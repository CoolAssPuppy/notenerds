import PencilKit

private struct PencilAppendReconciliationRequest {
    let drawing: PKDrawing
    let committedDrawing: PKDrawing
    let baseline: [Stroke]
    let pendingInputs: [PendingPencilStrokeInput]
    let canAppend: Bool
    let shouldCancel: () -> Bool
}

enum PencilDrawingReconciler {
    static func reconcile(
        drawing: PKDrawing,
        committedDrawing: PKDrawing?,
        baseline: [Stroke],
        contacts: [PencilContactSnapshot],
        fallbackInput: PencilStrokeInput,
        shouldCancel: @escaping () -> Bool = { false }
    ) -> PencilDrawingReconciliation? {
        guard !shouldCancel() else { return nil }
        let pendingInputs = pendingStrokeInputs(
            committedDrawing: committedDrawing,
            contacts: contacts,
            finalDrawing: drawing,
            fallbackInput: fallbackInput,
            shouldCancel: shouldCancel
        )
        if let committedDrawing,
           let appended = appendedReconciliation(PencilAppendReconciliationRequest(
               drawing: drawing,
               committedDrawing: committedDrawing,
               baseline: baseline,
               pendingInputs: pendingInputs,
               canAppend: !contacts.isEmpty && contacts.allSatisfy {
                   $0.input.configuration.tool.instrument != nil
               },
               shouldCancel: shouldCancel
           )) {
            return appended
        }
        return fullReconciliation(PencilFullReconciliationRequest(
            drawing: drawing,
            baseline: baseline,
            pendingInputs: pendingInputs,
            fallbackInput: fallbackInput,
            shouldCancel: shouldCancel
        ))
    }

    private static func pendingStrokeInputs(
        committedDrawing: PKDrawing?,
        contacts: [PencilContactSnapshot],
        finalDrawing: PKDrawing,
        fallbackInput: PencilStrokeInput,
        shouldCancel: () -> Bool
    ) -> [PendingPencilStrokeInput] {
        var previousCount = committedDrawing?.strokes.count ?? 0
        var pending: [PendingPencilStrokeInput] = []
        for contact in contacts {
            guard !shouldCancel() else { return [] }
            if contact.input.configuration.tool.instrument != nil {
                pending.append(contentsOf: contact.appendedStrokeKeys.map {
                    PendingPencilStrokeInput(key: $0, input: contact.input)
                })
            }
            previousCount = contact.endingStrokeCount
        }
        let finalStrokes = finalDrawing.strokes
        if finalStrokes.count > previousCount,
           fallbackInput.configuration.tool.instrument != nil {
            pending.append(contentsOf: finalStrokes.dropFirst(previousCount).map {
                PendingPencilStrokeInput(key: PencilNativeStrokeKey($0), input: fallbackInput)
            })
        }
        return pending
    }

    static func takeInput(
        for stroke: PKStroke,
        from pending: inout [PendingPencilStrokeInput]
    ) -> PencilStrokeInput? {
        let key = PencilNativeStrokeKey(stroke)
        let matchingIndices = pending.indices.filter { pending[$0].key == key }
        guard let index = matchingIndices.first else { return nil }
        if matchingIndices.count == 1 { return pending[index].input }
        return pending.remove(at: index).input
    }

    private static func appendedReconciliation(
        _ request: PencilAppendReconciliationRequest
    ) -> PencilDrawingReconciliation? {
        let committedStrokes = request.committedDrawing.strokes
        let incomingStrokes = request.drawing.strokes
        guard request.canAppend,
              request.baseline.count == committedStrokes.count,
              incomingStrokes.count > committedStrokes.count,
              unchangedCommittedPrefix(
                  incomingStrokes,
                  committedStrokes: committedStrokes,
                  shouldCancel: request.shouldCancel
              ) else {
            return nil
        }
        var availableInputs = request.pendingInputs
        var completed: [CompletedPencilStroke] = []
        for stroke in incomingStrokes.dropFirst(committedStrokes.count) {
            guard !request.shouldCancel() else { return nil }
            let input = takeInput(for: stroke, from: &availableInputs)
            guard let input,
                  let canonical = newStroke(
                      from: stroke,
                      input: input,
                      shouldCancel: request.shouldCancel
                  ) else {
                return nil
            }
            completed.append(CompletedPencilStroke(
                stroke: canonical,
                shouldConvertToText: input.configuration.tool == .handwritingToText
            ))
        }
        return PencilDrawingReconciliation(
            edit: CanvasStrokeEdit(
                before: request.baseline,
                after: request.baseline + completed.map(\.stroke)
            ),
            completedStrokes: completed,
            reusedStrokeCount: request.baseline.count,
            publication: .completedStrokes
        )
    }

