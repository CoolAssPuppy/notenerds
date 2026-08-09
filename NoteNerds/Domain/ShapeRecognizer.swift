import Foundation

extension Stroke {
    var terminalHoldDuration: TimeInterval {
        guard let finalSample = samples.last else { return 0 }
        let movementTolerance = max(4, style.width * 1.5)
        let holdStart = samples.reversed().last { sample in
            hypot(sample.point.x - finalSample.point.x, sample.point.y - finalSample.point.y) <= movementTolerance
        }
        return max(0, finalSample.timeOffset - (holdStart?.timeOffset ?? finalSample.timeOffset))
    }
}

struct ShapeRecognizer: Sendable {
    private let minimumHoldDuration = 0.5

    func recognize(_ stroke: Stroke, holdDuration: TimeInterval) -> RecognizedShape? {
        guard stroke.style.instrument != .highlighter,
              holdDuration >= minimumHoldDuration,
              stroke.samples.count >= 2 else { return nil }
        let points = stroke.samples.map(\.point)
        let bounds = CanvasRect.enclosing(points)
        let diagonal = hypot(bounds.size.width, bounds.size.height)
        guard diagonal > 4 else { return nil }

        let kind: RecognizedShapeKind
        let recognizedPoints: [CanvasPoint]
        if isClosed(points, tolerance: diagonal * 0.22) {
            let vertices = simplifiedVertices(points, tolerance: diagonal * 0.08)
            switch vertices.count {
            case 3:
                kind = .triangle
                recognizedPoints = vertices
            case 4:
                kind = abs(bounds.size.width - bounds.size.height) < diagonal * 0.08 ? .square : .rectangle
                recognizedPoints = rectanglePoints(bounds)
            default:
                kind = abs(bounds.size.width - bounds.size.height) < diagonal * 0.1 ? .circle : .ellipse
                recognizedPoints = points
            }
        } else if let arrowPoints = arrowPoints(points, tolerance: diagonal * 0.12) {
            kind = .arrow
            recognizedPoints = arrowPoints
        } else if isStraight(points, tolerance: diagonal * 0.08) {
            kind = .line
            recognizedPoints = [points[0], points[points.count - 1]]
        } else {
            return nil
        }
        return RecognizedShape(
            id: ObjectID(rawValue: stroke.id.rawValue),
            layerID: stroke.layerID,
            kind: kind,
            points: recognizedPoints,
            style: stroke.style,
            originalStroke: stroke
        )
    }

    private func isStraight(_ points: [CanvasPoint], tolerance: Double) -> Bool {
        let start = points[0]
        let end = points[points.count - 1]
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return false }
        return points.allSatisfy { point in
            let distance = abs(
                (end.y - start.y) * point.x - (end.x - start.x) * point.y + end.x * start.y - end.y * start.x
            ) / length
            return distance <= tolerance
        }
    }

    private func isClosed(_ points: [CanvasPoint], tolerance: Double) -> Bool {
        guard let first = points.first, let last = points.last else { return false }
        return hypot(last.x - first.x, last.y - first.y) <= tolerance
    }

    private func arrowPoints(_ points: [CanvasPoint], tolerance: Double) -> [CanvasPoint]? {
        guard points.count >= 5, let start = points.first else { return nil }
        var tipIndex = 1
        for index in points.indices.dropFirst()
        where distance(points[index], start) > distance(points[tipIndex], start) {
            tipIndex = index
        }
        guard tipIndex < points.count - 2 else { return nil }
        let tip = points[tipIndex]
        let laterPoints = points[(tipIndex + 1)...]
        let returnsToTip = laterPoints.contains { distance($0, tip) <= tolerance }
        guard returnsToTip else { return nil }
        return [start, tip, laterPoints.first ?? tip, tip, laterPoints.last ?? tip]
    }

    private func distance(_ first: CanvasPoint, _ second: CanvasPoint) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func simplifiedVertices(_ points: [CanvasPoint], tolerance: Double) -> [CanvasPoint] {
        let candidates = stride(from: 0, to: points.count - 1, by: max(1, points.count / 12)).map { points[$0] }
        var vertices: [CanvasPoint] = []
        for point in candidates {
            guard let last = vertices.last else {
                vertices.append(point)
                continue
            }
            if hypot(point.x - last.x, point.y - last.y) > tolerance { vertices.append(point) }
        }
        return vertices.count > 6 ? [] : vertices
    }

    private func rectanglePoints(_ bounds: CanvasRect) -> [CanvasPoint] {
        [
            bounds.origin,
            CanvasPoint(x: bounds.maxX, y: bounds.minY),
            CanvasPoint(x: bounds.maxX, y: bounds.maxY),
            CanvasPoint(x: bounds.minX, y: bounds.maxY)
        ]
    }
}
