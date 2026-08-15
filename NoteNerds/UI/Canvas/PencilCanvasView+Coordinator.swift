import PencilKit
import SwiftUI

extension PencilCanvasView {
    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
        var knownStrokeCount = 0
        var canonicalStrokes: [Stroke] = []
        var isApplyingModelDrawing = false
        var lastNavigationCommandID: UUID?
        var lastEditingCommandID: UUID?
        weak var objectSelectionOverlay: CanvasSelectionOverlayView?
        weak var inlineTextEditor: InlineCanvasTextEditor?
        var overlay = CanvasOverlayState()
        var configuration = ToolConfiguration.favoriteOne
        var appliedToolConfiguration: ToolConfiguration?
        var activeLayerID: LayerID
        var isUsingTool = false
        var latestNativeDrawing: PKDrawing?
        var committedNativeDrawing: PKDrawing?
        var deferredModelStrokes: [Stroke]?
        var isDrawingCommitPending = false
        var drawingRevision: UInt64 = 0
        var drawingCommitTask: Task<Void, Never>?
        var immediateFlushTask: Task<Void, Never>?
        var immediateFlushGeneration: UUID?
        var isImmediateFlushInProgress = false
        let drawingWorker = PencilDrawingReconciliationWorker()
        var activeDrawingInput: PencilStrokeInput?
        var activeContactStartStrokeCount: Int?
        var completedContactSnapshots: [PencilContactSnapshot] = []
        var appliedModelDrawing: PKDrawing?
        weak var activeCanvasView: PKCanvasView?
        weak var snapshotFlusher: PencilCanvasSnapshotFlusher?
        let snapshotFlusherRegistrationID = PencilCanvasSnapshotFlusher.RegistrationID()
        var latestPencilRoll = 0.0
        var latestPencilLocation: CGPoint?
        var paperType: PaperType?
        var hasAppliedInitialPlannerViewport = false
        var canvasID: CanvasID?
        var plannerRegions: [CanvasRegion] = []
        var selectedPlannerRegionID: String?
        var isPlannerRegionPagingEnabled = false
        var shouldAnimatePlannerRegionChanges = true
        var lastFocusedCanvasID: CanvasID?
        var lastFocusedRegionID: String?
        var lastPlannerViewportSize = CGSize.zero
        var isApplyingPlannerViewport = false
        var hasRequestedRegionForCurrentPan = false
        private var onStrokesCompleted: @MainActor ([CompletedPencilStroke]) -> Void
        private var onDrawingChanged: @MainActor (CanvasStrokeEdit, [CompletedPencilStroke]) -> Void
        private var onConvertStrokesToText: @MainActor ([Stroke]) -> Void
        private var onViewportChanged: @MainActor (CanvasRect) -> Void
        private var onPencilSqueeze: @MainActor (PencilSqueezeResponse, CGPoint?) -> Void
        private var onPencilDoubleTap: @MainActor () -> Void
        var onPlannerRegionPageRequested: @MainActor (Int) -> Void
        private var onPencilContactChanged: @MainActor (Bool) -> Void

        init(activeLayerID: LayerID, actions: PencilCanvasActions) {
            self.activeLayerID = activeLayerID
            self.onStrokesCompleted = actions.onStrokesCompleted
            self.onDrawingChanged = actions.onDrawingChanged
            self.onConvertStrokesToText = actions.onConvertStrokesToText
            self.onViewportChanged = actions.onViewportChanged
            self.onPencilSqueeze = actions.onPencilSqueeze
            self.onPencilDoubleTap = actions.onPencilDoubleTap
            self.onPlannerRegionPageRequested = actions.onPlannerRegionPageRequested
            self.onPencilContactChanged = actions.onPencilContactChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingModelDrawing else { return }
            if let appliedModelDrawing, canvasView.drawing == appliedModelDrawing {
                self.appliedModelDrawing = nil
                return
            }
            appliedModelDrawing = nil
            captureNativeDrawing(from: canvasView)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            CanvasDiagnostics.mark("contact began strokes=\(canvasView.drawing.strokes.count)")
            drawingCommitTask?.cancel()
            drawingCommitTask = nil
            if committedNativeDrawing == nil,
               canvasView.drawing.strokes.count == canonicalStrokes.count {
                committedNativeDrawing = canvasView.drawing
                latestNativeDrawing = canvasView.drawing
            }
            setPencilContactActive(true)
            isDrawingCommitPending = true
            activeContactStartStrokeCount = canvasView.drawing.strokes.count
            activeDrawingInput = PencilStrokeInput(
                configuration: configuration,
                layerID: activeLayerID,
                createdAt: Date(),
                pencilRoll: latestPencilRoll
            )
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            CanvasDiagnostics.mark("contact ended strokes=\(canvasView.drawing.strokes.count)")
            setPencilContactActive(false)
            completeActiveContact(with: canvasView.drawing)
            applyToolIfNeeded(to: canvasView)
            captureNativeDrawing(from: canvasView)
        }

