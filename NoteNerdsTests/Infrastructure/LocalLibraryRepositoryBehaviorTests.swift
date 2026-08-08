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
        XCTAssertLessThan(metadata.count, 100_000)
        XCTAssertEqual(try Data(contentsOf: assetURL), asset.data)
        XCTAssertEqual(restored, library)
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

        XCTAssertEqual(restored.asset(id: assetID)?.data, Data("new".utf8))
    }
}
