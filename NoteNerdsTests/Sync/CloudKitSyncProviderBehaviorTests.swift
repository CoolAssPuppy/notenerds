import CloudKit
import XCTest
@testable import NoteNerds

final class CloudKitSyncProviderBehaviorTests: XCTestCase {
    func testFailedLowerSequenceChangeDoesNotAttemptHigherSequenceChange() async {
        let recordSaver = SequenceFailingRecordSaver(failingSequence: 1)
        let provider = CloudKitSyncProvider(recordSaver: recordSaver)
        let changes = [
            DocumentChange.fixture(objectKey: "folder:second", sequence: 2),
            DocumentChange.fixture(objectKey: "folder:first", sequence: 1)
        ]

        do {
            try await provider.push(changes)
            XCTFail("Expected the failed CloudKit record to keep the batch waiting for retry")
        } catch {
            XCTAssertEqual(error as? SyncProviderFailure, .persistent)
        }

        let request = await recordSaver.requestSnapshot()
        XCTAssertEqual(request.sequences, [1])
        XCTAssertEqual(request.recordCounts, [1])
        XCTAssertEqual(request.zoneNames, [CKRecordZone.ID.defaultZoneName])
    }

    func testReturnedChangeRecordFailureIsReportedForRetry() async {
        let recordSaver = LaterRecordFailingSaver()
        let provider = CloudKitSyncProvider(recordSaver: recordSaver)
        let changes = [
            DocumentChange.fixture(objectKey: "folder:first", sequence: 1),
            DocumentChange.fixture(objectKey: "folder:second", sequence: 2)
        ]

        do {
            try await provider.push(changes)
            XCTFail("Expected the failed CloudKit record to keep the batch waiting for retry")
        } catch {
            XCTAssertEqual(error as? SyncProviderFailure, .persistent)
        }

        let requestedSequences = await recordSaver.requestedSequences()
        XCTAssertEqual(requestedSequences, [1, 2])
    }

    func testFailedCloudKitAssetSaveIsReportedForRetry() async {
        let recordSaver = FailingRecordSaver()
        let provider = CloudKitSyncProvider(recordSaver: recordSaver)
        let asset = DocumentAsset(
            id: AssetID(),
            data: Data("folder icon".utf8),
            contentType: "image/png"
        )

        do {
            try await provider.uploadAsset(asset)
            XCTFail("Expected the failed CloudKit asset to remain waiting for retry")
        } catch {
            XCTAssertEqual(error as? SyncProviderFailure, .persistent)
        }

        let recordCounts = await recordSaver.recordCounts()
        XCTAssertEqual(recordCounts, [1])
    }

    func testFolderMutationWithMismatchedNotebookObjectKeyIsRejected() throws {
        let folder = Folder(
            name: "Work",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let original = try SyncChangeEncoder(deviceID: "device").change(
            for: .updateFolder(folder),
            notebookID: NotebookID(rawValue: folder.id.rawValue),
            sequence: 10,
            timestamp: DomainFixtures.fixedDate
        )
        let mismatched = DocumentChange(
            id: original.id,
            notebookID: original.notebookID,
            objectKey: "notebook:\(folder.id.rawValue.uuidString)",
            kind: original.kind,
            payload: original.payload,
            timestamp: original.timestamp,
            deviceID: original.deviceID,
            sequence: original.sequence
        )

        XCTAssertThrowsError(try SyncChangeEncoder.decodeLibraryMutation(mismatched)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .coderInvalidValue)
        }
    }

    func testOversizedFolderEnvelopeWithMismatchedDocumentObjectKeyIsRejected() throws {
        let folder = Folder(
            name: String(
                repeating: "a",
                count: SyncChangeEncoder.maximumLibraryMutationPayloadByteCount + 1
            ),
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let payload = try Self.encodePayload(.library(.updateFolder(folder)))
        let change = DocumentChange(
            id: ChangeID(),
            notebookID: NotebookID(rawValue: folder.id.rawValue),
            objectKey: "stroke:\(UUID().uuidString)",
            kind: .upsert,
            payload: payload,
            timestamp: DomainFixtures.fixedDate,
            deviceID: "device",
            sequence: 11
        )
        XCTAssertGreaterThan(payload.count, SyncChangeEncoder.maximumLibraryMutationPayloadByteCount)
        XCTAssertEqual(
            SyncChangeEncoder.maximumPayloadByteCount(
                forEnvelopePrefix: Data(payload.prefix(SyncChangeEncoder.maximumEnvelopePrefixByteCount))
            ),
            SyncChangeEncoder.maximumLibraryMutationPayloadByteCount
        )

        XCTAssertThrowsError(try SyncChangeEncoder.decodeLibraryMutation(change)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadTooLarge)
        }
    }

    private static func encodePayload(_ payload: SyncPayloadFixture) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(payload)
    }
}

private enum SyncPayloadFixture: Codable {
    case library(LibrarySyncMutation)
}

private struct RecordSaveRequestSnapshot: Sendable {
    let sequences: [Int]
    let recordCounts: [Int]
    let zoneNames: [String]
}

private actor SequenceFailingRecordSaver: CloudKitRecordSaving {
    private let failingSequence: Int
    private var requestedSequences: [Int] = []
    private var requestedRecordCounts: [Int] = []
    private var requestedZoneNames: [String] = []

    init(failingSequence: Int) {
        self.failingSequence = failingSequence
    }

    func save(
        _ records: [CKRecord]
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        requestedSequences.append(contentsOf: records.compactMap(sequence(from:)))
        requestedRecordCounts.append(records.count)
        requestedZoneNames.append(contentsOf: records.map(\.recordID.zoneID.zoneName))

        return Dictionary(uniqueKeysWithValues: records.map { record in
            let failed = sequence(from: record) == failingSequence
            let result: Result<CKRecord, any Error> = failed
                ? .failure(CocoaError(.fileWriteUnknown))
                : .success(record)
            return (record.recordID, result)
        })
    }

    func requestSnapshot() -> RecordSaveRequestSnapshot {
        RecordSaveRequestSnapshot(
            sequences: requestedSequences,
            recordCounts: requestedRecordCounts,
            zoneNames: requestedZoneNames
        )
    }

    private func sequence(from record: CKRecord) -> Int? {
        record["sequence"] as? Int
    }
}

private actor LaterRecordFailingSaver: CloudKitRecordSaving {
    private var sequences: [Int] = []

    func save(
        _ records: [CKRecord]
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        sequences.append(contentsOf: records.compactMap { $0["sequence"] as? Int })
        return Dictionary(uniqueKeysWithValues: records.map { record in
            let result: Result<CKRecord, any Error> = record["sequence"] as? Int == 2
                ? .failure(CocoaError(.fileWriteUnknown))
                : .success(record)
            return (record.recordID, result)
        })
    }

    func requestedSequences() -> [Int] {
        sequences
    }
}

private actor FailingRecordSaver: CloudKitRecordSaving {
    private var requestedRecordCounts: [Int] = []

    func save(
        _ records: [CKRecord]
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        requestedRecordCounts.append(records.count)
        return Dictionary(uniqueKeysWithValues: records.map { record in
            (record.recordID, .failure(CocoaError(.fileWriteUnknown)))
        })
    }

    func recordCounts() -> [Int] {
        requestedRecordCounts
    }
}
