import PencilKit

struct CompletedPencilStroke: Hashable, Sendable {
    let stroke: Stroke
    let shouldConvertToText: Bool
}

struct PencilStrokeInput: Sendable {
    let configuration: ToolConfiguration
    let layerID: LayerID
    let createdAt: Date
    let pencilRoll: Double

    init(
        configuration: ToolConfiguration,
        layerID: LayerID,
        createdAt: Date,
        pencilRoll: Double = 0
    ) {
        self.configuration = configuration
        self.layerID = layerID
        self.createdAt = createdAt
        self.pencilRoll = pencilRoll
    }
}

struct PencilContactSnapshot: Sendable {
    let input: PencilStrokeInput
    let appendedStrokeKeys: [PencilNativeStrokeKey]
    let endingStrokeCount: Int
}

enum PencilDrawingPublication: Equatable, Sendable {
    case none
    case completedStrokes
    case drawingChanged
}

struct PencilDrawingReconciliation: Sendable {
    let edit: CanvasStrokeEdit
    let completedStrokes: [CompletedPencilStroke]
    let reusedStrokeCount: Int
    let publication: PencilDrawingPublication
}

actor PencilDrawingReconciliationWorker {
    func reconcile(
        drawing: PKDrawing,
        committedDrawing: PKDrawing?,
        baseline: [Stroke],
        contacts: [PencilContactSnapshot],
        fallbackInput: PencilStrokeInput
    ) -> PencilDrawingReconciliation? {
        PencilDrawingReconciler.reconcile(
            drawing: drawing,
            committedDrawing: committedDrawing,
            baseline: baseline,
            contacts: contacts,
            fallbackInput: fallbackInput,
            shouldCancel: { Task.isCancelled }
        )
    }
}

struct PencilNativeStrokeKey: Hashable, Sendable {
    let randomSeed: UInt32
    let creationDate: Date

    init(_ stroke: PKStroke) {
        randomSeed = stroke.randomSeed
        creationDate = stroke.path.creationDate
    }
}

struct PendingPencilStrokeInput: Sendable {
    let key: PencilNativeStrokeKey
    let input: PencilStrokeInput
}

extension PencilDrawingReconciler {
    static func edit(
        drawing: PKDrawing,
        baseline: [Stroke],
        activeLayerID: LayerID,
        configuration: ToolConfiguration,
        pencilRoll: Double = 0,
        createdAt: Date
    ) -> CanvasStrokeEdit {
        let input = PencilStrokeInput(
            configuration: configuration,
            layerID: activeLayerID,
            createdAt: createdAt,
            pencilRoll: pencilRoll
        )
        return reconcile(
            drawing: drawing,
            committedDrawing: nil,
            baseline: baseline,
            contacts: [],
            fallbackInput: input
        )?.edit ?? CanvasStrokeEdit(before: baseline, after: baseline)
    }
}

extension CGAffineTransform {
    var components: [CGFloat] { [a, b, c, d, tx, ty] }
}

extension CGRect {
    var components: [CGFloat] { [origin.x, origin.y, size.width, size.height] }
}

struct PencilFullReconciliationRequest {
    let drawing: PKDrawing
    let baseline: [Stroke]
    let pendingInputs: [PendingPencilStrokeInput]
    let fallbackInput: PencilStrokeInput
    let shouldCancel: () -> Bool
}

private struct PencilSourceStrokeCandidate {
    let index: Int
    let nativeStroke: PKStroke?
}

private enum PencilSourceMatch {
    case found(PencilSourceStrokeCandidate)
    case noMatch
    case cancelled
}

private enum PencilStrokeReconciliationStep {
    case handled
    case unmatched
    case cancelled
}

private struct PencilFullReconciliationState {
    let request: PencilFullReconciliationRequest
    let sourceCandidatesBySeed: [UInt32: [PencilSourceStrokeCandidate]]
    var unusedSourceIndices: Set<Int>
    var canonicalStrokes: [Stroke]
    var completedStrokes: [CompletedPencilStroke]
    var reusedStrokeCount: Int
    var availableInputs: [PendingPencilStrokeInput]

