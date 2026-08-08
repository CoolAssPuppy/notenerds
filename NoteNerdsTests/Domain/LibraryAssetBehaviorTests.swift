import XCTest
@testable import NoteNerds

final class LibraryAssetBehaviorTests: XCTestCase {
    func testLibraryAssetSurvivesPersistenceRoundTrip() throws {
        let asset = DocumentAsset(id: AssetID(), data: Data("asset".utf8), contentType: "image/png")
        var library = LibraryState()
        library.storeAsset(asset)

        let data = try JSONEncoder().encode(library)
        let restored = try JSONDecoder().decode(LibraryState.self, from: data)

        XCTAssertEqual(restored.asset(id: asset.id), asset)
    }
}
