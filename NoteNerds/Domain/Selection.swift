import Foundation

struct LassoPath: Codable, Hashable, Sendable {
    let points: [CanvasPoint]

    var bounds: CanvasRect { CanvasRect.enclosing(points) }

    func selects(_ object: CanvasObject) -> Bool {
        guard bounds.intersects(object.bounds) else { return false }
        if case let .stroke(stroke) = object {
            return stroke.samples.contains { contains($0.point) }
                || stroke.samples.indices.dropFirst().contains { index in
                    segmentIntersectsBounds(stroke.samples[index - 1].point, stroke.samples[index].point)
                }
        }
        return contains(object.bounds.origin)
            || contains(CanvasPoint(x: object.bounds.maxX, y: object.bounds.maxY))
            || bounds.intersects(object.bounds)
    }

    private func contains(_ point: CanvasPoint) -> Bool {
        guard points.count > 2 else { return false }
        var isInside = false
        var previousIndex = points.count - 1
        for index in points.indices {
            let current = points[index]
            let previous = points[previousIndex]
            let crosses = (current.y > point.y) != (previous.y > point.y)
                && point.x < (previous.x - current.x) * (point.y - current.y)
                / (previous.y - current.y) + current.x
            if crosses { isInside.toggle() }
            previousIndex = index
        }
        return isInside
    }

    private func segmentIntersectsBounds(_ first: CanvasPoint, _ second: CanvasPoint) -> Bool {
        CanvasRect.enclosing([first, second]).intersects(bounds)
    }
}

struct SelectionTransform: Codable, Hashable, Sendable {
    var scaleX: Double
    var scaleY: Double
    var rotation: Double
    var translation: CanvasPoint

    func point(_ point: CanvasPoint, around center: CanvasPoint) -> CanvasPoint {
        let scaledX = (point.x - center.x) * scaleX
        let scaledY = (point.y - center.y) * scaleY
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return CanvasPoint(
            x: center.x + scaledX * cosine - scaledY * sine + translation.x,
            y: center.y + scaledX * sine + scaledY * cosine + translation.y
        )
    }
}

extension CanvasObject {
    var bounds: CanvasRect {
        switch self {
        case let .stroke(stroke): stroke.bounds
        case let .shape(shape): CanvasRect.enclosing(shape.points)
        case let .text(text): text.frame
        case let .image(image): image.frame
        case let .pdf(pdf): pdf.frame
        }
    }

    func applying(_ transform: SelectionTransform, around center: CanvasPoint) -> CanvasObject {
        switch self {
        case var .stroke(stroke):
            stroke.samples = stroke.samples.map { sample in
                var transformed = sample
                transformed.point = transform.point(sample.point, around: center)
                return transformed
            }
            stroke.style.width *= sqrt(abs(transform.scaleX * transform.scaleY))
            return .stroke(stroke)
        case var .shape(shape):
            shape.points = shape.points.map { transform.point($0, around: center) }
            shape.style.width *= sqrt(abs(transform.scaleX * transform.scaleY))
            return .shape(shape)
        case var .text(text):
            text.frame = transformedFrame(text.frame, by: transform, around: center)
            return .text(text)
        case var .image(image):
            image.frame = transformedFrame(image.frame, by: transform, around: center)
            image.rotation += transform.rotation
            return .image(image)
        case var .pdf(pdf):
            pdf.frame = transformedFrame(pdf.frame, by: transform, around: center)
            return .pdf(pdf)
        }
    }

    private func transformedFrame(
        _ frame: CanvasRect,
        by transform: SelectionTransform,
        around center: CanvasPoint
    ) -> CanvasRect {
        let corners = [
            frame.origin,
            CanvasPoint(x: frame.maxX, y: frame.minY),
            CanvasPoint(x: frame.maxX, y: frame.maxY),
            CanvasPoint(x: frame.minX, y: frame.maxY)
        ]
        return CanvasRect.enclosing(corners.map { transform.point($0, around: center) })
    }
}