    var result: PencilDrawingReconciliation? {
        guard let publication = PencilDrawingPublication.classify(
            before: request.baseline,
            after: canonicalStrokes,
            hasCompletedStrokes: !completedStrokes.isEmpty,
            shouldCancel: request.shouldCancel
        ) else { return nil }
        return PencilDrawingReconciliation(
            edit: CanvasStrokeEdit(
                before: request.baseline,
                after: canonicalStrokes
            ),
            completedStrokes: completedStrokes,
            reusedStrokeCount: reusedStrokeCount,
            publication: publication
        )
    }
}

private extension PencilDrawingPublication {
    static func classify(
        before: [Stroke],
        after: [Stroke],
        hasCompletedStrokes: Bool,
        shouldCancel: () -> Bool
    ) -> PencilDrawingPublication? {
        let sharedCount = min(before.count, after.count)
        for index in 0..<sharedCount {
            guard !shouldCancel() else { return nil }
            if before[index] != after[index] { return .drawingChanged }
        }
        if before.count == after.count { return PencilDrawingPublication.none }
        if after.count > before.count, hasCompletedStrokes { return .completedStrokes }
        return .drawingChanged
    }
}

extension PencilDrawingReconciler {
    static func fullReconciliation(
        _ request: PencilFullReconciliationRequest
    ) -> PencilDrawingReconciliation? {
        guard var state = makeFullReconciliationState(request) else { return nil }
        for pencilStroke in request.drawing.strokes {
            guard reconcileStroke(pencilStroke, state: &state) else { return nil }
        }
        return state.result
    }

    private static func makeFullReconciliationState(
        _ request: PencilFullReconciliationRequest
    ) -> PencilFullReconciliationState? {
        var candidatesBySeed: [UInt32: [PencilSourceStrokeCandidate]] = [:]
        var unusedSourceIndices = Set<Int>()
        for index in request.baseline.indices {
            guard !request.shouldCancel() else { return nil }
            let nativeStroke = PencilKitStrokeArchiveCodec.stroke(for: request.baseline[index])
            let randomSeed = nativeStroke?.randomSeed
                ?? PencilKitStrokeArchiveCodec.randomSeed(for: request.baseline[index])
            candidatesBySeed[randomSeed, default: []].append(
                PencilSourceStrokeCandidate(index: index, nativeStroke: nativeStroke)
            )
            unusedSourceIndices.insert(index)
        }
        return PencilFullReconciliationState(
            request: request,
            sourceCandidatesBySeed: candidatesBySeed,
            unusedSourceIndices: unusedSourceIndices,
            canonicalStrokes: [],
            completedStrokes: [],
            reusedStrokeCount: 0,
            availableInputs: request.pendingInputs
        )
    }

    private static func reconcileStroke(
        _ pencilStroke: PKStroke,
        state: inout PencilFullReconciliationState
    ) -> Bool {
        guard !state.request.shouldCancel() else { return false }
        let candidates = state.sourceCandidatesBySeed[pencilStroke.randomSeed, default: []]
        switch reconcileUnusedSource(pencilStroke, candidates: candidates, state: &state) {
        case .handled:
            return true
        case .cancelled:
            return false
        case .unmatched:
            break
        }
        switch reconcileSplitSource(pencilStroke, candidates: candidates, state: &state) {
        case .handled:
            return true
        case .cancelled:
            return false
        case .unmatched:
            break
        }
        if appendPendingStroke(pencilStroke, state: &state) { return true }
        return appendUnmatchedStroke(pencilStroke, state: &state)
    }

