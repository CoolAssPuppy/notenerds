import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class PencilCanvasToolApplicationBehaviorTests: XCTestCase {
    func testTheSelectedToolIsInstalledOnce() {
        let canvasView = PKCanvasView()
        let coordinator = makeCoordinator()
        coordinator.configuration = ToolConfiguration(tool: .ballpoint, width: .medium, color: .black)

        coordinator.applyToolIfNeeded(to: canvasView)
        let installedTool = canvasView.tool
        coordinator.applyToolIfNeeded(to: canvasView)

        XCTAssertTrue(isSameInkingTool(canvasView.tool, installedTool))
        XCTAssertEqual(coordinator.appliedToolConfiguration, coordinator.configuration)
    }

    func testAToolChosenDuringAContactWaitsForThePencilToLift() {
        let canvasView = PKCanvasView()
        let coordinator = makeCoordinator()
        let ballpoint = ToolConfiguration(tool: .ballpoint, width: .medium, color: .black)
        let eraser = ToolConfiguration(tool: .eraser, width: .medium, color: .black)
        coordinator.configuration = ballpoint
        coordinator.applyToolIfNeeded(to: canvasView)

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        coordinator.configuration = eraser
        coordinator.applyToolIfNeeded(to: canvasView)

        XCTAssertEqual(coordinator.appliedToolConfiguration, ballpoint)
        XCTAssertTrue(canvasView.tool is PKInkingTool)

        coordinator.canvasViewDidEndUsingTool(canvasView)

        XCTAssertEqual(coordinator.appliedToolConfiguration, eraser)
        XCTAssertTrue(canvasView.tool is PKEraserTool)
    }

    private func makeCoordinator() -> PencilCanvasView.Coordinator {
        PencilStrokeTestFixture.coordinator(onCompletedPencilStrokes: { _ in })
    }

    private func isSameInkingTool(_ lhs: PKTool, _ rhs: PKTool) -> Bool {
        guard let lhs = lhs as? PKInkingTool, let rhs = rhs as? PKInkingTool else { return false }
        return lhs.inkType == rhs.inkType && lhs.color == rhs.color && lhs.width == rhs.width
    }
}
