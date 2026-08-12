import XCTest
@testable import NoteNerds

final class CanvasSystemsBehaviorTests: XCTestCase {
    func testSpatialIndexReturnsOnlyObjectsIntersectingVisibleCanvasRegion() {
        let layerID = LayerID()
        let near = TextBlock(
            id: ObjectID(), layerID: layerID, text: "Near",
            frame: CanvasRect(x: 10, y: 10, width: 80, height: 40), fontSize: 17, alignment: .left
        )
        let far = TextBlock(
            id: ObjectID(), layerID: layerID, text: "Far",
            frame: CanvasRect(x: 4_000, y: 4_000, width: 80, height: 40), fontSize: 17, alignment: .left
        )
        let index = CanvasSpatialIndex(objects: [.text(near), .text(far)], cellSize: 256)

        let visible = index.objects(in: CanvasRect(x: 0, y: 0, width: 500, height: 500))

        XCTAssertEqual(visible.map(\.id), [near.id])
    }

    func testMinimapMapsContentAndViewportIntoAvailableBounds() {
        let layout = MinimapLayout(
            contentBounds: CanvasRect(x: -1_000, y: -500, width: 2_000, height: 1_000),
            viewportBounds: CanvasRect(x: -500, y: -250, width: 500, height: 250),
            displaySize: CanvasSize(width: 200, height: 120)
        )

        XCTAssertEqual(layout.contentFrame, CanvasRect(x: 0, y: 10, width: 200, height: 100))
        XCTAssertEqual(layout.viewportFrame, CanvasRect(x: 50, y: 35, width: 50, height: 25))
    }

    func testInputRoutingChangesWhenFingerDrawingIsEnabled() {
        XCTAssertEqual(InputRouter(mode: .pencilAndNavigation).action(for: .pencil), .draw)
        XCTAssertNil(InputRouter(mode: .pencilAndNavigation).action(for: .oneFinger))
        XCTAssertEqual(InputRouter(mode: .fingerDrawing).action(for: .oneFinger), .draw)
        XCTAssertEqual(InputRouter(mode: .fingerDrawing).action(for: .twoFingers), .navigate)
    }

    func testSimulatorPointerDrawsWithoutRequiringAHiddenPreference() {
        XCTAssertTrue(DrawingInputPolicy.allowsFingerDrawing(userPreference: false, isSimulator: true))
        XCTAssertTrue(DrawingInputPolicy.allowsFingerDrawing(userPreference: true, isSimulator: false))
        XCTAssertFalse(DrawingInputPolicy.allowsFingerDrawing(userPreference: false, isSimulator: false))
    }

    func testNewTextEditingSessionStartsAtTheTappedCanvasPoint() {
        let layerID = LayerID()
        let session = CanvasTextEditingSession.new(
            layerID: layerID,
            insertionPoint: CanvasPoint(x: 1_220, y: 2_210)
        )

        XCTAssertFalse(session.isExistingText)
        XCTAssertEqual(session.textBlock.layerID, layerID)
        XCTAssertEqual(session.textBlock.frame, CanvasRect(x: 1_220, y: 2_210, width: 360, height: 44))
        XCTAssertEqual(session.textBlock.fontSize, 20)
        XCTAssertEqual(session.textBlock.alignment, .left)
        XCTAssertNil(session.textBlock.fontName)
    }

    func testExistingTextEditingSessionPreservesTheCanvasObject() {
        let textBlock = TextBlock(
            id: ObjectID(),
            layerID: LayerID(),
            text: "Existing note",
            frame: CanvasRect(x: 120, y: 240, width: 420, height: 200),
            fontSize: 28,
            alignment: .center
        )

        let session = CanvasTextEditingSession.editing(textBlock)

        XCTAssertTrue(session.isExistingText)
        XCTAssertEqual(session.textBlock, textBlock)
    }

    func testEachDrawingToolRemembersItsOwnWidthAndColor() {
        var palette = ToolPaletteState()
        let red = InkColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        palette.select(.pencil)
        palette.setWidth(.thin)
        palette.setColor(red)
        palette.select(.highlighter)
        palette.setWidth(.thick)
        palette.select(.pencil)

        XCTAssertEqual(palette.current.width, .thin)
        XCTAssertEqual(palette.current.color, red)
        palette.select(.highlighter)
        XCTAssertEqual(palette.current.width, .thick)
    }
}
