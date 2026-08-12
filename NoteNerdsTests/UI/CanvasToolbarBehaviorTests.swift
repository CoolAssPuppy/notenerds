import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

final class CanvasToolbarBehaviorTests: XCTestCase {
    func testToolbarStartsMinimizedAndKeepsTheUsersSavedState() throws {
        let suiteName = "CanvasToolbarBehaviorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.register(defaults: [
            CanvasToolbarPreferences.isExpandedKey: CanvasToolbarPreferences.isExpandedByDefault
        ])

        XCTAssertFalse(defaults.bool(forKey: CanvasToolbarPreferences.isExpandedKey))

        defaults.set(true, forKey: CanvasToolbarPreferences.isExpandedKey)

        XCTAssertTrue(defaults.bool(forKey: CanvasToolbarPreferences.isExpandedKey))
    }

    func testCompactToolbarKeepsEveryCoreDrawingControlVisible() {
        XCTAssertEqual(
            CanvasToolbarPresentation.actions(isExpanded: false),
            [.drawing, .width, .color, .eraser, .lasso]
        )
    }

    func testExpandedToolbarAddsOnlyCoreToolsAndEditingCommands() {
        XCTAssertEqual(
            CanvasToolbarPresentation.actions(isExpanded: true),
            [
                .drawing, .width, .color, .eraser, .lasso,
                .text, .shapes, .undo, .redo,
                .layers
            ]
        )
    }

    func testInkOnlyCanvasStillCreatesASelectionOverlayForLasso() {
        XCTAssertTrue(
            CanvasOverlayPresentation.requiresSelectionOverlay(
                strokeCount: 1,
                nonStrokeObjectCount: 0,
                isLassoEnabled: true,
                isShapePlacementEnabled: false
            )
        )
        XCTAssertFalse(
            CanvasOverlayPresentation.requiresSelectionOverlay(
                strokeCount: 1,
                nonStrokeObjectCount: 0,
                isLassoEnabled: false,
                isShapePlacementEnabled: false
            )
        )
    }

    func testLassoOverlayRefreshesAfterSameCountStrokeGeometryChanges() {
        var original = DomainFixtures.stroke()
        original.samples[0].point = CanvasPoint(x: 120, y: 180)
        original.samples = [original.samples[0]]
        var moved = original
        moved.samples[0].point = CanvasPoint(x: 420, y: 480)

        XCTAssertTrue(
            CanvasOverlayModelReconciliation.requiresRefresh(
                currentStrokes: [original],
                incomingStrokes: [moved],
                isLassoEnabled: true
            )
        )
        XCTAssertFalse(
            CanvasOverlayModelReconciliation.requiresRefresh(
                currentStrokes: [original],
                incomingStrokes: [moved],
                isLassoEnabled: false
            )
        )
    }

    @MainActor
    func testDrawingOverlayRoutesPencilInputToTheNativeCanvas() {
        let canvasView = PKCanvasView(frame: canvasFrame)
        let overlay = makeSelectionOverlay(objects: [.stroke(DomainFixtures.stroke())])
        canvasView.addSubview(overlay)

        XCTAssertIdentical(canvasView.hitTest(canvasPoint, with: nil), overlay)

        let pencilHit = canvasView.hitTest(canvasPoint, with: PencilEvent())
        XCTAssertFalse(pencilHit === overlay)
        XCTAssertTrue(pencilHit === canvasView || pencilHit?.isDescendant(of: canvasView) == true)
        assertGestureRecognizers(in: overlay, allow: [.direct])
    }

    @MainActor
    func testLassoAndShapeOverlaysAcceptPencilInput() {
        let overlays = [
            makeSelectionOverlay(objects: [], isLassoEnabled: true),
            makeSelectionOverlay(objects: [], shapePlacementKind: .rectangle)
        ]

        for overlay in overlays {
            let canvasView = PKCanvasView(frame: canvasFrame)
            canvasView.addSubview(overlay)

            XCTAssertIdentical(canvasView.hitTest(canvasPoint, with: PencilEvent()), overlay)
            assertGestureRecognizers(in: overlay, allow: [.direct, .pencil])
        }
    }

    @MainActor
    func testSharedCanvasAssetIsReadOnceWithoutCrashing() {
        let layerID = LayerID()
        let assetID = AssetID()
        let frame = CanvasRect(x: 10, y: 20, width: 100, height: 80)
        let objects: [CanvasObject] = [
            .image(ImageObject(
                id: ObjectID(),
                layerID: layerID,
                assetID: assetID,
                frame: frame,
                rotation: 0
            )),
            .image(ImageObject(
                id: ObjectID(),
                layerID: layerID,
                assetID: assetID,
                frame: frame,
                rotation: 0
            ))
        ]
        let notebook = Notebook(
            title: "Shared asset",
            canvases: [Canvas(title: "Canvas 1", layers: [Layer(id: layerID, name: "Layer 1", objects: objects)])]
        )
        let expectedData = Data("shared image".utf8)
        var library = LibraryState(notebooks: [notebook])
        library.storeAsset(DocumentAsset(id: assetID, data: expectedData, contentType: "image/png"))
        let model = AppModel(automaticallyRestore: false)
        model.library = library

        let assets = NotebookEditorView(model: model, notebook: notebook).currentAssets

        XCTAssertEqual(assets, [assetID: expectedData])
    }

    func testSpecializedWritingToolsRemainChoicesInsideDrawingTools() {
        XCTAssertEqual(
            CanvasToolbarPresentation.specializedDrawingTools,
            [
                .ballpoint, .fineliner, .mechanicalPencil, .pencil,
                .marker, .highlighter, .brush, .calligraphyPen, .handwritingToText
            ]
        )
    }

    func testExpandedToolbarUsesOneBoundedScrollerAlongItsDockAxis() {
        XCTAssertEqual(CanvasToolbarPresentation.verticalColumnCount(isExpanded: false), 1)
        XCTAssertEqual(CanvasToolbarPresentation.verticalColumnCount(isExpanded: true), 1)
        XCTAssertEqual(CanvasToolbarPresentation.scrollAxis(orientation: .vertical), .vertical)
        XCTAssertEqual(CanvasToolbarPresentation.scrollAxis(orientation: .horizontal), .horizontal)
        XCTAssertEqual(CanvasToolbarPresentation.maximumExpandedLength(orientation: .vertical), 280)
        XCTAssertEqual(CanvasToolbarPresentation.maximumExpandedLength(orientation: .horizontal), 500)
        XCTAssertTrue(CanvasToolbarPresentation.isChevronPinned)
    }

    func testChevronRotatesHalfATurnAndMatchesToolbarAxis() {
        XCTAssertEqual(CanvasToolbarPresentation.chevronSymbol(orientation: .vertical), "chevron.down")
        XCTAssertEqual(CanvasToolbarPresentation.chevronSymbol(orientation: .horizontal), "chevron.right")
        XCTAssertEqual(CanvasToolbarPresentation.chevronRotation(isExpanded: false), 0)
        XCTAssertEqual(CanvasToolbarPresentation.chevronRotation(isExpanded: true), 180)
    }

    func testDragReleaseSnapsToTopOrNearestVerticalEdge() {
        let size = CGSize(width: 1_024, height: 768)

        XCTAssertEqual(
            CanvasToolbarDocking.destination(for: CGPoint(x: 700, y: 90), in: size),
            .top
        )
        XCTAssertEqual(
            CanvasToolbarDocking.destination(for: CGPoint(x: 120, y: 420), in: size),
            .left
        )
        XCTAssertEqual(
            CanvasToolbarDocking.destination(for: CGPoint(x: 900, y: 420), in: size),
            .right
        )
    }
}