        /// Installs the selected tool on the canvas when it differs from the one
        /// already there. A tool chosen during a contact, through a Pencil
        /// squeeze or double tap, waits until the tip lifts so the stroke in
        /// progress is not cancelled.
        func applyToolIfNeeded(to canvasView: PKCanvasView) {
            guard appliedToolConfiguration != configuration, !isUsingTool else { return }
            appliedToolConfiguration = configuration
            canvasView.tool = PencilCanvasView.tool(for: configuration)
        }

        var isProtectingNativeDrawing: Bool {
            isUsingTool || isDrawingCommitPending
        }

        func receiveModelStrokes(_ strokes: [Stroke]) {
            guard !isProtectingNativeDrawing else {
                deferredModelStrokes = PencilCanvasModelReconciliation.isSameRenderedContent(
                    strokes,
                    canonicalStrokes
                ) ? nil : strokes
                return
            }
            canonicalStrokes = strokes
            deferredModelStrokes = nil
        }

        func tagAppliedModelDrawing(_ drawing: PKDrawing) {
            appliedModelDrawing = drawing
            latestNativeDrawing = drawing
            committedNativeDrawing = drawing
        }

        func updateHandlers(from view: PencilCanvasView) {
            onStrokesCompleted = view.actions.onStrokesCompleted
            onDrawingChanged = view.actions.onDrawingChanged
            onConvertStrokesToText = view.actions.onConvertStrokesToText
            onViewportChanged = view.actions.onViewportChanged
            onPencilSqueeze = view.actions.onPencilSqueeze
            onPencilDoubleTap = view.actions.onPencilDoubleTap
            onPlannerRegionPageRequested = view.actions.onPlannerRegionPageRequested
            onPencilContactChanged = view.actions.onPencilContactChanged
        }

        func attachSnapshotFlusher(
            _ snapshotFlusher: PencilCanvasSnapshotFlusher,
            canvasView: PKCanvasView
        ) {
            activeCanvasView = canvasView
            guard self.snapshotFlusher !== snapshotFlusher else { return }
            self.snapshotFlusher?.detach(id: snapshotFlusherRegistrationID)
            self.snapshotFlusher = snapshotFlusher
            snapshotFlusher.attach(id: snapshotFlusherRegistrationID) { [weak self] in
                await self?.flushPendingDrawing()
            }
        }

        private func captureNativeDrawing(from canvasView: PKCanvasView) {
            latestNativeDrawing = canvasView.drawing
            isDrawingCommitPending = true
            drawingRevision &+= 1
            guard !isUsingTool,
                  !isImmediateFlushInProgress else { return }
            scheduleDrawingCommit(for: canvasView)
        }

        private func completeActiveContact(with drawing: PKDrawing) {
            guard let activeDrawingInput else { return }
            let startIndex = min(
                activeContactStartStrokeCount ?? drawing.strokes.count,
                drawing.strokes.count
            )
            let appendedStrokeKeys = activeDrawingInput.configuration.tool.instrument == nil
                ? []
                : drawing.strokes.dropFirst(startIndex).map(PencilNativeStrokeKey.init)
            completedContactSnapshots.append(PencilContactSnapshot(
                input: activeDrawingInput,
                appendedStrokeKeys: appendedStrokeKeys,
                endingStrokeCount: drawing.strokes.count
            ))
            self.activeDrawingInput = nil
            activeContactStartStrokeCount = nil
        }