    private static func unchangedCommittedPrefix(
        _ incomingStrokes: [PKStroke],
        committedStrokes: [PKStroke],
        shouldCancel: () -> Bool
    ) -> Bool {
        for index in committedStrokes.indices {
            guard !shouldCancel() else { return false }
            let incoming = incomingStrokes[index]
            let committed = committedStrokes[index]
            guard matchingNativeStroke(
                incoming,
                committed,
                shouldCancel: shouldCancel
            ) else { return false }
        }
        return true
    }

    private static func matchingNativeStroke(
        _ incoming: PKStroke,
        _ committed: PKStroke,
        shouldCancel: () -> Bool
    ) -> Bool {
        guard incoming.randomSeed == committed.randomSeed,
              incoming.path.creationDate == committed.path.creationDate,
              approximatelyEqual(incoming.transform.components, committed.transform.components),
              approximatelyEqual(incoming.renderBounds.components, committed.renderBounds.components),
              incoming.maskedPathRanges == committed.maskedPathRanges,
              incoming.ink.inkType == committed.ink.inkType,
              incoming.ink.color.isEqual(committed.ink.color),
              incoming.path.count == committed.path.count else { return false }
        for points in zip(incoming.path, committed.path) {
            guard !shouldCancel(), matchingNativePoint(points.0, points.1) else { return false }
        }
        return true
    }

    private static func matchingNativePoint(_ incoming: PKStrokePoint, _ committed: PKStrokePoint) -> Bool {
        approximatelyEqual(incoming.location.x, committed.location.x)
            && approximatelyEqual(incoming.location.y, committed.location.y)
            && approximatelyEqual(incoming.timeOffset, committed.timeOffset)
            && approximatelyEqual(incoming.size.width, committed.size.width)
            && approximatelyEqual(incoming.size.height, committed.size.height)
            && approximatelyEqual(incoming.opacity, committed.opacity)
            && approximatelyEqual(incoming.force, committed.force)
            && approximatelyEqual(incoming.azimuth, committed.azimuth)
            && approximatelyEqual(incoming.altitude, committed.altitude)
            && approximatelyEqual(incoming.secondaryScale, committed.secondaryScale)
            && approximatelyEqual(incoming.threshold, committed.threshold)
    }

    static func approximatelyEqual<T: BinaryFloatingPoint>(
        _ incoming: T,
        _ committed: T,
        tolerance: T = 0.002
    ) -> Bool {
        abs(incoming - committed) <= tolerance
    }

    private static func approximatelyEqual<T: BinaryFloatingPoint>(
        _ incoming: [T],
        _ committed: [T]
    ) -> Bool {
        incoming.count == committed.count
            && zip(incoming, committed).allSatisfy { approximatelyEqual($0.0, $0.1) }
    }

    static func newStroke(
        from pencilStroke: PKStroke,
        input: PencilStrokeInput,
        shouldCancel: () -> Bool
    ) -> Stroke? {
        guard let instrument = input.configuration.tool.instrument else { return nil }
        var samples: [StrokeSample] = []
        samples.reserveCapacity(pencilStroke.path.count)
        for point in pencilStroke.path {
            guard !shouldCancel() else { return nil }
            samples.append(canonicalSample(
                from: point,
                transformedBy: pencilStroke.transform,
                roll: input.pencilRoll
            ))
        }
        guard !samples.isEmpty else { return nil }
        let stroke = Stroke(
            id: StrokeID(),
            layerID: input.layerID,
            samples: samples,
            style: StrokeStyle(
                instrument: instrument,
                width: input.configuration.width.points,
                color: input.configuration.color
            ),
            createdAt: input.createdAt,
            pencilKitArchive: nil
        )
        return PencilKitStrokeArchiveCodec.preserving(pencilStroke, in: stroke)
    }

    static func canonicalSample(
        from point: PKStrokePoint,
        transformedBy transform: CGAffineTransform,
        roll: Double
    ) -> StrokeSample {
        PencilKitStrokeArchiveCodec.sample(
            from: point,
            transformedBy: transform,
            roll: roll
        )
    }
}
