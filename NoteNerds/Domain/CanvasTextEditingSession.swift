import Foundation

struct CanvasTextEditingSession: Equatable, Sendable {
    let textBlock: TextBlock
    let isExistingText: Bool

    static func new(
        layerID: LayerID,
        insertionPoint: CanvasPoint,
        constrainedTo region: CanvasRect? = nil
    ) -> CanvasTextEditingSession {
        let size = CanvasSize(width: 360, height: 44)
        let frame = PlannerRegionContentPolicy.constrainedFrame(
            CanvasRect(
                x: insertionPoint.x,
                y: insertionPoint.y,
                width: size.width,
                height: size.height
            ),
            to: region
        )
        return CanvasTextEditingSession(
            textBlock: TextBlock(
                id: ObjectID(),
                layerID: layerID,
                text: "",
                frame: frame,
                fontSize: 20,
                alignment: .left
            ),
            isExistingText: false
        )
    }

    static func editing(_ textBlock: TextBlock) -> CanvasTextEditingSession {
        CanvasTextEditingSession(textBlock: textBlock, isExistingText: true)
    }
}
