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

struct PencilCanvasSelectionTransformResult {
    let drawing: PKDrawing
    let canonicalStrokes: [Stroke]
}

enum PencilCanvasSelectionTransform {
    static func applying(
        objectIDs: Set<ObjectID>,
        transform: SelectionTransform,
        center: CanvasPoint,
        to drawing: PKDrawing,
        canonicalStrokes: [Stroke]
    ) -> PencilCanvasSelectionTransformResult {
        guard drawing.strokes.count == canonicalStrokes.count else {
            return PencilCanvasSelectionTransformResult(
                drawing: drawing,
                canonicalStrokes: canonicalStrokes
            )
        }
        let affineTransform = cgAffineTransform(transform, around: center)
        let pencilStrokes = drawing.strokes.enumerated().map { index, pencilStroke in
            guard objectIDs.contains(canonicalStrokes[index].objectID) else { return pencilStroke }
            var transformedStroke = pencilStroke
            transformedStroke.transform = pencilStroke.transform.concatenating(affineTransform)
            return transformedStroke
        }
        let transformedCanonicalStrokes = canonicalStrokes.map { stroke in
            guard objectIDs.contains(stroke.objectID),
                  case let .stroke(transformedStroke) = CanvasObject.stroke(stroke).applying(
                    transform,
                    around: center
                  ) else { return stroke }
            return transformedStroke
        }
        return PencilCanvasSelectionTransformResult(
            drawing: PKDrawing(strokes: pencilStrokes),
            canonicalStrokes: transformedCanonicalStrokes
        )
    }

    private static func cgAffineTransform(
        _ transform: SelectionTransform,
        around center: CanvasPoint
    ) -> CGAffineTransform {
        let cosine = cos(transform.rotation)
        let sine = sin(transform.rotation)
        let horizontalScale = transform.scaleX
        let verticalScale = transform.scaleY
        let horizontalX = horizontalScale * cosine
        let horizontalY = horizontalScale * sine
        let verticalX = -verticalScale * sine
        let verticalY = verticalScale * cosine
        return CGAffineTransform(
            a: horizontalX,
            b: horizontalY,
            c: verticalX,
            d: verticalY,
            tx: center.x - horizontalX * center.x - verticalX * center.y + transform.translation.x,
            ty: center.y - horizontalY * center.x - verticalY * center.y + transform.translation.y
        )
    }
}