        private func scheduleDrawingCommit(for canvasView: PKCanvasView) {
            drawingCommitTask?.cancel()
            let revision = drawingRevision
            let drawing = latestNativeDrawing ?? canvasView.drawing
            let baseline = canonicalStrokes
            let committedDrawing = committedNativeDrawing
            let contacts = completedContactSnapshots
            let fallbackInput = activeDrawingInput ?? contacts.last?.input ?? PencilStrokeInput(
                configuration: configuration,
                layerID: activeLayerID,
                createdAt: Date(),
                pencilRoll: latestPencilRoll
            )
            drawingCommitTask = Task { @MainActor [self, weak canvasView] in
                do {
                    try await Task.sleep(for: .milliseconds(120))
                } catch {
                    return
                }
                guard let result = await drawingWorker.reconcile(
                    drawing: drawing,
                    committedDrawing: committedDrawing,
                    baseline: baseline,
                    contacts: contacts,
                    fallbackInput: fallbackInput
                ), !Task.isCancelled,
                      !isUsingTool,
                      revision == drawingRevision else { return }
                finishDrawingCommit(result, drawing: drawing, in: canvasView)
            }
        }

        private func finishDrawingCommit(
            _ result: PencilDrawingReconciliation,
            drawing: PKDrawing,
            in canvasView: PKCanvasView?
        ) {
            CanvasDiagnostics.mark(
                "commit publish=\(result.publication) strokes=\(result.edit.after.count)"
            )
            let edit = result.edit
            canonicalStrokes = edit.after
            knownStrokeCount = edit.after.count
            committedNativeDrawing = drawing
            isDrawingCommitPending = false
            drawingCommitTask = nil
            activeDrawingInput = nil
            activeContactStartStrokeCount = nil
            completedContactSnapshots = []
            switch result.publication {
            case .none:
                if let canvasView { applyDeferredModelDrawingIfNeeded(to: canvasView) }
            case .completedStrokes:
                onStrokesCompleted(result.completedStrokes)
            case .drawingChanged:
                onDrawingChanged(edit, result.completedStrokes)
            }
        }

        private func applyDeferredModelDrawingIfNeeded(to canvasView: PKCanvasView) {
            guard let deferredModelStrokes,
                  !PencilCanvasModelReconciliation.isSameRenderedContent(
                      deferredModelStrokes,
                      canonicalStrokes
                  ) else {
                self.deferredModelStrokes = nil
                return
            }
            let drawing = PencilCanvasRenderer.drawing(from: deferredModelStrokes)
            isApplyingModelDrawing = true
            tagAppliedModelDrawing(drawing)
            canvasView.drawing = drawing
            canonicalStrokes = deferredModelStrokes
            knownStrokeCount = deferredModelStrokes.count
            committedNativeDrawing = drawing
            self.deferredModelStrokes = nil
            isApplyingModelDrawing = false
        }

        func prepareForDismantle(_ canvasView: PKCanvasView) {
            setPencilContactActive(false)
            completeActiveContact(with: canvasView.drawing)
            latestNativeDrawing = canvasView.drawing
            isDrawingCommitPending = true
            drawingRevision &+= 1
            activeCanvasView = nil
            let registrationID = snapshotFlusherRegistrationID
            let snapshotFlusher = snapshotFlusher
            let flushTask = Task { @MainActor [self] in
                await flushPendingDrawing()
            }
            snapshotFlusher?.attach(id: registrationID) {
                await flushTask.value
            }
            Task { @MainActor in
                await flushTask.value
                snapshotFlusher?.detach(id: registrationID)
            }
        }

