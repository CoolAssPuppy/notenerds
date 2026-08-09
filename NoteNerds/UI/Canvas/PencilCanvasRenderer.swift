import PencilKit
import UIKit

enum PencilCanvasModelReconciliation {
    static func requiresRedraw(
        current: [Stroke],
        incoming: [Stroke],
        isUsingTool: Bool = false
    ) -> Bool {
        !isUsingTool && current != incoming
    }
}

enum PencilCanvasRenderer {
    static func drawing(from strokes: [Stroke]) -> PKDrawing {
        let pencilStrokes = strokes.compactMap { stroke -> PKStroke? in
            guard !stroke.samples.isEmpty else { return nil }
            let points = stroke.samples.map { sample in
                PKStrokePoint(
                    location: CGPoint(x: sample.point.x, y: sample.point.y),
                    timeOffset: sample.timeOffset,
                    size: CGSize(width: stroke.style.width, height: stroke.style.width),
                    opacity: stroke.style.color.alpha,
                    force: sample.pressure,
                    azimuth: sample.azimuth,
                    altitude: sample.altitude
                )
            }
            let path = PKStrokePath(controlPoints: points, creationDate: stroke.createdAt)
            let ink = PKInk(stroke.style.instrument.inkType, color: UIColor(stroke.style.color))
            return PKStroke(ink: ink, path: path)
        }
        return PKDrawing(strokes: pencilStrokes)
    }

    static func patternColor(for template: CanvasTemplate) -> UIColor {
        PaperRenderer.patternColor(for: template)
    }

    static func marginRuleFrame(for template: PaperType, contentSize: CGSize) -> CGRect? {
        guard [.yellowLegalPad, .whiteLegalPad].contains(template) else { return nil }
        return CGRect(x: 9_551.5, y: 0, width: 1, height: contentSize.height)
    }
}
