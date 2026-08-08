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
    let template: CanvasTemplate
    let isFingerDrawingEnabled: Bool
    let textEditingSession: CanvasTextEditingSession?
    let isTextToolActive: Bool
    let onStrokesCompleted: @MainActor ([Stroke]) -> Void
    let onDrawingChanged: @MainActor ([Stroke]) -> Void
    let onConvertStrokesToText: @MainActor ([Stroke]) -> Void
    let onTransformObjects: @MainActor (Set<ObjectID>, SelectionTransform, CanvasPoint) -> Void
    let onDeleteObjects: @MainActor (Set<ObjectID>) -> Void
    let onPasteObjects: @MainActor ([CanvasObject]) -> Void
    let onMoveObjectsToLayer: @MainActor (Set<ObjectID>, LayerID) -> Void
    let onEditText: @MainActor (TextBlock) -> Void
    let onPlaceText: @MainActor (CanvasPoint) -> Void
    let onCommitText: @MainActor (TextBlock) -> Void
    let onCancelText: @MainActor () -> Void
    let onObjectSelectionChanged: @MainActor (Bool) -> Void
    let onViewportChanged: @MainActor (CanvasRect) -> Void
    let onPencilSqueeze: @MainActor (CGPoint?) -> Void
    let onPencilDoubleTap: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onStrokesCompleted: onStrokesCompleted,
            onDrawingChanged: onDrawingChanged,
            onConvertStrokesToText: onConvertStrokesToText,
            onViewportChanged: onViewportChanged,
            onPencilSqueeze: onPencilSqueeze,
            onPencilDoubleTap: onPencilDoubleTap
        )
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvasView.addInteraction(pencilInteraction)
        let hoverRecognizer = UIHoverGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePencilHover(_:))
        )
        hoverRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        canvasView.addGestureRecognizer(hoverRecognizer)
        let hoverPreview = UIView()
        hoverPreview.isHidden = true
        hoverPreview.isUserInteractionEnabled = false
        hoverPreview.backgroundColor = UIColor.label.withAlphaComponent(0.08)
        hoverPreview.layer.borderColor = UIColor.label.withAlphaComponent(0.45).cgColor
        hoverPreview.layer.borderWidth = 1
        canvasView.addSubview(hoverPreview)
        context.coordinator.hoverPreview = hoverPreview
        canvasView.minimumZoomScale = CanvasViewport.minimumZoom
        canvasView.maximumZoomScale = CanvasViewport.maximumZoom
        canvasView.contentSize = CGSize(width: 20_000, height: 20_000)
        canvasView.contentOffset = CGPoint(x: 9_500, y: 9_500)
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
        context.coordinator.reportViewport(canvasView)
        apply(configuration, to: canvasView, coordinator: context.coordinator)
        apply(navigationCommand, to: canvasView, coordinator: context.coordinator)
        apply(editingCommand, to: canvasView, coordinator: context.coordinator)
        updateInlineTextEditor(in: canvasView, coordinator: context.coordinator)
        canvasView.drawingPolicy = isFingerDrawingEnabled ? .anyInput : .pencilOnly
        canvasView.drawingGestureRecognizer.isEnabled = !isTextToolActive
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        context.coordinator.configuration = configuration
        context.coordinator.canonicalStrokes = strokes
        canvasView.drawingPolicy = isFingerDrawingEnabled ? .anyInput : .pencilOnly
        canvasView.drawingGestureRecognizer.isEnabled = !isTextToolActive
        if context.coordinator.paperType != template {
            applyPaper(to: canvasView, coordinator: context.coordinator)
        }
        updateObjectOverlays(in: canvasView, coordinator: context.coordinator)
        updateInlineTextEditor(in: canvasView, coordinator: context.coordinator)
        updateAccessibility(for: canvasView)
        apply(configuration, to: canvasView, coordinator: context.coordinator)
        if strokes.count != context.coordinator.knownStrokeCount {
            context.coordinator.isApplyingModelDrawing = true
            canvasView.drawing = PencilCanvasRenderer.drawing(from: strokes)
            context.coordinator.knownStrokeCount = strokes.count
            context.coordinator.isApplyingModelDrawing = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var knownStrokeCount = 0
        var canonicalStrokes: [Stroke] = []
        var isApplyingModelDrawing = false
        var lastNavigationCommandID: UUID?
        var lastEditingCommandID: UUID?
        weak var objectSelectionOverlay: CanvasSelectionOverlayView?
        weak var hoverPreview: UIView?
        weak var inlineTextEditor: InlineCanvasTextEditor?
        var overlayObjects: [CanvasObject] = []
        var overlayAssets: [AssetID: Data] = [:]
        var highlightedStrokeIDs: Set<StrokeID> = []
        var isLassoOverlayEnabled = false
        var isTextPlacementOverlayEnabled = false
        var configuration = ToolConfiguration.favoriteOne
        var latestPencilRoll = 0.0
        var paperType: PaperType?
        private let onStrokesCompleted: @MainActor ([Stroke]) -> Void
        private let onDrawingChanged: @MainActor ([Stroke]) -> Void
        private let onConvertStrokesToText: @MainActor ([Stroke]) -> Void
        private let onViewportChanged: @MainActor (CanvasRect) -> Void
        private let onPencilSqueeze: @MainActor (CGPoint?) -> Void
        private let onPencilDoubleTap: @MainActor () -> Void

        init(
            onStrokesCompleted: @escaping @MainActor ([Stroke]) -> Void,
            onDrawingChanged: @escaping @MainActor ([Stroke]) -> Void,
            onConvertStrokesToText: @escaping @MainActor ([Stroke]) -> Void,
            onViewportChanged: @escaping @MainActor (CanvasRect) -> Void,
            onPencilSqueeze: @escaping @MainActor (CGPoint?) -> Void,
            onPencilDoubleTap: @escaping @MainActor () -> Void
        ) {
            self.onStrokesCompleted = onStrokesCompleted
            self.onDrawingChanged = onDrawingChanged
            self.onConvertStrokesToText = onConvertStrokesToText
            self.onViewportChanged = onViewportChanged
            self.onPencilSqueeze = onPencilSqueeze
            self.onPencilDoubleTap = onPencilDoubleTap
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingModelDrawing else { return }
            guard canvasView.drawing.strokes.count > knownStrokeCount else {
                if canvasView.drawing.strokes.count <= knownStrokeCount {
                    var changedStrokes: [Stroke] = []
                    for (index, pencilStroke) in canvasView.drawing.strokes.enumerated()
                    where canonicalStrokes.indices.contains(index) {
                        changedStrokes.append(
                            canonicalStroke(from: pencilStroke, preserving: canonicalStrokes[index])
                        )
                    }
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
            guard let instrument = configuration.tool.instrument else { return }
            let addedStrokes = addedPencilStrokes.compactMap { pencilStroke -> Stroke? in
                let samples = pencilStroke.path.map { point in
                    StrokeSample(
                        point: CanvasPoint(x: point.location.x, y: point.location.y),
                        pressure: point.force,
                        altitude: point.altitude,
                        azimuth: point.azimuth,
                        roll: latestPencilRoll,
                        timeOffset: point.timeOffset
                    )
                }
                guard !samples.isEmpty else { return nil }
                return Stroke(
                    id: StrokeID(),
                    layerID: LayerID(),
                    samples: samples,
                    style: StrokeStyle(
                        instrument: instrument,
                        width: configuration.width.points,
                        color: configuration.color
                    ),
                    createdAt: Date()
                )
            }
            onStrokesCompleted(addedStrokes)
        }

        private func canonicalStroke(from pencilStroke: PKStroke, preserving source: Stroke) -> Stroke {
            let points = Array(pencilStroke.path)
            let samples = points.enumerated().map { index, point in
                StrokeSample(
                    point: CanvasPoint(x: point.location.x, y: point.location.y),
                    pressure: point.force,
                    altitude: point.altitude,
                    azimuth: point.azimuth,
                    roll: source.samples.indices.contains(index) ? source.samples[index].roll : 0,
                    timeOffset: point.timeOffset
                )
            }
            return Stroke(
                id: source.id,
                layerID: source.layerID,
                samples: samples,
                style: source.style,
                createdAt: source.createdAt
            )
        }

        func pencilInteraction(
            _ interaction: UIPencilInteraction,
            didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
        ) {
            guard squeeze.phase == .began else { return }
            latestPencilRoll = squeeze.hoverPose.map { Double($0.rollAngle) } ?? latestPencilRoll
            UISelectionFeedbackGenerator().selectionChanged()
            onPencilSqueeze(squeeze.hoverPose?.location)
        }

        @objc func handlePencilHover(_ recognizer: UIHoverGestureRecognizer) {
            latestPencilRoll = Double(recognizer.rollAngle)
            guard let preview = hoverPreview else { return }
            switch recognizer.state {
            case .began, .changed:
                let diameter = configuration.tool == .eraser
                    ? max(18, configuration.width.points * 8)
                    : max(8, configuration.width.points * 4)
                let location = recognizer.location(in: recognizer.view)
                preview.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                preview.center = location
                preview.layer.cornerRadius = diameter / 2
                preview.transform = CGAffineTransform(rotationAngle: recognizer.rollAngle)
                preview.isHidden = false
            case .ended, .cancelled:
                preview.isHidden = true
            default:
                break
            }
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            onPencilDoubleTap()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let canvasView = scrollView as? PKCanvasView else { return }
            reportViewport(canvasView)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let canvasView = scrollView as? PKCanvasView else { return }
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

    private func applyPaper(to canvasView: PKCanvasView, coordinator: Coordinator) {
        let marginRuleTag = 8_421
        canvasView.backgroundColor = PencilCanvasRenderer.patternColor(for: template)
        canvasView.viewWithTag(marginRuleTag)?.removeFromSuperview()
        if let frame = PencilCanvasRenderer.marginRuleFrame(for: template, contentSize: canvasView.contentSize) {
            let marginRule = UIView(frame: frame)
            marginRule.tag = marginRuleTag
            marginRule.backgroundColor = PaperType.marginColor
            marginRule.isUserInteractionEnabled = false
            marginRule.isAccessibilityElement = false
            canvasView.addSubview(marginRule)
        }
        coordinator.paperType = template
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
        if UIPasteboard.general.data(forPasteboardType: "com.prashant.notenerds.selection") != nil {
            coordinator.objectSelectionOverlay?.pasteSelection()
        } else {
            canvasView.paste(nil)
        }
    }

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
        var parts = ["\(strokes.count) ink strokes", "\(nonStrokeObjects.count) other objects"]
        if !text.isEmpty { parts.append("Text: \(text.joined(separator: ", "))") }
        if !recognizedText.isEmpty {
            parts.append("Recognized handwriting: \(recognizedText.joined(separator: ", "))")
        }
        canvasView.accessibilityValue = parts.joined(separator: ". ")
        canvasView.accessibilityHint = "Draw with Apple Pencil. Pan and zoom with touch."
    }
}
