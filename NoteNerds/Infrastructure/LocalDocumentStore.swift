import Foundation

enum LocalDocumentStoreError: Error, Equatable {
    case notebookNotFound
    case unsupportedStorageVersion(Int)
}

actor LocalDocumentStore {
    private struct SnapshotEnvelope: Codable {
        static let currentStorageVersion = 1

        let storageVersion: Int
        let journalWatermark: UInt64
        let package: NativeNotebookPackage
    }

    private struct DecodedSnapshot {
        let envelope: SnapshotEnvelope
        let isLegacy: Bool
        /// The schema version the file was written with, before normalisation.
        let storedSchemaVersion: DocumentSchemaVersion
    }

    private let rootURL: URL
    private let serializer = NativeDocumentSerializer()
    private let fileManager = FileManager.default
    private let readData: @Sendable (URL) throws -> Data
    private let afterSnapshotWrite: @Sendable () throws -> Void
    private let afterJournalWrite: @Sendable () throws -> Void
    private var journalSequences: [NotebookID: UInt64] = [:]

    init(
        rootURL: URL,
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        afterSnapshotWrite: @escaping @Sendable () throws -> Void = {},
        afterJournalWrite: @escaping @Sendable () throws -> Void = {}
    ) {
        self.rootURL = rootURL
        self.readData = readData
        self.afterSnapshotWrite = afterSnapshotWrite
        self.afterJournalWrite = afterJournalWrite
    }

    func save(_ package: NativeNotebookPackage) throws {
        try CanvasDiagnostics.measure("snapshot save \(package.notebook.title)") {
            try performSave(package)
        }
    }

    private func performSave(_ package: NativeNotebookPackage) throws {
        try createDirectories()
        let notebookID = package.notebook.id
        let watermark = try currentJournalSequence(for: notebookID)
        let encoded = try encode(SnapshotEnvelope(
            storageVersion: SnapshotEnvelope.currentStorageVersion,
            journalWatermark: watermark,
            package: package
        ))
        try encoded.write(to: snapshotURL(for: package.notebook.id), options: [.atomic, .completeFileProtection])
        try afterSnapshotWrite()
        let journalURL = journalURL(for: notebookID)
        if fileManager.fileExists(atPath: journalURL.path()) {
            try fileManager.removeItem(at: journalURL)
        }
        try DocumentJournal.removeSidecars(for: notebookID, journalsURL: journalsURL)
        journalSequences[notebookID] = watermark
    }

    func load(notebookID: NotebookID) throws -> NativeNotebookPackage {
        let url = snapshotURL(for: notebookID)
        do {
            let decodedSnapshot = try decodeSnapshot(readData(url))
            let snapshot = decodedSnapshot.envelope
            journalSequences[notebookID] = max(
                journalSequences[notebookID, default: 0],
                snapshot.journalWatermark
            )
            var package = snapshot.package
            let wasRepaired = package.repairStrokeArchivesIfWrittenBeforeSelfInvalidation(
                storedVersion: decodedSnapshot.storedSchemaVersion
            )
            if decodedSnapshot.isLegacy || wasRepaired {
                try save(package)
            }
            return package
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw LocalDocumentStoreError.notebookNotFound
        }
    }

    func append(_ operation: DocumentOperation, notebookID: NotebookID) throws {
        try append(
            SyncedDocumentAction(operation: operation, direction: .apply),
            notebookID: notebookID
        )
    }

    func append(_ action: SyncedDocumentAction, notebookID: NotebookID) throws {
        try createDirectories()
        let url = journalURL(for: notebookID)
        try removeInterruptedFinalRecord(at: url)
        let sequence = try currentJournalSequence(for: notebookID) + 1
        let prepared = DocumentJournal.preparing(action)
        if !prepared.sidecar.isEmpty {
            try DocumentJournal.writeSidecar(
                prepared.sidecar,
                notebookID: notebookID,
                sequence: sequence,
                journalsURL: journalsURL
            )
        }
        var encoded = try encode(DocumentJournalEntry(
            storageVersion: DocumentJournal.currentStorageVersion,
            sequence: sequence,
            action: prepared.action,
            sidecarCount: prepared.sidecar.count
        ))
        encoded.append(0x0A)
        if fileManager.fileExists(atPath: url.path()) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: encoded)
            try handle.close()
        } else {
            try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        }
        try afterJournalWrite()
        journalSequences[notebookID] = sequence
    }

    func recover(notebookID: NotebookID) throws -> NativeNotebookPackage {
        let decodedSnapshot: DecodedSnapshot
        do {
            decodedSnapshot = try decodeSnapshot(readData(snapshotURL(for: notebookID)))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw LocalDocumentStoreError.notebookNotFound
        }
        let snapshot = decodedSnapshot.envelope
        var package = snapshot.package
        var needsRewrite = decodedSnapshot.isLegacy
        if let data = try journalData(for: notebookID) {
            let isLegacyJournalCovered = decodedSnapshot.isLegacy
                && isSnapshotNewerThanJournal(for: notebookID)
            needsRewrite = try applyJournal(
                data,
                to: &package,
                notebookID: notebookID,
                snapshotWatermark: snapshot.journalWatermark,
                isLegacyJournalCovered: isLegacyJournalCovered
            ) || needsRewrite
        } else {
            journalSequences[notebookID] = snapshot.journalWatermark
        }
        // Repair before writing, so a note rewritten here is not stamped at the
        // current version while still holding ink from an older build. Writing
        // it back is what stops the repair running again on every launch.
        let wasRepaired = package.repairStrokeArchivesIfWrittenBeforeSelfInvalidation(
            storedVersion: decodedSnapshot.storedSchemaVersion
        )
        if needsRewrite || wasRepaired {
            try save(package)
        }
        return package
    }

    private func journalData(for notebookID: NotebookID) throws -> Data? {
        do {
            return try readData(journalURL(for: notebookID))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func applyJournal(
        _ data: Data,
        to package: inout NativeNotebookPackage,
        notebookID: NotebookID,
        snapshotWatermark: UInt64,
        isLegacyJournalCovered: Bool
    ) throws -> Bool {
        let decoder = makeDecoder()
        let lines = data.split(separator: 0x0A)
        var hasLegacyEntries = false
        for (index, line) in lines.enumerated() {
            do {
                let lineData = Data(line)
                if let entry = try? decoder.decode(DocumentJournalEntry.self, from: lineData) {
                    try apply(entry, to: &package, notebookID: notebookID, watermark: snapshotWatermark)
                } else {
                    hasLegacyEntries = true
                    let operation = try decoder.decode(DocumentOperation.self, from: lineData)
                    let sequence = UInt64(index + 1)
                    recordSequence(sequence, notebookID: notebookID, watermark: snapshotWatermark)
                    if sequence > snapshotWatermark, !isLegacyJournalCovered {
                        try operation.apply(to: &package.notebook)
                    }
                }
            } catch where index == lines.count - 1 && data.last != 0x0A {
                break
            }
        }
        return hasLegacyEntries
    }

    private func apply(
        _ entry: DocumentJournalEntry,
        to package: inout NativeNotebookPackage,
        notebookID: NotebookID,
        watermark: UInt64
    ) throws {
        try validateStorageVersion(entry.storageVersion, maximum: DocumentJournal.currentStorageVersion)
        recordSequence(entry.sequence, notebookID: notebookID, watermark: watermark)
        guard entry.sequence > watermark else { return }
        let action: SyncedDocumentAction
        if entry.sidecarCount > 0 {
            guard let sidecar = try DocumentJournal.readSidecar(
                notebookID: notebookID,
                sequence: entry.sequence,
                journalsURL: journalsURL
            ), sidecar.count == entry.sidecarCount else { return }
            action = DocumentJournal.restoring(entry.action, sidecar: sidecar)
        } else {
            action = entry.action
        }
        try action.perform(on: &package.notebook)
    }

    private func recordSequence(_ sequence: UInt64, notebookID: NotebookID, watermark: UInt64) {
        journalSequences[notebookID] = max(
            journalSequences[notebookID, default: watermark],
            sequence
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private func decodeSnapshot(_ data: Data) throws -> DecodedSnapshot {
        let decoder = makeDecoder()
        if let envelope = try? decoder.decode(SnapshotEnvelope.self, from: data) {
            try validateStorageVersion(envelope.storageVersion, maximum: SnapshotEnvelope.currentStorageVersion)
            var package = try serializer.validatedPackage(envelope.package)
            package.notebook = PencilKitStrokeArchiveCodec.restoringSamples(in: package.notebook)
            return DecodedSnapshot(
                envelope: SnapshotEnvelope(
                    storageVersion: envelope.storageVersion,
                    journalWatermark: envelope.journalWatermark,
                    package: package
                ),
                isLegacy: false,
                storedSchemaVersion: envelope.package.schemaVersion
            )
        }
        return DecodedSnapshot(
            envelope: SnapshotEnvelope(
                storageVersion: SnapshotEnvelope.currentStorageVersion,
                journalWatermark: 0,
                package: try serializer.decode(data)
            ),
            isLegacy: true,
            storedSchemaVersion: .current
        )
    }

    private func validateStorageVersion(_ version: Int, maximum: Int) throws {
        guard version <= maximum else {
            throw LocalDocumentStoreError.unsupportedStorageVersion(version)
        }
    }

    private func currentJournalSequence(for notebookID: NotebookID) throws -> UInt64 {
        if let sequence = journalSequences[notebookID] { return sequence }
        var sequence: UInt64 = 0
        if let data = try? readData(snapshotURL(for: notebookID)) {
            sequence = try decodeSnapshot(data).envelope.journalWatermark
        }
        if let data = try? readData(journalURL(for: notebookID)) {
            let decoder = makeDecoder()
            for (index, line) in data.split(separator: 0x0A).enumerated() {
                if let entry = try? decoder.decode(DocumentJournalEntry.self, from: Data(line)) {
                    sequence = max(sequence, entry.sequence)
                } else if (try? decoder.decode(DocumentOperation.self, from: Data(line))) != nil {
                    sequence = max(sequence, UInt64(index + 1))
                }
            }
        }
        journalSequences[notebookID] = sequence
        return sequence
    }

    private func isSnapshotNewerThanJournal(for notebookID: NotebookID) -> Bool {
        let snapshotAttributes = try? fileManager.attributesOfItem(
            atPath: snapshotURL(for: notebookID).path()
        )
        let journalAttributes = try? fileManager.attributesOfItem(
            atPath: journalURL(for: notebookID).path()
        )
        guard let snapshotDate = snapshotAttributes?[.modificationDate] as? Date,
              let journalDate = journalAttributes?[.modificationDate] as? Date else { return false }
        return snapshotDate > journalDate
    }

    private func removeInterruptedFinalRecord(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path()) else { return }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, data.last != 0x0A else { return }
        let finalRecordStart = data.lastIndex(of: 0x0A).map { data.index(after: $0) } ?? data.startIndex
        let finalRecord = Data(data[finalRecordStart...])
        let decoder = makeDecoder()
        let isCompleteRecord = (try? decoder.decode(DocumentJournalEntry.self, from: finalRecord)) != nil
            || (try? decoder.decode(DocumentOperation.self, from: finalRecord)) != nil
        var repairedData: Data
        if isCompleteRecord {
            repairedData = data
            repairedData.append(0x0A)
        } else if let lastNewline = data.lastIndex(of: 0x0A) {
            repairedData = Data(data[...lastNewline])
        } else {
            repairedData = Data()
        }
        try repairedData.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func createDirectories() throws {
        try fileManager.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: journalsURL, withIntermediateDirectories: true)
    }

    private var snapshotsURL: URL { rootURL.appending(path: "Snapshots", directoryHint: .isDirectory) }
    private var journalsURL: URL { rootURL.appending(path: "Journals", directoryHint: .isDirectory) }

    private func snapshotURL(for notebookID: NotebookID) -> URL {
        snapshotsURL.appending(path: "\(notebookID.rawValue.uuidString).notenerds.json")
    }

    private func journalURL(for notebookID: NotebookID) -> URL {
        journalsURL.appending(path: "\(notebookID.rawValue.uuidString).journal")
    }
}