private extension CanvasToolbarBehaviorTests {
    var canvasFrame: CGRect { CGRect(x: 0, y: 0, width: 500, height: 500) }
    var canvasPoint: CGPoint { CGPoint(x: 20, y: 30) }

    @MainActor
    func makeSelectionOverlay(
        objects: [CanvasObject],
        isLassoEnabled: Bool = false,
        shapePlacementKind: RecognizedShapeKind? = nil
    ) -> CanvasSelectionOverlayView {
        CanvasSelectionOverlayView(
            frame: canvasFrame,
            objects: objects,
            isLassoEnabled: isLassoEnabled,
            onTransform: { _, _, _ in },
            onDelete: { _ in },
            onPaste: { _ in },
            onMoveToLayer: { _, _ in },
            onEditText: { _ in },
            shapePlacementKind: shapePlacementKind,
            onPlaceShape: { _ in },
            onSelectionChanged: { _ in }
        )
    }

    @MainActor
    func assertGestureRecognizers(
        in overlay: CanvasSelectionOverlayView,
        allow expectedTypes: [UITouch.TouchType],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recognizers = overlay.gestureRecognizers ?? []
        XCTAssertFalse(recognizers.isEmpty, file: file, line: line)
        let expectedRawValues = expectedTypes.map(\.rawValue).sorted()
        for recognizer in recognizers {
            XCTAssertEqual(
                recognizer.allowedTouchTypes.map(\.intValue).sorted(),
                expectedRawValues,
                file: file,
                line: line
            )
        }
    }
}

@MainActor
private final class PencilEvent: UIEvent {
    private let pencilTouch = PencilTouch()

    override var allTouches: Set<UITouch>? { [pencilTouch] }
}

@MainActor
private final class PencilTouch: UITouch {
    override var type: UITouch.TouchType { .pencil }
}
