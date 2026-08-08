import XCTest
@testable import NoteNerds

@MainActor
final class AppSessionPersistenceBehaviorTests: XCTestCase {
    func testNotebookAndCanvasTextRestoreInANewApplicationModel() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let firstSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await firstSession.restoreLibrary()
        firstSession.createNotebook()
        let notebookID = try XCTUnwrap(firstSession.selectedNotebookID)
        let notebook = try XCTUnwrap(firstSession.notebook(notebookID))
        let canvas = try XCTUnwrap(notebook.canvases.first)
        let layer = try XCTUnwrap(canvas.layers.first)
        firstSession.addTextBlock(
            TextBlockInsertion(
                text: "Saved between sessions",
                fontSize: 20,
                alignment: .left,
                fontName: nil,
                frame: CanvasRect(x: 100, y: 100, width: 300, height: 44),
                layerID: layer.id,
                canvasID: canvas.id
            ),
            notebookID: notebookID
        )
        firstSession.closeNotebook()
        await firstSession.checkpointDocuments()

        let nextSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await nextSession.restoreLibrary()

        let restored = try XCTUnwrap(nextSession.notebook(notebookID))
        let restoredText: [String] = restored.canvases[0].layers[0].objects.compactMap { object in
            guard case let .text(block) = object else { return nil }
            return block.text
        }
        XCTAssertEqual(restoredText, ["Saved between sessions"])
    }
}
