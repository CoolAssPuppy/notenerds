import Foundation

struct LassoPath: Codable, Hashable, Sendable {
    let points: [CanvasPoint]

    var bounds: CanvasRect { CanvasRect.enclosing(points) }

    func selects(_ object: CanvasObject) -> Bool {
        guard bounds.intersects(object.bounds) else { return false }
        if case let .stroke(stroke) = object {
            return stroke.samples.contains { contains($0.point) }
                || stroke.samples.indices.dropFirst().contains { index in
                    segmentIntersectsPath(stroke.samples[index - 1].point, stroke.samples[index].point)
                }
        }
        let objectCenter = CanvasPoint(
            x: object.bounds.minX + object.bounds.size.width / 2,
            y: object.bounds.minY + object.bounds.size.height / 2
        )
        return contains(objectCenter)
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

    private func segmentIntersectsPath(_ first: CanvasPoint, _ second: CanvasPoint) -> Bool {
        guard points.count > 2 else { return false }
        return points.indices.contains { index in
            let nextIndex = points.index(after: index) == points.endIndex ? points.startIndex : index + 1
            return segmentsIntersect(first, second, points[index], points[nextIndex])
        }
    }

    private func segmentsIntersect(
        _ firstStart: CanvasPoint,
        _ firstEnd: CanvasPoint,
        _ secondStart: CanvasPoint,
        _ secondEnd: CanvasPoint
    ) -> Bool {
        let firstSideA = crossProduct(firstStart, firstEnd, secondStart)
        let firstSideB = crossProduct(firstStart, firstEnd, secondEnd)
        let secondSideA = crossProduct(secondStart, secondEnd, firstStart)
        let secondSideB = crossProduct(secondStart, secondEnd, firstEnd)
        let crossesBothSegments = haveOppositeSigns(firstSideA, firstSideB)
            && haveOppositeSigns(secondSideA, secondSideB)
        return crossesBothSegments
            || isOnSegment(secondStart, firstStart, firstEnd, crossProduct: firstSideA)
            || isOnSegment(secondEnd, firstStart, firstEnd, crossProduct: firstSideB)
            || isOnSegment(firstStart, secondStart, secondEnd, crossProduct: secondSideA)
            || isOnSegment(firstEnd, secondStart, secondEnd, crossProduct: secondSideB)
    }

    private func crossProduct(_ start: CanvasPoint, _ end: CanvasPoint, _ point: CanvasPoint) -> Double {
        (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
    }

    private func haveOppositeSigns(_ first: Double, _ second: Double) -> Bool {
        (first > 0 && second < 0) || (first < 0 && second > 0)
    }

    private func isOnSegment(
        _ point: CanvasPoint,
        _ start: CanvasPoint,
        _ end: CanvasPoint,
        crossProduct: Double
    ) -> Bool {
        let tolerance = 0.000_001
        return abs(crossProduct) <= tolerance
            && point.x >= min(start.x, end.x) - tolerance
            && point.x <= max(start.x, end.x) + tolerance
            && point.y >= min(start.y, end.y) - tolerance
            && point.y <= max(start.y, end.y) + tolerance
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
