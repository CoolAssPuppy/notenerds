import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class NotionPayloadBuilderTests: XCTestCase {
    func testBuildCreatesOnlyLowResolutionPreviewsAndAStableContentHash() async throws {
        let notebook = DomainFixtures.notebook()
        let library = LibraryState(notebooks: [notebook])

        let payload = try await NotionNotebookPayloadBuilder().build(
            notebook: notebook,
            library: library,
            exportedAt: DomainFixtures.fixedDate
        )
        XCTAssertTrue(payload.nativeArchive.isEmpty)
        XCTAssertTrue(payload.pdf.isEmpty)
        XCTAssertEqual(payload.snapshot.row.contentHash.count, 64)
        let expectedCanvasIDs = Set(notebook.canvases.map { $0.id.rawValue.uuidString.lowercased() })
        XCTAssertEqual(Set(payload.previews.keys), expectedCanvasIDs)
        for preview in payload.previews.values {
            let image = try XCTUnwrap(UIImage(data: preview))
            let width = try XCTUnwrap(image.cgImage?.width)
            let height = try XCTUnwrap(image.cgImage?.height)
            XCTAssertLessThanOrEqual(max(width, height), 512)
        }
    }

    func testUnchangedNotebookProducesTheSameArchiveAcrossSeparateSyncTimes() async throws {
        let notebook = DomainFixtures.notebook()
        let library = LibraryState(notebooks: [notebook])
        let builder = NotionNotebookPayloadBuilder()

        let first = try await builder.build(
            notebook: notebook,
            library: library,
            exportedAt: DomainFixtures.fixedDate
        )
        let second = try await builder.build(
            notebook: notebook,
            library: library,
            exportedAt: DomainFixtures.fixedDate.addingTimeInterval(3_600)
        )

        XCTAssertTrue(first.nativeArchive.isEmpty)
        XCTAssertTrue(second.nativeArchive.isEmpty)
        XCTAssertEqual(first.snapshot.row.contentHash, second.snapshot.row.contentHash)
    }

    func testDuplicateCanvasIdentifiersStopSyncWithoutCrashingTheApp() async {
        var notebook = DomainFixtures.notebook()
        notebook.canvases.append(notebook.canvases[0])

        do {
            _ = try await NotionNotebookPayloadBuilder().build(
                notebook: notebook,
                library: LibraryState(notebooks: [notebook]),
                exportedAt: DomainFixtures.fixedDate
            )
            XCTFail("Expected duplicate canvas identifiers to stop the payload")
        } catch {
            XCTAssertEqual(
                error as? NotionNotebookPayloadError,
                .duplicateCanvasIdentifier(notebook.canvases[0].id)
            )
        }
    }

    func testReferencePayloadDoesNotCopyOriginalAssets() async throws {
        let referencedID = AssetID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let unrelatedID = AssetID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        var notebook = DomainFixtures.notebook()
        let layerID = notebook.canvases[0].layers[0].id
        notebook.canvases[0].layers[0].objects.append(
            .image(
                ImageObject(
                    id: ObjectID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
                    layerID: layerID,
                    assetID: referencedID,
                    frame: CanvasRect(x: 0, y: 0, width: 20, height: 20),
                    rotation: 0
                )
            )
        )
        var library = LibraryState(notebooks: [notebook])
        library.storeAsset(DocumentAsset(id: referencedID, data: Data("image".utf8), contentType: "image/png"))
        library.storeAsset(DocumentAsset(id: unrelatedID, data: Data("other".utf8), contentType: "image/png"))

        let payload = try await NotionNotebookPayloadBuilder().build(
            notebook: notebook,
            library: library,
            exportedAt: DomainFixtures.fixedDate
        )
        XCTAssertTrue(payload.nativeArchive.isEmpty)
        XCTAssertTrue(payload.pdf.isEmpty)
    }

    func testMissingReferencedAssetDoesNotBlockReferencePublishing() async throws {
        let missingID = AssetID(rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
        var notebook = DomainFixtures.notebook()
        let layerID = notebook.canvases[0].layers[0].id
        notebook.canvases[0].layers[0].objects.append(
            .image(
                ImageObject(
                    id: ObjectID(),
                    layerID: layerID,
                    assetID: missingID,
                    frame: CanvasRect(x: 0, y: 0, width: 20, height: 20),
                    rotation: 0
                )
            )
        )

        let payload = try await NotionNotebookPayloadBuilder().build(
            notebook: notebook,
            library: LibraryState(notebooks: [notebook]),
            exportedAt: DomainFixtures.fixedDate
        )

        XCTAssertTrue(payload.nativeArchive.isEmpty)
        XCTAssertTrue(payload.pdf.isEmpty)
    }
}
