import PDFKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class NotionPayloadBuilderTests: XCTestCase {
    func testBuildCreatesRestorableArchiveFullPDFPreviewsAndExactContentHash() async throws {
        let notebook = DomainFixtures.notebook()
        let library = LibraryState(notebooks: [notebook])

        let payload = try await NotionNotebookPayloadBuilder().build(
            notebook: notebook,
            library: library,
            exportedAt: DomainFixtures.fixedDate
        )
        let archive = try NotionTransportFile.decode(payload.nativeArchive)
        let restored = try NotionTransportArchive().decode(archive)

        XCTAssertEqual(
            restored.package,
            NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        )
        XCTAssertEqual(restored.assets, [])
        XCTAssertEqual(
            payload.snapshot.row.contentHash,
            NotionContentHasher.sha256Hex(of: payload.nativeArchive)
        )
        XCTAssertEqual(PDFDocument(data: payload.pdf)?.pageCount, notebook.canvases.count)
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

        XCTAssertEqual(first.nativeArchive, second.nativeArchive)
        XCTAssertEqual(first.snapshot.row.contentHash, second.snapshot.row.contentHash)
    }

    func testUnchangedBackgroundPublishSkipsRenderingAndEveryNotionRequest() async throws {
        let notebook = DomainFixtures.notebook()
        let library = LibraryState(notebooks: [notebook])
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let manifestPageID = "33333333-3333-3333-3333-333333333333"
        let renderer = RejectingNotebookPayloadRenderer()
        let payloadBuilder = NotionNotebookPayloadBuilder(renderer: renderer)
        let preparation = try await payloadBuilder.prepare(
            notebook: notebook,
            library: library,
            exportedAt: DomainFixtures.fixedDate
        )
        let manifest = NotionLibraryManifest(
            library: library,
            databaseID: destination.databaseID,
            dataSourceID: destination.dataSourceID,
            generatedAt: DomainFixtures.fixedDate
        )
        let registry = NotionSyncRegistry(store: PayloadPublisherStateStore(state: NotionSyncState(
            workspaceID: "workspace",
            destination: destination,
            manifestPageID: manifestPageID,
            manifestContentHash: try NotionLibraryManifestCodec.contentHash(manifest),
            bindings: [NotionNotebookBinding(
                notebookID: preparation.snapshot.row.notebookID,
                pageID: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
                managedRootBlockID: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE",
                contentHash: preparation.snapshot.row.contentHash,
                syncedAt: DomainFixtures.fixedDate,
                notionLastEditedAt: nil
            )]
        )))
        let notion = RequestCountingNotionAPI()
        let publisher = NotionLibraryPublisher(
            api: notion,
            registry: registry,
            payloadBuilder: payloadBuilder,
            now: { DomainFixtures.fixedDate }
        )

        let report = try await publisher.publish(library)
        let requestCount = await notion.requestCount

        XCTAssertEqual(report.skippedNotebookCount, 1)
        XCTAssertEqual(renderer.renderCount, 0)
        XCTAssertEqual(requestCount, 0)
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

    func testArchiveIncludesReferencedAssetsAndExcludesUnrelatedAssets() async throws {
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
        let archive = try NotionTransportFile.decode(payload.nativeArchive)
        let restored = try NotionTransportArchive().decode(archive)

        XCTAssertEqual(restored.assets.map(\.id), [referencedID])
    }

    func testMissingReferencedAssetStopsTheExport() async {
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

        do {
            _ = try await NotionNotebookPayloadBuilder().build(
                notebook: notebook,
                library: LibraryState(notebooks: [notebook]),
                exportedAt: DomainFixtures.fixedDate
            )
            XCTFail("Expected a missing asset to fail")
        } catch {
            XCTAssertEqual(error as? NotionNotebookPayloadError, .missingAsset(missingID))
        }
    }

    func testEmptyReferencedAssetStopsTheExport() async {
        let emptyID = AssetID(rawValue: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
        var notebook = DomainFixtures.notebook()
        let layerID = notebook.canvases[0].layers[0].id
        notebook.canvases[0].layers[0].objects.append(
            .pdf(
                PDFObject(
                    id: ObjectID(),
                    layerID: layerID,
                    assetID: emptyID,
                    frame: CanvasRect(x: 0, y: 0, width: 20, height: 20),
                    pageIndex: 0,
                    embeddedText: nil
                )
            )
        )
        var library = LibraryState(notebooks: [notebook])
        library.storeAsset(DocumentAsset(id: emptyID, data: Data(), contentType: "application/pdf"))

        do {
            _ = try await NotionNotebookPayloadBuilder().build(
                notebook: notebook,
                library: library,
                exportedAt: DomainFixtures.fixedDate
            )
            XCTFail("Expected an empty asset to fail")
        } catch {
            XCTAssertEqual(error as? NotionNotebookPayloadError, .missingAsset(emptyID))
        }
    }
}

@MainActor
private final class RejectingNotebookPayloadRenderer: NotionNotebookPayloadRendering {
    private(set) var renderCount = 0

    func render(
        _ preparation: NotionNotebookPayloadPreparation,
        maximumPreviewDimension: Double
    ) throws -> NotionNotebookPayload {
        renderCount += 1
        throw NotionAPIError.invalidResponse
    }
}

private actor PayloadPublisherStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?

    init(state: NotionSyncState?) { self.state = state }

    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}

private actor RequestCountingNotionAPI: NotionSyncAPI {
    private(set) var requestCount = 0

    func uploadFile(data: Data, filename: String, contentType: String) -> String {
        requestCount += 1
        return "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    }

    func findNotebookPage(dataSourceID: String, notebookID: String) -> NotionPageBinding? {
        requestCount += 1
        return nil
    }

    func createNotebookPage(
        dataSourceID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) -> NotionPageBinding {
        requestCount += 1
        return NotionPageBinding(pageID: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", url: nil)
    }

    func updateNotebookPage(
        pageID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) -> NotionPageBinding {
        requestCount += 1
        return NotionPageBinding(pageID: pageID, url: nil)
    }

    func findManagedRootBlock(pageID: String, notebookID: String) -> String? {
        requestCount += 1
        return nil
    }

    func trashNotebookPage(pageID: String) {
        requestCount += 1
    }

    func replaceManagedPage(
        pageID: String,
        oldRootID: String?,
        plan: NotionManagedPagePlan
    ) -> String {
        requestCount += 1
        return "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
    }
}