    private static func reconcileUnusedSource(
        _ pencilStroke: PKStroke,
        candidates: [PencilSourceStrokeCandidate],
        state: inout PencilFullReconciliationState
    ) -> PencilStrokeReconciliationStep {
        let match = closestSourceIndex(
            to: pencilStroke,
            candidates: candidates,
            availableIndices: state.unusedSourceIndices,
            shouldCancel: state.request.shouldCancel
        )
        guard case let .found(sourceCandidate) = match else {
            if case .cancelled = match { return .cancelled }
            return .unmatched
        }
        let sourceIndex = sourceCandidate.index
        state.unusedSourceIndices.remove(sourceIndex)
        if let nativeStroke = sourceCandidate.nativeStroke,
           matchesCanonicalStroke(
               pencilStroke,
               source: state.request.baseline[sourceIndex],
               archivedStroke: nativeStroke,
               shouldCancel: state.request.shouldCancel
           ) {
            state.canonicalStrokes.append(state.request.baseline[sourceIndex])
            state.reusedStrokeCount += 1
            return .handled
        }
        guard let stroke = canonicalStroke(
            from: pencilStroke,
            preserving: state.request.baseline[sourceIndex],
            pencilRoll: state.request.fallbackInput.pencilRoll,
            shouldCancel: state.request.shouldCancel
        ) else { return .cancelled }
        state.canonicalStrokes.append(stroke)
        return .handled
    }

    private static func reconcileSplitSource(
        _ pencilStroke: PKStroke,
        candidates: [PencilSourceStrokeCandidate],
        state: inout PencilFullReconciliationState
    ) -> PencilStrokeReconciliationStep {
        let match = closestSourceIndex(
            to: pencilStroke,
            candidates: candidates,
            availableIndices: nil,
            shouldCancel: state.request.shouldCancel
        )
        guard case let .found(sourceCandidate) = match else {
            if case .cancelled = match { return .cancelled }
            return .unmatched
        }
        guard let stroke = canonicalStroke(
            from: pencilStroke,
            preserving: state.request.baseline[sourceCandidate.index],
            id: StrokeID(),
            pencilRoll: state.request.fallbackInput.pencilRoll,
            shouldCancel: state.request.shouldCancel
        ) else { return .cancelled }
        state.canonicalStrokes.append(stroke)
        return .handled
    }

    private static func appendPendingStroke(
        _ pencilStroke: PKStroke,
        state: inout PencilFullReconciliationState
    ) -> Bool {
        guard let input = takeInput(for: pencilStroke, from: &state.availableInputs),
              let stroke = newStroke(
                  from: pencilStroke,
                  input: input,
                  shouldCancel: state.request.shouldCancel
              ) else {
            return false
        }
        appendCompletedStroke(stroke, input: input, state: &state)
        return true
    }

    private static func appendUnmatchedStroke(
        _ pencilStroke: PKStroke,
        state: inout PencilFullReconciliationState
    ) -> Bool {
        if state.request.drawing.strokes.count <= state.request.baseline.count,
           let sourceIndex = state.unusedSourceIndices.min() {
            state.unusedSourceIndices.remove(sourceIndex)
            guard let stroke = canonicalStroke(
                from: pencilStroke,
                preserving: state.request.baseline[sourceIndex],
                pencilRoll: state.request.fallbackInput.pencilRoll,
                shouldCancel: state.request.shouldCancel
            ) else { return false }
            state.canonicalStrokes.append(stroke)
            return true
        }
        if let stroke = newStroke(
            from: pencilStroke,
            input: state.request.fallbackInput,
            shouldCancel: state.request.shouldCancel
        ) {
            appendCompletedStroke(stroke, input: state.request.fallbackInput, state: &state)
        }
        return true
    }

    private static func appendCompletedStroke(
        _ stroke: Stroke,
        input: PencilStrokeInput,
        state: inout PencilFullReconciliationState
    ) {
        state.canonicalStrokes.append(stroke)
        state.completedStrokes.append(CompletedPencilStroke(
            stroke: stroke,
            shouldConvertToText: input.configuration.tool == .handwritingToText
        ))
    }

