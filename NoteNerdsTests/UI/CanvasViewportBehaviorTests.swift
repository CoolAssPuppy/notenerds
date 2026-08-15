import Combine
import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

final class CanvasViewportBehaviorTests: XCTestCase {
    func testReopeningANoteZoomsToWritingOutsideTheHomePage() {
        let writtenNearOrigin = CanvasRect(x: 10, y: 20, width: 120, height: 40)

        XCTAssertEqual(
            CanvasViewportPolicy.openingAction(contentBounds: writtenNearOrigin),
            .zoomToContent(writtenNearOrigin)
        )
    }

    func testReopeningANoteOnTheHomePageStaysThere() {
        let writtenOnHomePage = CanvasRect(x: 9_620, y: 9_640, width: 80, height: 30)

        XCTAssertEqual(
            CanvasViewportPolicy.openingAction(contentBounds: writtenOnHomePage),
            .home
        )
    }

    func testAnEmptyNoteOpensOnTheHomePage() {
        XCTAssertEqual(CanvasViewportPolicy.openingAction(contentBounds: nil), .home)
        XCTAssertEqual(
            CanvasViewportPolicy.openingAction(contentBounds: CanvasRect(x: 0, y: 0, width: 0, height: 0)),
            .home
        )
    }

    func testOpeningOntoOriginWritingMovesOffTheHomePage() {
        let canvasView = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 820, height: 600))
        PencilCanvasView.configureViewport(canvasView)
        let writing = CanvasRect(x: 40, y: 60, width: 180, height: 50)

        PencilCanvasView.applyOpeningViewport(.zoomToContent(writing), to: canvasView)

        XCTAssertNotEqual(canvasView.contentOffset.x, 9_500, accuracy: 1)
        XCTAssertNotEqual(canvasView.contentOffset.y, 9_500, accuracy: 1)
    }

    func testOpeningZoomRectIncludesTheWrittenInk() {
        let writing = CanvasRect(x: 40, y: 60, width: 180, height: 50)

        let zoomRect = PencilCanvasView.zoomRect(for: writing)

        XCTAssertTrue(
            zoomRect.contains(CGRect(x: 40, y: 60, width: 180, height: 50)),
            "The opening zoom \(zoomRect) did not include the written ink"
        )
    }

    func testAnEmptyCanvasOpensOnTheHomePageAfterLayout() {
        let canvasView = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 820, height: 600))
        PencilCanvasView.configureViewport(canvasView)

        PencilCanvasView.applyOpeningViewport(
            CanvasViewportPolicy.openingAction(contentBounds: nil),
            to: canvasView
        )

        XCTAssertEqual(canvasView.contentOffset.x, 9_500, accuracy: 0.5)
        XCTAssertEqual(canvasView.contentOffset.y, 9_500, accuracy: 0.5)
    }

    @MainActor
    func testClosingAndReopeningKeepsOriginWritingAndOpensOntoIt() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let model = AppModel(
            repository: LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json")),
            documentStore: LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents")),
            automaticallyRestore: false
        )
        model.createNotebook()
        let notebookID = try XCTUnwrap(model.selectedNotebookID)
        let notebook = try XCTUnwrap(model.notebook(notebookID))
        let canvas = try XCTUnwrap(notebook.canvases.first)
        let layer = try XCTUnwrap(canvas.layers.first)
        _ = model.addStrokes(
            [DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)],
            to: notebookID,
            canvasID: canvas.id,
            layerID: layer.id
        )

        model.closeNotebook()
        model.open(notebookID)

        let reopened = try XCTUnwrap(model.notebook(notebookID)?.canvases.first)
        let writing = try XCTUnwrap(reopened.contentBounds)
        XCTAssertEqual(reopened.layers[0].objects.compactMap(\.strokeValue).count, 1)
        XCTAssertEqual(
            CanvasViewportPolicy.openingAction(contentBounds: writing),
            .zoomToContent(writing),
            "Closing and reopening left the writing off the home page"
        )
    }

    func testThumbnailWritingNearTheOriginIsOutsideTheHomePage() throws {
        let canvas = DomainFixtures.notebook().canvases[0]
        let writing = try XCTUnwrap(canvas.contentBounds)

        XCTAssertNotNil(CanvasThumbnailRenderer.image(for: canvas, size: CGSize(width: 80, height: 60)))
        XCTAssertFalse(
            writing.intersects(CanvasViewport.defaultVisibleBounds),
            "The thumbnail crops to \(writing), which the home page does not show"
        )
        XCTAssertEqual(
            CanvasViewportPolicy.openingAction(contentBounds: writing),
            .zoomToContent(writing)
        )
    }

    func testRepeatedViewportReportsDoNotNotifyObservers() {
        let viewport = CanvasViewportModel(bounds: bounds(x: 0))
        var notificationCount = 0
        let cancellable = viewport.objectWillChange.sink { notificationCount += 1 }

        viewport.report(bounds(x: 0))
        viewport.report(bounds(x: 0))
        viewport.report(bounds(x: 0))

        XCTAssertEqual(notificationCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testAChangedViewportNotifiesObserversOnce() {
        let viewport = CanvasViewportModel(bounds: bounds(x: 0))
        var notificationCount = 0
        let cancellable = viewport.objectWillChange.sink { notificationCount += 1 }

        viewport.report(bounds(x: 40))
        viewport.report(bounds(x: 40))

        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(viewport.bounds, bounds(x: 40))
        withExtendedLifetime(cancellable) {}
    }

    private func bounds(x: Double) -> CanvasRect {
        CanvasRect(x: x, y: 0, width: 1_024, height: 1_366)
    }
}
