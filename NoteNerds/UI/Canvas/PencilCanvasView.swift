import PencilKit
import SwiftUI

struct PencilCanvasView: UIViewRepresentable {
    let strokes: [Stroke]
    let nonStrokeObjects: [CanvasObject]
    let assets: [AssetID: Data]
    let navigationCommand: CanvasNavigationCommand?
    let editingCommand: CanvasEditingCommand?
    let highlightedStrokeIDs: Set<StrokeID>
    let recognizedText: [String]
    let configuration: ToolConfiguration
    let canvasID: CanvasID
    let activeLayerID: LayerID
    let template: CanvasTemplate
    let plannerRegions: [CanvasRegion]
    let selectedPlannerRegionID: String?
    let isPlannerRegionPagingEnabled: Bool
    let shouldAnimatePlannerRegionChanges: Bool
    let isFingerDrawingEnabled: Bool
    let textEditingSession: CanvasTextEditingSession?
    let isTextToolActive: Bool
    let shapePlacementKind: RecognizedShapeKind?
    let onStrokesCompleted: @MainActor ([Stroke]) -> Void
    let onDrawingChanged: @MainActor ([Stroke]) -> Void
    let onConvertStrokesToText: @MainActor ([Stroke]) -> Void
    let onTransformObjects: @MainActor (Set<ObjectID>, SelectionTransform, CanvasPoint, [Stroke]) -> Void
    let onDeleteObjects: @MainActor (Set<ObjectID>) -> Void
    let onPasteObjects: @MainActor ([CanvasObject]) -> Void
    let onMoveObjectsToLayer: @MainActor (Set<ObjectID>, LayerID) -> Void
    let onEditText: @MainActor (TextBlock) -> Void
    let onPlaceText: @MainActor (CanvasPoint) -> Void
    let onPlaceShape: @MainActor (CanvasPoint) -> Void
    let onCommitText: @MainActor (TextBlock) -> Void
    let onCancelText: @MainActor () -> Void
    let onObjectSelectionChanged: @MainActor (Bool) -> Void
    let onViewportChanged: @MainActor (CanvasRect) -> Void
    let onPencilSqueeze: @MainActor (PencilSqueezeResponse, CGPoint?) -> Void
    let onPencilDoubleTap: @MainActor () -> Void
    let onPlannerRegionPageRequested: @MainActor (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            activeLayerID: activeLayerID,
            onStrokesCompleted: onStrokesCompleted,
            onDrawingChanged: onDrawingChanged,
            onConvertStrokesToText: onConvertStrokesToText,
            onViewportChanged: onViewportChanged,
            onPencilSqueeze: onPencilSqueeze,
            onPencilDoubleTap: onPencilDoubleTap,
            onPlannerRegionPageRequested: onPlannerRegionPageRequested
        )
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        let coordinator = context.coordinator
        PencilCanvasInputAccessories.install(on: canvasView, coordinator: coordinator)
        configureViewport(canvasView)
        addPlannerSwipeRecognizers(to: canvasView, coordinator: context.coordinator)
        updatePlannerContext(context.coordinator)
        applyPaper(to: canvasView, coordinator: context.coordinator)
        canvasView.isOpaque = true
        canvasView.alwaysBounceHorizontal = true
        canvasView.alwaysBounceVertical = true
        context.coordinator.isApplyingModelDrawing = true
        canvasView.drawing = PencilCanvasRenderer.drawing(from: strokes)
        context.coordinator.knownStrokeCount = strokes.count
        context.coordinator.canonicalStrokes = strokes
        context.coordinator.isApplyingModelDrawing = false
        updateObjectOverlays(in: canvasView, coordinator: context.coordinator)
        updateAccessibility(for: canvasView)
        DispatchQueue.main.async { [weak canvasView, weak coordinator] in
            guard let canvasView, let coordinator else { return }
            coordinator.focusPlannerRegionIfNeeded(in: canvasView)
            applyInitialPlannerViewport(to: canvasView, coordinator: coordinator)
            coordinator.reportViewport(canvasView)
        }
        apply(configuration, to: canvasView, coordinator: context.coordinator)
        apply(navigationCommand, to: canvasView, coordinator: context.coordinator)
        apply(editingCommand, to: canvasView, coordinator: context.coordinator)
        updateInlineTextEditor(in: canvasView, coordinator: context.coordinator)
        bringCanvasOverlaysToFront(in: canvasView, coordinator: context.coordinator)
        canvasView.drawingPolicy = isFingerDrawingEnabled ? .anyInput : .pencilOnly
        canvasView.drawingGestureRecognizer.isEnabled = isDrawingGestureEnabled
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        let shouldRedraw = PencilCanvasModelReconciliation.requiresRedraw(
            current: context.coordinator.canonicalStrokes,
            incoming: strokes,
            isUsingTool: context.coordinator.isUsingTool
        )
        context.coordinator.configuration = configuration
        context.coordinator.activeLayerID = activeLayerID
        context.coordinator.canonicalStrokes = strokes
        updatePlannerContext(context.coordinator)
        context.coordinator.configurePlannerSwipeRecognizers(
            touchCount: isFingerDrawingEnabled ? 2 : 1
        )
        canvasView.drawingPolicy = isFingerDrawingEnabled ? .anyInput : .pencilOnly
        canvasView.drawingGestureRecognizer.isEnabled = isDrawingGestureEnabled
        if context.coordinator.paperType != template {
            applyPaper(to: canvasView, coordinator: context.coordinator)
        }
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak canvasView, weak coordinator] in
            guard let canvasView, let coordinator else { return }
            coordinator.focusPlannerRegionIfNeeded(in: canvasView)
            applyInitialPlannerViewport(to: canvasView, coordinator: coordinator)
        }
        updateObjectOverlays(in: canvasView, coordinator: context.coordinator)
        updateInlineTextEditor(in: canvasView, coordinator: context.coordinator)
        bringCanvasOverlaysToFront(in: canvasView, coordinator: context.coordinator)
        updateAccessibility(for: canvasView)
        apply(configuration, to: canvasView, coordinator: context.coordinator)
        if shouldRedraw {
            context.coordinator.isApplyingModelDrawing = true
            canvasView.drawing = PencilCanvasRenderer.drawing(from: strokes)
            context.coordinator.knownStrokeCount = strokes.count
            context.coordinator.isApplyingModelDrawing = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
        var knownStrokeCount = 0
        var canonicalStrokes: [Stroke] = []
        var isApplyingModelDrawing = false
        var lastNavigationCommandID: UUID?
        var lastEditingCommandID: UUID?
        weak var objectSelectionOverlay: CanvasSelectionOverlayView?
        weak var inlineTextEditor: InlineCanvasTextEditor?
        var overlayStrokes: [Stroke] = []
        var overlayObjects: [CanvasObject] = []
        var overlayAssets: [AssetID: Data] = [:]
        var highlightedStrokeIDs: Set<StrokeID> = []
        var isLassoOverlayEnabled = false
        var isTextPlacementOverlayEnabled = false
        var shapePlacementKind: RecognizedShapeKind?
        var configuration = ToolConfiguration.favoriteOne
        var activeDrawingConfiguration: ToolConfiguration?
        var activeLayerID: LayerID
        var isUsingTool = false
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
        weak var previousRegionSwipeRecognizer: UISwipeGestureRecognizer?
        weak var nextRegionSwipeRecognizer: UISwipeGestureRecognizer?
        private let onStrokesCompleted: @MainActor ([Stroke]) -> Void
        private let onDrawingChanged: @MainActor ([Stroke]) -> Void
        private let onConvertStrokesToText: @MainActor ([Stroke]) -> Void
        private let onViewportChanged: @MainActor (CanvasRect) -> Void
        private let onPencilSqueeze: @MainActor (PencilSqueezeResponse, CGPoint?) -> Void
        private let onPencilDoubleTap: @MainActor () -> Void
        let onPlannerRegionPageRequested: @MainActor (Int) -> Void

        init(
            activeLayerID: LayerID,
            onStrokesCompleted: @escaping @MainActor ([Stroke]) -> Void,
            onDrawingChanged: @escaping @MainActor ([Stroke]) -> Void,
            onConvertStrokesToText: @escaping @MainActor ([Stroke]) -> Void,
            onViewportChanged: @escaping @MainActor (CanvasRect) -> Void,
            onPencilSqueeze: @escaping @MainActor (PencilSqueezeResponse, CGPoint?) -> Void,
            onPencilDoubleTap: @escaping @MainActor () -> Void,
            onPlannerRegionPageRequested: @escaping @MainActor (Int) -> Void
        ) {
            self.activeLayerID = activeLayerID
            self.onStrokesCompleted = onStrokesCompleted
            self.onDrawingChanged = onDrawingChanged
            self.onConvertStrokesToText = onConvertStrokesToText
            self.onViewportChanged = onViewportChanged
            self.onPencilSqueeze = onPencilSqueeze
            self.onPencilDoubleTap = onPencilDoubleTap
            self.onPlannerRegionPageRequested = onPlannerRegionPageRequested
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingModelDrawing, !isUsingTool else { return }
            synchronizeDrawing(canvasView)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = true
            activeDrawingConfiguration = configuration
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = false
            synchronizeDrawing(canvasView)
            activeDrawingConfiguration = nil
        }

        private func synchronizeDrawing(_ canvasView: PKCanvasView) {
            guard !isApplyingModelDrawing else { return }
            guard canvasView.drawing.strokes.count > knownStrokeCount else {
                if canvasView.drawing.strokes.count <= knownStrokeCount {
                    let changedStrokes = reconciledCanonicalStrokes(
                        from: canvasView.drawing.strokes,
                        preserving: canonicalStrokes
                    )
                    knownStrokeCount = changedStrokes.count
                    canonicalStrokes = changedStrokes
                    onDrawingChanged(changedStrokes)
                    return
                }
                knownStrokeCount = canvasView.drawing.strokes.count
                return
            }
            let addedPencilStrokes = canvasView.drawing.strokes.dropFirst(knownStrokeCount)
            knownStrokeCount = canvasView.drawing.strokes.count
            let strokeConfiguration = activeDrawingConfiguration ?? configuration
            guard let instrument = strokeConfiguration.tool.instrument else { return }
            let addedStrokes = addedPencilStrokes.compactMap { pencilStroke -> Stroke? in
                let samples = pencilStroke.path.map { point in
                    canonicalSample(
                        from: point,
                        transformedBy: pencilStroke.transform,
                        roll: latestPencilRoll
                    )
                }
                guard !samples.isEmpty else { return nil }
                let stroke = Stroke(
                    id: StrokeID(),
                    layerID: activeLayerID,
                    samples: samples,
                    style: StrokeStyle(
                        instrument: instrument,
                        width: strokeConfiguration.width.points,
                        color: strokeConfiguration.color
                    ),
                    createdAt: Date(),
                    pencilKitArchive: nil
                )
                return PencilKitStrokeArchiveCodec.preserving(pencilStroke, in: stroke)
            }
            canonicalStrokes.append(contentsOf: addedStrokes)
            onStrokesCompleted(addedStrokes)
        }

        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
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
            onPencilDoubleTap()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let canvasView = scrollView as? PKCanvasView else { return }
            focusPlannerRegionIfNeeded(in: canvasView)
            reportViewport(canvasView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let canvasView = scrollView as? PKCanvasView else { return }
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

    private func apply(_ configuration: ToolConfiguration, to canvasView: PKCanvasView, coordinator: Coordinator) {
        coordinator.configuration = configuration
        switch configuration.tool {
        case .eraser:
            canvasView.tool = configuration.eraserMode == .stroke
                ? PKEraserTool(.vector)
                : PKEraserTool(.bitmap, width: configuration.width.points * 4)
        case .lasso:
            canvasView.tool = PKLassoTool()
        default:
            canvasView.tool = PKInkingTool(
                configuration.tool.inkType,
                color: UIColor(configuration.color),
                width: configuration.width.points
            )
        }
    }

    private var isDrawingGestureEnabled: Bool {
        !isTextToolActive && shapePlacementKind == nil && configuration.tool != .lasso
    }

    private func apply(
        _ command: CanvasNavigationCommand?,
        to canvasView: PKCanvasView,
        coordinator: Coordinator
    ) {
        guard let command, coordinator.lastNavigationCommandID != command.id else { return }
        coordinator.lastNavigationCommandID = command.id
        switch command.action {
        case .home:
            canvasView.setZoomScale(1, animated: true)
            canvasView.setContentOffset(CGPoint(x: 9_500, y: 9_500), animated: true)
        case let .zoomToContent(bounds):
            let margin = max(bounds.size.width, bounds.size.height) * 0.08 + 40
            canvasView.zoom(to: bounds.pencilKitRect.insetBy(dx: -margin, dy: -margin), animated: true)
        }
    }

    private func apply(
        _ command: CanvasEditingCommand?,
        to canvasView: PKCanvasView,
        coordinator: Coordinator
    ) {
        guard let command, coordinator.lastEditingCommandID != command.id else { return }
        coordinator.lastEditingCommandID = command.id
        if performObjectEditing(command.action, coordinator: coordinator) { return }
        switch command.action {
        case .copy: canvasView.copy(nil)
        case .cut: canvasView.cut(nil)
        case .paste: performPaste(on: canvasView, coordinator: coordinator)
        case .selectAll:
            coordinator.objectSelectionOverlay?.selectAllObjects()
            canvasView.selectAll(nil)
        case .delete: canvasView.delete(nil)
        case .convertToText: coordinator.convertSelectedStrokesToText(in: canvasView)
        case .duplicate: coordinator.objectSelectionOverlay?.duplicateSelection()
        case let .moveToLayer(layerID): coordinator.objectSelectionOverlay?.moveSelection(to: layerID)
        }
    }

    private func performObjectEditing(
        _ action: CanvasEditingAction,
        coordinator: Coordinator
    ) -> Bool {
        guard let overlay = coordinator.objectSelectionOverlay, overlay.hasSelection else { return false }
        switch action {
        case .copy: overlay.copySelection()
        case .cut: overlay.cutSelection()
        case .delete: overlay.deleteSelection()
        case .duplicate: overlay.duplicateSelection()
        case let .moveToLayer(layerID): overlay.moveSelection(to: layerID)
        case .paste, .selectAll, .convertToText: return false
        }
        return true
    }

    private func performPaste(on canvasView: PKCanvasView, coordinator: Coordinator) {
        if UIPasteboard.general.data(forPasteboardType: "com.strategicnerds.notenerds.selection") != nil {
            coordinator.objectSelectionOverlay?.pasteSelection()
        } else {
            canvasView.paste(nil)
        }
    }

}

extension PencilCanvasView.Coordinator {
    func applySelectionTransform(
        objectIDs: Set<ObjectID>,
        transform: SelectionTransform,
        center: CanvasPoint,
        in canvasView: PKCanvasView
    ) -> [Stroke] {
        let result = PencilCanvasSelectionTransform.applying(
            objectIDs: objectIDs,
            transform: transform,
            center: center,
            to: canvasView.drawing,
            canonicalStrokes: canonicalStrokes
        )
        isApplyingModelDrawing = true
        canvasView.drawing = result.drawing
        canonicalStrokes = result.canonicalStrokes
        knownStrokeCount = result.canonicalStrokes.count
        isApplyingModelDrawing = false
        return result.canonicalStrokes.filter { objectIDs.contains($0.objectID) }
    }
}

private extension CGPoint {
    var canvasPoint: CanvasPoint { CanvasPoint(x: x, y: y) }
}

private extension PencilCanvasView {
    func updateAccessibility(for canvasView: PKCanvasView) {
        let text = nonStrokeObjects.compactMap { object -> String? in
            switch object {
            case let .text(text): text.text
            case let .pdf(pdf): pdf.embeddedText
            case .stroke, .shape, .image: nil
            }
        }
        canvasView.isAccessibilityElement = true
        canvasView.accessibilityLabel = "Infinite canvas"
        var parts = [
            "Paper: \(template.displayName)",
            "\(strokes.count) ink strokes",
            "\(nonStrokeObjects.count) other objects"
        ]
        if !text.isEmpty { parts.append("Text: \(text.joined(separator: ", "))") }
        if !recognizedText.isEmpty {
            parts.append("Recognized handwriting: \(recognizedText.joined(separator: ", "))")
        }
        canvasView.accessibilityValue = parts.joined(separator: ". ")
        canvasView.accessibilityHint = "Draw with Apple Pencil. Pan and zoom with touch."
    }
}