    private static func matchesCanonicalStroke(
        _ pencilStroke: PKStroke,
        source: Stroke,
        archivedStroke: PKStroke,
        shouldCancel: () -> Bool
    ) -> Bool {
        guard pencilStroke.randomSeed == archivedStroke.randomSeed,
              pencilStroke.maskedPathRanges == archivedStroke.maskedPathRanges,
              pencilStroke.path.count == source.samples.count else { return false }
        for (index, point) in pencilStroke.path.enumerated() {
            guard !shouldCancel() else { return false }
            let incomingSample = canonicalSample(
                from: point,
                transformedBy: pencilStroke.transform,
                roll: source.samples[index].roll
            )
            guard matchingCanonicalSample(incomingSample, source.samples[index]) else { return false }
        }
        return true
    }

    private static func matchingCanonicalSample(
        _ incoming: StrokeSample,
        _ source: StrokeSample
    ) -> Bool {
        approximatelyEqual(incoming.point.x, source.point.x)
            && approximatelyEqual(incoming.point.y, source.point.y)
            && approximatelyEqual(incoming.pressure, source.pressure)
            && approximatelyEqual(incoming.altitude, source.altitude)
            && approximatelyEqual(incoming.azimuth, source.azimuth)
            && approximatelyEqual(incoming.roll, source.roll)
            && approximatelyEqual(incoming.timeOffset, source.timeOffset)
            && approximatelyEqual(incoming.renderedSize?.width, source.renderedSize?.width)
            && approximatelyEqual(incoming.renderedSize?.height, source.renderedSize?.height)
            && approximatelyEqual(incoming.renderedOpacity, source.renderedOpacity)
            && approximatelyEqual(incoming.secondaryScale, source.secondaryScale)
            && approximatelyEqual(incoming.threshold, source.threshold)
    }

    private static func approximatelyEqual(
        _ incoming: Double?,
        _ source: Double?
    ) -> Bool {
        switch (incoming, source) {
        case let (.some(incoming), .some(source)):
            approximatelyEqual(incoming, source)
        case (.none, .none):
            true
        default:
            false
        }
    }

    private static func closestSourceIndex(
        to pencilStroke: PKStroke,
        candidates: [PencilSourceStrokeCandidate],
        availableIndices: Set<Int>?,
        shouldCancel: () -> Bool
    ) -> PencilSourceMatch {
        var closestCandidate: PencilSourceStrokeCandidate?
        var closestDistance = CGFloat.greatestFiniteMagnitude
        for candidate in candidates {
            guard availableIndices?.contains(candidate.index) ?? true else { continue }
            guard !shouldCancel() else { return .cancelled }
            let distance = strokeIdentityDistance(
                pencilStroke,
                sourceStroke: candidate.nativeStroke
            )
            if closestCandidate == nil || distance < closestDistance {
                closestCandidate = candidate
                closestDistance = distance
            }
        }
        return closestCandidate.map(PencilSourceMatch.found) ?? .noMatch
    }

    private static func strokeIdentityDistance(
        _ pencilStroke: PKStroke,
        sourceStroke: PKStroke?
    ) -> CGFloat {
        guard let sourceStroke else {
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

    private static func canonicalStroke(
        from pencilStroke: PKStroke,
        preserving source: Stroke,
        id: StrokeID? = nil,
        pencilRoll: Double,
        shouldCancel: () -> Bool
    ) -> Stroke? {
        var samples: [StrokeSample] = []
        samples.reserveCapacity(pencilStroke.path.count)
        for (index, point) in pencilStroke.path.enumerated() {
            guard !shouldCancel() else { return nil }
            samples.append(canonicalSample(
                from: point,
                transformedBy: pencilStroke.transform,
                roll: source.samples.indices.contains(index) ? source.samples[index].roll : pencilRoll
            ))
        }
        let stroke = Stroke(
            id: id ?? source.id,
            layerID: source.layerID,
            samples: samples,
            style: source.style,
            createdAt: source.createdAt,
            pencilKitArchive: nil
        )
        return PencilKitStrokeArchiveCodec.preserving(pencilStroke, in: stroke)
    }
}