        func flushPendingDrawing() async {
            if let immediateFlushTask {
                await immediateFlushTask.value
                return
            }
            let generation = UUID()
            immediateFlushGeneration = generation
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await performImmediateFlush()
            }
            immediateFlushTask = task
            await task.value
            if immediateFlushGeneration == generation {
                immediateFlushTask = nil
                immediateFlushGeneration = nil
            }
        }

        private func performImmediateFlush() async {
            isImmediateFlushInProgress = true
            defer { isImmediateFlushInProgress = false }
            drawingCommitTask?.cancel()
            drawingCommitTask = nil
            if let canvasView = activeCanvasView {
                if isUsingTool {
                    setPencilContactActive(false)
                    completeActiveContact(with: canvasView.drawing)
                }
                latestNativeDrawing = canvasView.drawing
                isDrawingCommitPending = true
                drawingRevision &+= 1
            }
            while isDrawingCommitPending {
                let revision = drawingRevision
                guard let drawing = latestNativeDrawing else { return }
                let baseline = canonicalStrokes
                let committedDrawing = committedNativeDrawing
                let contacts = completedContactSnapshots
                let fallbackInput = activeDrawingInput ?? contacts.last?.input ?? PencilStrokeInput(
                    configuration: configuration,
                    layerID: activeLayerID,
                    createdAt: Date(),
                    pencilRoll: latestPencilRoll
                )
                guard let result = await drawingWorker.reconcile(
                    drawing: drawing,
                    committedDrawing: committedDrawing,
                    baseline: baseline,
                    contacts: contacts,
                    fallbackInput: fallbackInput
                ) else { return }
                guard revision == drawingRevision else { continue }
                finishDrawingCommit(result, drawing: drawing, in: activeCanvasView)
            }
        }

        private func setPencilContactActive(_ isActive: Bool) {
            guard isUsingTool != isActive else { return }
            isUsingTool = isActive
            onPencilContactChanged(isActive)
        }

        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            CanvasDiagnostics.mark("pencil squeeze phase=\(squeeze.phase.rawValue)")
            latestPencilRoll = squeeze.hoverPose.map { Double($0.rollAngle) } ?? latestPencilRoll
            let response = PencilSqueezeBehavior.response(
                for: UIPencilInteraction.preferredSqueezeAction,
                phase: squeeze.phase
            )
            guard response != .none else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            onPencilSqueeze(
                response,
                PencilSqueezeBehavior.viewportLocation(
                    poseLocation: squeeze.hoverPose?.location,
                    lastHoverLocation: latestPencilLocation,
                    visibleBounds: interaction.view?.bounds ?? .zero
                )
            )
        }

        @objc func handlePencilHover(_ recognizer: UIHoverGestureRecognizer) {
            latestPencilRoll = Double(recognizer.rollAngle)
            switch recognizer.state {
            case .began, .changed:
                latestPencilLocation = recognizer.location(in: recognizer.view)
            case .ended, .cancelled:
                break
            default:
                break
            }
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            CanvasDiagnostics.mark("pencil double tap")
            onPencilDoubleTap()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let canvasView = scrollView as? PKCanvasView else { return }
            focusPlannerRegionIfNeeded(in: canvasView)
            reportViewport(canvasView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let canvasView = scrollView as? PKCanvasView else { return }
            CanvasOverlayGeometry.synchronizeZoom(in: canvasView)
            focusPlannerRegionIfNeeded(in: canvasView)
            reportViewport(canvasView)
        }

        func reportViewport(_ canvasView: PKCanvasView) {
            let zoom = Double(canvasView.zoomScale)
            onViewportChanged(CanvasRect(
                x: canvasView.contentOffset.x / zoom,
                y: canvasView.contentOffset.y / zoom,
                width: canvasView.bounds.width / zoom,
                height: canvasView.bounds.height / zoom
            ))
        }

        func convertSelectedStrokesToText(in canvasView: PKCanvasView) {
            if let strokes = objectSelectionOverlay?.selectedStrokes(), !strokes.isEmpty {
                onConvertStrokesToText(strokes)
                return
            }
            canvasView.copy(nil)
            let selectedDrawings = UIPasteboard.general.items.flatMap { item in
                item.values.compactMap { value -> PKDrawing? in
                    guard let data = value as? Data else { return nil }
                    return try? PKDrawing(data: data)
                }
            }
            guard let selectedDrawing = selectedDrawings.first(where: { !$0.strokes.isEmpty }) else { return }
            let selectedBounds = selectedDrawing.strokes.map(\.renderBounds)
            let selected = canonicalStrokes.filter { stroke in
                let bounds = stroke.bounds.pencilKitRect.insetBy(dx: -12, dy: -12)
                return selectedBounds.contains { $0.intersects(bounds) }
            }
            onConvertStrokesToText(selected)
        }
    }
}
