import PencilKit

extension PencilCanvasView.Coordinator {
    func canonicalSample(
        from point: PKStrokePoint,
        transformedBy transform: CGAffineTransform,
        roll: Double
    ) -> StrokeSample {
        let threshold: Double?
        if #available(iOS 26.0, *) {
            threshold = point.threshold
        } else {
            threshold = nil
        }
        let location = point.location.applying(transform)
        return StrokeSample(
            point: CanvasPoint(x: location.x, y: location.y),
            pressure: point.force,
            altitude: point.altitude,
            azimuth: point.azimuth,
            roll: roll,
            timeOffset: point.timeOffset,
            rendering: StrokeSampleRendering(
                size: CanvasSize(width: point.size.width, height: point.size.height),
                opacity: point.opacity,
                secondaryScale: point.secondaryScale,
                threshold: threshold
            )
        )
    }
}
