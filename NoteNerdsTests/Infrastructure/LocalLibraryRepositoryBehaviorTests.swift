import XCTest
@testable import NoteNerds

final class LocalLibraryRepositoryBehaviorTests: XCTestCase {
    func testLargeAssetsAreStoredOnceOutsideFrequentlyWrittenLibraryMetadata() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fileURL = directoryURL.appending(path: "library.json")
        let repository = LocalLibraryRepository(fileURL: fileURL)
        let asset = DocumentAsset(
            id: AssetID(),
            data: Data(repeating: 0xAB, count: 1_000_000),
            contentType: "application/pdf"
        )
        var library = LibraryState(notebooks: [DomainFixtures.notebook()])
        library.storeAsset(asset)

        try await repository.save(library)

        let metadata = try Data(contentsOf: fileURL)
        let assetURL = directoryURL
            .appending(path: "Assets", directoryHint: .isDirectory)
            .appending(path: asset.id.rawValue.uuidString)
        let restored = try await repository.load()
        let loadedAsset = try await repository.loadAsset(id: asset.id, contentType: asset.contentType)
        XCTAssertLessThan(metadata.count, 100_000)
        XCTAssertEqual(try Data(contentsOf: assetURL), asset.data)
        XCTAssertEqual(restored.asset(id: asset.id)?.data, Data())
        XCTAssertEqual(loadedAsset?.data, asset.data)
    }

    func testSavingAReplacementAssetUpdatesThePersistedBytes() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let assetID = AssetID()
        var original = LibraryState()
        original.storeAsset(DocumentAsset(id: assetID, data: Data("old".utf8), contentType: "image/png"))
        try await repository.save(original)
        var replacement = LibraryState()
        replacement.storeAsset(DocumentAsset(id: assetID, data: Data("new".utf8), contentType: "image/png"))

        try await repository.save(replacement)
        let restored = try await repository.load()
        let loadedAsset = try await repository.loadAsset(id: assetID, contentType: "image/png")

        XCTAssertEqual(restored.asset(id: assetID)?.data, Data())
        XCTAssertEqual(loadedAsset?.data, Data("new".utf8))
    }

    func testLoadRejectsALibraryIndexLargerThanSixtyFourMegabytes() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fileURL = directoryURL.appending(path: "library.json")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: LocalLibraryRepository.maximumLibraryByteCount + 1)
            .write(to: fileURL)
        let repository = LocalLibraryRepository(fileURL: fileURL)

        do {
            _ = try await repository.load()
            XCTFail("Expected an oversized library index to fail")
        } catch {
            XCTAssertEqual(error as? BoundedFileReaderError, .fileTooLarge)
        }
    }
}
