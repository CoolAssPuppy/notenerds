import PencilKit
import SwiftUI

struct PencilCanvasView: UIViewRepresentable {
    @EnvironmentObject private var snapshotFlusher: PencilCanvasSnapshotFlusher

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
    let isCanvasLocked: Bool
    let textEditingSession: CanvasTextEditingSession?
    let isTextToolActive: Bool
    let shapePlacementKind: RecognizedShapeKind?
    let actions: PencilCanvasActions

    func makeCoordinator() -> Coordinator {
        Coordinator(activeLayerID: activeLayerID, actions: actions)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        let coordinator = context.coordinator
        coordinator.attachSnapshotFlusher(snapshotFlusher, canvasView: canvasView)
        PencilCanvasInputAccessories.install(on: canvasView, coordinator: coordinator)
        Self.configureViewport(canvasView)
        updatePlannerContext(context.coordinator)
        applyPaper(to: canvasView, coordinator: context.coordinator)
        canvasView.isOpaque = true
        canvasView.alwaysBounceHorizontal = true
        canvasView.alwaysBounceVertical = true
        context.coordinator.isApplyingModelDrawing = true
        canvasView.drawing = PencilCanvasRenderer.drawing(from: strokes)
        context.coordinator.knownStrokeCount = strokes.count
        context.coordinator.canonicalStrokes = strokes
        context.coordinator.committedNativeDrawing = canvasView.drawing
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
        applyInputPolicy(to: canvasView)
        Self.applyCanvasLock(isCanvasLocked, to: canvasView)
        canvasView.delegate = context.coordinator
        return canvasView
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.prepareForDismantle(uiView)
        uiView.delegate = nil
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        CanvasDiagnostics.measure("updateUIView strokes=\(strokes.count)") {
            performUpdate(canvasView, context: context)
        }
    }

    private func performUpdate(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.attachSnapshotFlusher(snapshotFlusher, canvasView: canvasView)
        context.coordinator.updateHandlers(from: self)
        let shouldRedraw = PencilCanvasModelReconciliation.requiresRedraw(
            current: context.coordinator.canonicalStrokes,
            incoming: strokes,
            isUsingTool: context.coordinator.isProtectingNativeDrawing
        )
        context.coordinator.configuration = configuration
        context.coordinator.activeLayerID = activeLayerID
        context.coordinator.receiveModelStrokes(strokes)
        updatePlannerContext(context.coordinator)
        applyInputPolicy(to: canvasView)
        Self.applyCanvasLock(isCanvasLocked, to: canvasView)
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
            let drawing = PencilCanvasRenderer.drawing(from: strokes)
            context.coordinator.isApplyingModelDrawing = true
            context.coordinator.tagAppliedModelDrawing(drawing)
            canvasView.drawing = drawing
            context.coordinator.knownStrokeCount = strokes.count
            context.coordinator.isApplyingModelDrawing = false
        }
    }

    /// Assigns the drawing tool only when it actually changes, and never during
    /// a live contact.
    ///
    /// `updateUIView` runs on every model change, and assigning
    /// `PKCanvasView.tool` interrupts a stroke that is still being drawn. A
    /// Pencil squeeze or double tap can change tools while the tip is down, so
    /// the new tool waits for the contact to end.
    private func apply(_ configuration: ToolConfiguration, to canvasView: PKCanvasView, coordinator: Coordinator) {
        coordinator.configuration = configuration
        coordinator.applyToolIfNeeded(to: canvasView)
    }

    static func tool(for configuration: ToolConfiguration) -> PKTool {
        switch configuration.tool {
        case .eraser:
            return configuration.eraserMode == .stroke
                ? PKEraserTool(.vector)
                : PKEraserTool(.bitmap, width: configuration.width.points * 4)
        case .lasso:
            return PKLassoTool()
        default:
            return PKInkingTool(
                configuration.tool.inkType,
                color: UIColor(configuration.color),
                width: configuration.width.points
            )
        }
    }

    private var isDrawingGestureEnabled: Bool {
        !isTextToolActive && shapePlacementKind == nil && configuration.tool != .lasso
    }

    /// Writes the input policy only on a real change. Reassigning either value
    /// can cancel touches that PencilKit is already tracking.
    private func applyInputPolicy(to canvasView: PKCanvasView) {
        let policy: PKCanvasViewDrawingPolicy = isFingerDrawingEnabled ? .anyInput : .pencilOnly
        if canvasView.drawingPolicy != policy {
            canvasView.drawingPolicy = policy
        }
        if canvasView.drawingGestureRecognizer.isEnabled != isDrawingGestureEnabled {
            canvasView.drawingGestureRecognizer.isEnabled = isDrawingGestureEnabled
        }
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
            canvasView.setContentOffset(
                CGPoint(x: CanvasViewport.homeOrigin.x, y: CanvasViewport.homeOrigin.y),
                animated: true
            )
        case let .zoomToContent(bounds):
            canvasView.zoom(to: Self.zoomRect(for: bounds), animated: true)
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
        tagAppliedModelDrawing(result.drawing)
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
