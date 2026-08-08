import CloudKit
import Foundation

enum CloudKitSyncError: Error, Equatable {
    case malformedRecord
    case assetNotFound
}

actor CloudKitSyncProvider: SyncProvider {
    nonisolated let identifier = "cloudkit"
    private let container: CKContainer
    private let database: CKDatabase

    init(container: CKContainer = CKContainer.default()) {
        self.container = container
        database = container.privateCloudDatabase
    }

    func start() async throws {
        do {
            guard try await container.accountStatus() == .available else {
                throw SyncProviderFailure.accountUnavailable
            }
        } catch {
            throw syncFailure(from: error)
        }
    }

    func push(_ changes: [DocumentChange]) async throws {
        for batch in SyncPushBatcher.batches(changes, maximumCount: 200) {
            try await pushBatch(batch)
        }
    }

    func pull(since cursor: SyncCursor?) async throws -> SyncBatch {
        let minimumSequence = cursor?.sequence ?? Int.min
        let query = CKQuery(
            recordType: RecordType.change,
            predicate: NSPredicate(format: "%K > %d", Field.sequence, minimumSequence)
        )
        query.sortDescriptors = [NSSortDescriptor(key: Field.sequence, ascending: true)]
        do {
            var page = try await database.records(
                matching: query,
                resultsLimit: CKQueryOperation.maximumResults
            )
            var changes = try decodedChanges(page.matchResults)
            while let queryCursor = page.queryCursor {
                page = try await database.records(
                    continuingMatchFrom: queryCursor,
                    resultsLimit: CKQueryOperation.maximumResults
                )
                changes.append(contentsOf: try decodedChanges(page.matchResults))
            }
            changes.sort { $0.sequence < $1.sequence }
            return SyncBatch(
                changes: changes,
                cursor: changes.last.map { SyncCursor(sequence: $0.sequence) } ?? cursor
            )
        } catch {
            throw syncFailure(from: error)
        }
    }

    func uploadAsset(_ asset: DocumentAsset) async throws {
        let recordID = CKRecord.ID(recordName: asset.id.rawValue.uuidString)
        let record = CKRecord(recordType: RecordType.asset, recordID: recordID)
        let directoryURL = temporaryDirectory()
        let assetURL = directoryURL.appending(path: asset.id.rawValue.uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        record[Field.contentType] = asset.contentType as CKRecordValue
        do {
            try createProtectedFile(asset.data, at: assetURL)
            record[Field.data] = CKAsset(fileURL: assetURL)
            _ = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
        } catch {
            throw syncFailure(from: error)
        }
    }

    func fetchAsset(_ id: AssetID) async throws -> Data {
        let recordID = CKRecord.ID(recordName: id.rawValue.uuidString)
        do {
            let record = try await database.record(for: recordID)
            return try payloadData(from: record)
        } catch {
            throw syncFailure(from: error)
        }
    }

    private func pushBatch(_ changes: [DocumentChange]) async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let records = try changes.map { change in
                let payloadURL = directoryURL.appending(path: change.id.rawValue.uuidString)
                try createProtectedFile(change.payload, at: payloadURL)
                return record(for: change, payloadURL: payloadURL)
            }
            _ = try await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
        } catch {
            throw syncFailure(from: error)
        }
    }

    private func record(for change: DocumentChange, payloadURL: URL) -> CKRecord {
        let recordID = CKRecord.ID(recordName: change.id.rawValue.uuidString)
        let record = CKRecord(recordType: RecordType.change, recordID: recordID)
        record[Field.notebookID] = change.notebookID.rawValue.uuidString as CKRecordValue
        record[Field.objectKey] = change.objectKey as CKRecordValue
        record[Field.kind] = change.kind.rawValue as CKRecordValue
        record[Field.data] = CKAsset(fileURL: payloadURL)
        record[Field.timestamp] = change.timestamp as CKRecordValue
        record[Field.deviceID] = change.deviceID as CKRecordValue
        record[Field.sequence] = change.sequence as CKRecordValue
        return record
    }

    private func change(from record: CKRecord) throws -> DocumentChange {
        guard let changeUUID = UUID(uuidString: record.recordID.recordName),
              let notebookValue = record[Field.notebookID] as? String,
              let notebookUUID = UUID(uuidString: notebookValue),
              let objectKey = record[Field.objectKey] as? String,
              let kindValue = record[Field.kind] as? String,
              let kind = DocumentChangeKind(rawValue: kindValue),
              let timestamp = record[Field.timestamp] as? Date,
              let deviceID = record[Field.deviceID] as? String,
              let sequence = record[Field.sequence] as? Int else {
            throw CloudKitSyncError.malformedRecord
        }
        let payload = try payloadData(from: record)
        return DocumentChange(
            id: ChangeID(rawValue: changeUUID),
            notebookID: NotebookID(rawValue: notebookUUID),
            objectKey: objectKey,
            kind: kind,
            payload: payload,
            timestamp: timestamp,
            deviceID: deviceID,
            sequence: sequence
        )
    }

    private func decodedChanges(
        _ results: [(CKRecord.ID, Result<CKRecord, any Error>)]
    ) throws -> [DocumentChange] {
        try results.map { _, recordResult in try change(from: recordResult.get()) }
    }

    private func payloadData(from record: CKRecord) throws -> Data {
        if let data = record[Field.data] as? Data { return data }
        guard let asset = record[Field.data] as? CKAsset, let fileURL = asset.fileURL else {
            throw CloudKitSyncError.assetNotFound
        }
        return try BoundedFileReader().read(from: fileURL)
    }

    private func createProtectedFile(_ data: Data, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "NoteNerdsCloudKit", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func syncFailure(from error: Error) -> SyncProviderFailure {
        if let failure = error as? SyncProviderFailure { return failure }
        guard let cloudError = error as? CKError else { return .persistent }
        switch cloudError.code {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .accountUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy:
            return .serviceUnavailable
        default:
            return .persistent
        }
    }
}

private enum RecordType {
    static let change = "DocumentChange"
    static let asset = "DocumentAsset"
}

private enum Field {
    static let notebookID = "notebookID"
    static let objectKey = "objectKey"
    static let kind = "kind"
    static let data = "data"
    static let timestamp = "timestamp"
    static let deviceID = "deviceID"
    static let sequence = "sequence"
    static let contentType = "contentType"
}

enum DefaultSyncProvider {
    static func make() -> (any SyncProvider)? {
        guard CloudKitRuntime.isAvailable else {
            return nil
        }
        return CloudKitSyncProvider()
    }
}

enum CloudKitRuntime {
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }
}
