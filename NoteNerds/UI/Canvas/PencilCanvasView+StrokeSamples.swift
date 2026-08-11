import PencilKit

extension PencilCanvasView.Coordinator {
    func receiveModelStrokes(_ strokes: [Stroke]) {
        guard !isUsingTool else {
            pendingModelStrokes = strokes
            return
        }
        canonicalStrokes = strokes
        pendingModelStrokes = nil
    }

    func mergingPendingModelStrokes(
        with localStrokes: [Stroke],
        comparedTo baselineStrokes: [Stroke]
    ) -> [Stroke] {
        guard let pendingModelStrokes else { return localStrokes }
        let baselineIDs = Set(baselineStrokes.map(\.id))
        let localStrokesByID = Dictionary(uniqueKeysWithValues: localStrokes.map { ($0.id, $0) })
        var mergedStrokes = pendingModelStrokes.compactMap { stroke in
            baselineIDs.contains(stroke.id) ? localStrokesByID[stroke.id] : stroke
        }
        let mergedIDs = Set(mergedStrokes.map(\.id))
        mergedStrokes.append(contentsOf: localStrokes.filter { !mergedIDs.contains($0.id) })
        return mergedStrokes
    }

    func reconciledCanonicalStrokes(
        from pencilStrokes: [PKStroke],
        preserving sourceStrokes: [Stroke]
    ) -> [Stroke] {
        let sourceIndicesBySeed = Dictionary(grouping: sourceStrokes.indices) { index in
            PencilKitStrokeArchiveCodec.randomSeed(for: sourceStrokes[index])
        }
        var unusedSourceIndices = Set(sourceStrokes.indices)
        return pencilStrokes.compactMap { pencilStroke in
            let seedMatchingIndex = sourceIndicesBySeed[pencilStroke.randomSeed]?.filter {
                unusedSourceIndices.contains($0)
            }.min { firstIndex, secondIndex in
                strokeIdentityDistance(pencilStroke, source: sourceStrokes[firstIndex])
                    < strokeIdentityDistance(pencilStroke, source: sourceStrokes[secondIndex])
            }
            guard let sourceIndex = seedMatchingIndex
                ?? unusedSourceIndices.min() else { return nil }
            unusedSourceIndices.remove(sourceIndex)
            return canonicalStroke(from: pencilStroke, preserving: sourceStrokes[sourceIndex])
        }
    }

    private func strokeIdentityDistance(_ pencilStroke: PKStroke, source: Stroke) -> CGFloat {
        guard let sourceStroke = PencilKitStrokeArchiveCodec.stroke(for: source) else {
            return .greatestFiniteMagnitude
        }
        let transformDistance = zip(
            pencilStroke.transform.components,
            sourceStroke.transform.components
        ).reduce(CGFloat.zero) { distance, components in
            distance + abs(components.0 - components.1)
        }
        let boundsDistance = zip(
            pencilStroke.renderBounds.components,
            sourceStroke.renderBounds.components
        ).reduce(CGFloat.zero) { distance, components in
            distance + abs(components.0 - components.1)
        }
        return transformDistance * 1_000_000 + boundsDistance
    }

    private func canonicalStroke(from pencilStroke: PKStroke, preserving source: Stroke) -> Stroke {
        let points = Array(pencilStroke.path)
        let samples = points.enumerated().map { index, point in
            canonicalSample(
                from: point,
                transformedBy: pencilStroke.transform,
                roll: source.samples.indices.contains(index) ? source.samples[index].roll : 0
            )
        }
        let stroke = Stroke(
            id: source.id,
            layerID: source.layerID,
            samples: samples,
            style: source.style,
            createdAt: source.createdAt,
            pencilKitArchive: nil
        )
        return PencilKitStrokeArchiveCodec.preserving(pencilStroke, in: stroke)
    }

    func canonicalSample(
        from point: PKStrokePoint,
        transformedBy transform: CGAffineTransform,
        roll: Double
    ) -> StrokeSample {
        let location = point.location.applying(transform)
        let horizontalScale = hypot(transform.a, transform.b)
        let verticalScale = hypot(transform.c, transform.d)
        return StrokeSample(
            point: CanvasPoint(x: location.x, y: location.y),
            pressure: point.force,
            altitude: point.altitude,
            azimuth: point.azimuth,
            roll: roll,
            timeOffset: point.timeOffset,
            rendering: StrokeSampleRendering(
                size: CanvasSize(
                    width: point.size.width * horizontalScale,
                    height: point.size.height * verticalScale
                ),
                opacity: point.opacity,
                secondaryScale: point.secondaryScale,
                threshold: point.threshold
            )
        )
    }
}

private extension CGAffineTransform {
    var components: [CGFloat] { [a, b, c, d, tx, ty] }
}

private extension CGRect {
    var components: [CGFloat] { [origin.x, origin.y, size.width, size.height] }
}
