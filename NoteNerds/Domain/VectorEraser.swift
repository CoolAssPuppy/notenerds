import Foundation

struct VectorEraser: Sendable {
    func erase(_ stroke: Stroke, along eraserPoints: [CanvasPoint], radius: Double) -> [Stroke] {
        guard !eraserPoints.isEmpty, radius >= 0 else { return [stroke] }
        let remainingGroups = stroke.samples.split { sample in
            eraserPoints.contains { point in distance(from: sample.point, to: point) <= radius }
        }
        return remainingGroups.map { samples in
            Stroke(
                id: StrokeID(),
                layerID: stroke.layerID,
                samples: Array(samples),
                style: stroke.style,
                createdAt: stroke.createdAt
            )
        }
    }

    private func distance(from first: CanvasPoint, to second: CanvasPoint) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }
}
