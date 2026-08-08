import Foundation

enum ShapeFactory {
    static func make(
        _ kind: RecognizedShapeKind,
        centeredAt center: CanvasPoint,
        layerID: LayerID,
        style: StrokeStyle
    ) -> RecognizedShape {
        RecognizedShape(
            id: ObjectID(),
            layerID: layerID,
            kind: kind,
            points: points(for: kind, centeredAt: center),
            style: style,
            originalStroke: nil
        )
    }

    private static func points(
        for kind: RecognizedShapeKind,
        centeredAt center: CanvasPoint
    ) -> [CanvasPoint] {
        switch kind {
        case .line: line(center: center)
        case .arrow: arrow(center: center)
        case .rectangle: rectangle(center: center, width: 160, height: 100)
        case .square: rectangle(center: center, width: 120, height: 120)
        case .circle: ellipse(center: center, width: 120, height: 120)
        case .ellipse: ellipse(center: center, width: 160, height: 100)
        case .triangle: triangle(center: center)
        }
    }

    private static func line(center: CanvasPoint) -> [CanvasPoint] {
        [
            CanvasPoint(x: center.x - 80, y: center.y),
            CanvasPoint(x: center.x + 80, y: center.y)
        ]
    }

    private static func arrow(center: CanvasPoint) -> [CanvasPoint] {
        let tip = CanvasPoint(x: center.x + 80, y: center.y)
        return [
            CanvasPoint(x: center.x - 80, y: center.y),
            tip,
            CanvasPoint(x: center.x + 52, y: center.y - 22),
            tip,
            CanvasPoint(x: center.x + 52, y: center.y + 22)
        ]
    }

    private static func rectangle(
        center: CanvasPoint,
        width: Double,
        height: Double
    ) -> [CanvasPoint] {
        let halfWidth = width / 2
        let halfHeight = height / 2
        return [
            CanvasPoint(x: center.x - halfWidth, y: center.y - halfHeight),
            CanvasPoint(x: center.x + halfWidth, y: center.y - halfHeight),
            CanvasPoint(x: center.x + halfWidth, y: center.y + halfHeight),
            CanvasPoint(x: center.x - halfWidth, y: center.y + halfHeight)
        ]
    }

    private static func ellipse(
        center: CanvasPoint,
        width: Double,
        height: Double
    ) -> [CanvasPoint] {
        (0..<48).map { index in
            let angle = Double(index) / 48 * .pi * 2
            return CanvasPoint(
                x: center.x + cos(angle) * width / 2,
                y: center.y + sin(angle) * height / 2
            )
        }
    }

    private static func triangle(center: CanvasPoint) -> [CanvasPoint] {
        [
            CanvasPoint(x: center.x, y: center.y - 65),
            CanvasPoint(x: center.x + 70, y: center.y + 55),
            CanvasPoint(x: center.x - 70, y: center.y + 55)
        ]
    }
}

extension RecognizedShape {
    var bounds: CanvasRect { CanvasRect.enclosing(points) }
}
