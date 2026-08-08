import Foundation

struct CanvasPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    static let zero = CanvasPoint(x: 0, y: 0)
}

struct CanvasSize: Codable, Hashable, Sendable {
    var width: Double
    var height: Double
}

struct CanvasRect: Codable, Hashable, Sendable {
    var origin: CanvasPoint
    var size: CanvasSize

    init(x: Double, y: Double, width: Double, height: Double) {
        origin = CanvasPoint(x: x, y: y)
        size = CanvasSize(width: width, height: height)
    }

    var minX: Double { origin.x }
    var minY: Double { origin.y }
    var maxX: Double { origin.x + size.width }
    var maxY: Double { origin.y + size.height }

    func intersects(_ other: CanvasRect) -> Bool {
        maxX >= other.minX && other.maxX >= minX && maxY >= other.minY && other.maxY >= minY
    }

    static func enclosing(_ points: [CanvasPoint]) -> CanvasRect {
        guard let first = points.first else {
            return CanvasRect(x: 0, y: 0, width: 0, height: 0)
        }
        let extents = points.dropFirst().reduce(
            (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        ) { result, point in
            (
                min(result.minX, point.x),
                min(result.minY, point.y),
                max(result.maxX, point.x),
                max(result.maxY, point.y)
            )
        }
        return CanvasRect(
            x: extents.minX,
            y: extents.minY,
            width: extents.maxX - extents.minX,
            height: extents.maxY - extents.minY
        )
    }
}

struct CanvasViewport: Codable, Equatable, Sendable {
    static let minimumZoom = 0.1
    static let maximumZoom = 8.0

    var origin: CanvasPoint
    private(set) var zoom: Double

    init(origin: CanvasPoint = .zero, zoom: Double = 1) {
        self.origin = origin
        self.zoom = Self.clampedZoom(zoom)
    }

    static func clampedZoom(_ zoom: Double) -> Double {
        min(maximumZoom, max(minimumZoom, zoom))
    }

    func screenPoint(for canvasPoint: CanvasPoint) -> CanvasPoint {
        CanvasPoint(x: (canvasPoint.x - origin.x) * zoom, y: (canvasPoint.y - origin.y) * zoom)
    }

    func canvasPoint(for screenPoint: CanvasPoint) -> CanvasPoint {
        CanvasPoint(x: screenPoint.x / zoom + origin.x, y: screenPoint.y / zoom + origin.y)
    }
}
