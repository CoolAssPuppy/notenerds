import XCTest
@testable import NoteNerds

final class NotionTransportArchiveBehaviorTests: XCTestCase {
    func testSupportedJSONTransportFileRoundTripsTheBinaryArchiveDeterministically() throws {
        let archive = try encodedArchive()

        let first = try NotionTransportFile.encode(archive)
        let second = try NotionTransportFile.encode(archive)

        XCTAssertEqual(first, second)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: first) as? [String: Any])
        XCTAssertEqual(try NotionTransportFile.decode(first), archive)
        XCTAssertEqual(try NotionTransportFile.decode(archive), archive)
    }

    func testSupportedJSONTransportFileRejectsMalformedAndOversizedPayloads() throws {
        let malformed = Data(#"{"schemaVersion":1,"encoding":"base64","archive":"%%%"}"#.utf8)

        XCTAssertThrowsError(try NotionTransportFile.decode(malformed)) { error in
            XCTAssertEqual(error as? NotionTransportFileError, .invalidArchive)
        }
        XCTAssertThrowsError(
            try NotionTransportFile.decode(Data(repeating: 0x20, count: 128), maximumByteCount: 64),
            "A configured bound must reject the transport before JSON decoding"
        ) { error in
            XCTAssertEqual(error as? NotionTransportFileError, .fileTooLarge)
        }
    }

    func testTransportArchiveIsOneDeterministicFileThatRestoresEveryAsset() throws {
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook())
        let first = DocumentAsset.fixture(idSuffix: "01", text: "first", contentType: "image/png")
        let second = DocumentAsset.fixture(idSuffix: "02", text: "second", contentType: "application/pdf")
        let archive = NotionTransportArchive()

        let encoded = try archive.encode(
            package: package,
            assets: [second, first],
            exportedAt: DomainFixtures.fixedDate
        )
        let reordered = try archive.encode(
            package: package,
            assets: [first, second],
            exportedAt: DomainFixtures.fixedDate
        )
        let restored = try archive.decode(encoded)

        XCTAssertEqual(encoded, reordered)
        XCTAssertEqual(restored.package, package)
        XCTAssertEqual(restored.assets, [first, second])
        XCTAssertEqual(NotionContentHasher.sha256Hex(of: encoded).count, 64)
    }

    func testTransportArchiveRejectsChangedContent() throws {
        let data = try encodedArchive()
        var damaged = data
        damaged[damaged.index(before: damaged.endIndex)] ^= 0xff

        XCTAssertThrowsError(try NotionTransportArchive().decode(damaged)) { error in
            guard case NotionTransportArchiveError.checksumMismatch = error else {
                return XCTFail("Expected checksum mismatch, received \(error)")
            }
        }
    }

    func testTransportArchiveRejectsUnsafeAndDuplicatePaths() throws {
        let original = try encodedArchive(assetCount: 2)
        let unsafe = try replacingIndexText(
            in: original,
            target: "Assets/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA01",
            replacement: "../bad/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA01"
        )
        let duplicate = try replacingIndexText(
            in: original,
            target: "Assets/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA02",
            replacement: "Assets/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA01"
        )

        XCTAssertThrowsError(try NotionTransportArchive().decode(unsafe)) { error in
            XCTAssertEqual(error as? NotionTransportArchiveError, .unsafePath)
        }
        XCTAssertThrowsError(try NotionTransportArchive().decode(duplicate)) { error in
            XCTAssertEqual(error as? NotionTransportArchiveError, .duplicatePath)
        }
    }

    func testTransportArchiveRejectsNewerSchemasAndConfiguredBounds() throws {
        let original = try encodedArchive()
        let newer = try replacingIndexText(
            in: original,
            target: #""schemaVersion":1"#,
            replacement: #""schemaVersion":9"#
        )
        let smallLimits = NotionTransportLimits(
            maximumEntryCount: 10,
            maximumIndexByteCount: 10_000,
            maximumMetadataByteCount: 10_000,
            maximumAssetByteCount: 3
        )

        XCTAssertThrowsError(try NotionTransportArchive().decode(newer)) { error in
            XCTAssertEqual(error as? NotionTransportArchiveError, .unsupportedSchema(9))
        }
        XCTAssertThrowsError(try NotionTransportArchive(limits: smallLimits).decode(original)) { error in
            XCTAssertEqual(error as? NotionTransportArchiveError, .assetsTooLarge)
        }
    }

    func testTransportArchiveRejectsTruncationAndTrailingBytes() throws {
        let original = try encodedArchive()
        let truncated = original.dropLast()
        var trailing = original
        trailing.append(0)

        XCTAssertThrowsError(try NotionTransportArchive().decode(Data(truncated)))
        XCTAssertThrowsError(try NotionTransportArchive().decode(trailing)) { error in
            XCTAssertEqual(error as? NotionTransportArchiveError, .invalidLength)
        }
    }

    private func encodedArchive(assetCount: Int = 1) throws -> Data {
        let assets = (1...assetCount).map { index in
            DocumentAsset.fixture(
                idSuffix: String(format: "%02d", index),
                text: String(repeating: "a", count: 4),
                contentType: "image/png"
            )
        }
        return try NotionTransportArchive().encode(
            package: NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook()),
            assets: assets,
            exportedAt: DomainFixtures.fixedDate
        )
    }

    private func replacingIndexText(in archive: Data, target: String, replacement: String) throws -> Data {
        let headerSize = 16
        let indexLength = archive[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let indexEnd = headerSize + Int(indexLength)
        let indexData = archive[headerSize..<indexEnd]
        let indexText = try XCTUnwrap(String(data: indexData, encoding: .utf8))
        let changedText = indexText.replacingOccurrences(of: target, with: replacement)
        XCTAssertNotEqual(changedText, indexText)
        var changed = Data("NNARCH01".utf8)
        changed.append(contentsOf: UInt64(changedText.utf8.count).bigEndianBytes)
        changed.append(Data(changedText.utf8))
        changed.append(archive[indexEnd...])
        return changed
    }
}

private extension DocumentAsset {
    static func fixture(idSuffix: String, text: String, contentType: String) -> DocumentAsset {
        DocumentAsset(
            id: AssetID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA\(idSuffix)")!),
            data: Data(text.utf8),
            contentType: contentType
        )
    }
}

private extension UInt64 {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}
