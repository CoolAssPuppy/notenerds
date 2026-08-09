import PencilKit
import UIKit

@MainActor
enum PencilCanvasInputAccessories {
    static func install(on canvasView: PKCanvasView, coordinator: PencilCanvasView.Coordinator) {
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = coordinator
        canvasView.addInteraction(pencilInteraction)

        let hoverRecognizer = UIHoverGestureRecognizer(
            target: coordinator,
            action: #selector(PencilCanvasView.Coordinator.handlePencilHover(_:))
        )
        hoverRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        canvasView.addGestureRecognizer(hoverRecognizer)
    }
}
