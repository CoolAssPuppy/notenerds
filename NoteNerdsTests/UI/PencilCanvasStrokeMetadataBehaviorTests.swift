import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
extension PencilCanvasInputBehaviorTests {
    func testCompletedStrokeKeepsToolActiveWhenPencilContactBegan() async throws {
        let initialColor = InkColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1)
        let initialConfiguration = ToolConfiguration(
            tool: .ballpoint,
            width: .thin,
            color: initialColor
        )
        let canvasView = PKCanvasView()
        var completedStrokes: [Stroke] = []
        let published = expectation(description: "Configured stroke published")
        let coordinator = PencilStrokeTestFixture.coordinator {
            completedStrokes.append(contentsOf: $0)
            published.fulfill()
        }
        coordinator.configuration = initialConfiguration

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        coordinator.configuration = ToolConfiguration(
            tool: .marker,
            width: .extraBold,
            color: .black
        )
        canvasView.drawing = PKDrawing(strokes: [
            PencilStrokeTestFixture.pencilStroke(
                inkType: .pen,
                color: initialColor,
                size: CGSize(width: 1.5, height: 1.5),
                opacity: 1,
                randomSeed: 44
            )
        ])
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        let stroke = try XCTUnwrap(completedStrokes.first)
        XCTAssertEqual(stroke.style.instrument, .ballpoint)
        XCTAssertEqual(stroke.style.width, ToolWidth.thin.points)
        XCTAssertEqual(stroke.style.color, initialColor)
    }

    func testRapidContactsKeepTheirOwnToolLayerAndHandwritingIntent() async {
        let handwritingLayerID = LayerID()
        let markerLayerID = LayerID()
        let handwritingStroke = PencilStrokeTestFixture.pencilStroke(
            inkType: .pen,
            color: .black,
            size: CGSize(width: 2, height: 2),
            opacity: 1,
            randomSeed: 81
        )
        let markerStroke = PencilStrokeTestFixture.pencilStroke(
            color: .black,
            size: CGSize(width: 6, height: 6),
            opacity: 0.8,
            randomSeed: 82
        )
        let canvasView = PKCanvasView()
        let published = expectation(description: "Both rapid contacts published")
        var completed: [CompletedPencilStroke] = []
        let coordinator = PencilStrokeTestFixture.coordinator(
            activeLayerID: handwritingLayerID,
            onCompletedPencilStrokes: {
                completed = $0
                published.fulfill()
            }
        )

        coordinator.configuration = ToolConfiguration(
            tool: .handwritingToText,
            width: .thin,
            color: .black
        )
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [handwritingStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        coordinator.activeLayerID = markerLayerID
        coordinator.configuration = ToolConfiguration(
            tool: .marker,
            width: .thick,
            color: .black
        )
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [handwritingStroke, markerStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(completed.map(\.shouldConvertToText), [true, false])
        XCTAssertEqual(completed.map(\.stroke.style.instrument), [.ballpoint, .marker])
        XCTAssertEqual(completed.map(\.stroke.layerID), [handwritingLayerID, markerLayerID])
    }

    func testEraseThenWriteBeforeCommitKeepsTheNewStrokeMetadata() async {
        let scenario = eraseThenWriteMetadataScenario()
        let canvasView = PKCanvasView()
        canvasView.drawing = scenario.baselineDrawing
        var completed: [CompletedPencilStroke] = []
        var publishedEdit: CanvasStrokeEdit?
        let coordinator = PencilCanvasView.Coordinator(
            activeLayerID: scenario.originalLayerID,
            actions: .testActions(
                onStrokesCompleted: { completed = $0 },
                onDrawingChanged: { edit, mixedCompleted in
                    publishedEdit = edit
                    completed = mixedCompleted
                }
            )
        )
        coordinator.canonicalStrokes = scenario.baseline
        coordinator.committedNativeDrawing = scenario.baselineDrawing
        performEraseThenWrite(
            coordinator: coordinator,
            canvasView: canvasView,
            scenario: scenario
        )

        try? await Task.sleep(for: .milliseconds(180))

        let edit = try? XCTUnwrap(publishedEdit)
        let newStroke = edit?.after.last
        XCTAssertEqual(edit?.after.first?.id, scenario.baseline[1].id)
        XCTAssertNotEqual(newStroke?.id, scenario.baseline[0].id)
        XCTAssertNotEqual(newStroke?.id, scenario.baseline[1].id)
        XCTAssertEqual(newStroke?.layerID, scenario.handwritingLayerID)
        XCTAssertEqual(newStroke?.style.instrument, .ballpoint)
        XCTAssertEqual(completed.map(\.stroke.id), newStroke.map { [$0.id] } ?? [])
        XCTAssertEqual(completed.map(\.shouldConvertToText), [true])
    }

    private func eraseThenWriteMetadataScenario() -> EraseThenWriteMetadataScenario {
        let originalLayerID = LayerID()
        let firstStroke = PencilStrokeTestFixture.blackStroke(randomSeed: 91)
        let survivingStroke = PencilStrokeTestFixture.blackStroke(
            randomSeed: 92,
            transform: CGAffineTransform(translationX: 120, y: 0)
        )
        let handwritingStroke = PencilStrokeTestFixture.blackPenStroke(
            randomSeed: 93,
            transform: CGAffineTransform(translationX: 240, y: 0)
        )
        let drawing = PKDrawing(strokes: [firstStroke, survivingStroke])
        let baseline = PencilDrawingReconciler.edit(
            drawing: drawing,
            baseline: [],
            activeLayerID: originalLayerID,
            configuration: .favoriteOne,
            pencilRoll: 0,
            createdAt: DomainFixtures.fixedDate
        ).after
        return EraseThenWriteMetadataScenario(
            originalLayerID: originalLayerID,
            handwritingLayerID: LayerID(),
            survivingNativeStroke: survivingStroke,
            handwritingNativeStroke: handwritingStroke,
            baselineDrawing: drawing,
            baseline: baseline
        )
    }

    private func performEraseThenWrite(
        coordinator: PencilCanvasView.Coordinator,
        canvasView: PKCanvasView,
        scenario: EraseThenWriteMetadataScenario
    ) {
        coordinator.configuration = ToolConfiguration(
            tool: .eraser,
            width: .medium,
            color: .black,
            eraserMode: .stroke
        )
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [scenario.survivingNativeStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        coordinator.activeLayerID = scenario.handwritingLayerID
        coordinator.configuration = ToolConfiguration(
            tool: .handwritingToText,
            width: .thin,
            color: .black
        )
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [
            scenario.survivingNativeStroke,
            scenario.handwritingNativeStroke
        ])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)
    }
}

private struct EraseThenWriteMetadataScenario {
    let originalLayerID: LayerID
    let handwritingLayerID: LayerID
    let survivingNativeStroke: PKStroke
    let handwritingNativeStroke: PKStroke
    let baselineDrawing: PKDrawing
    let baseline: [Stroke]
}
