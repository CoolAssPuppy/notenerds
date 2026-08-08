import PencilKit
import UIKit

extension PencilCanvasView {
    func bringCanvasOverlaysToFront(in canvasView: PKCanvasView, coordinator: Coordinator) {
        for tag in 8_417...8_420 {
            if let overlay = canvasView.viewWithTag(tag) {
                canvasView.bringSubviewToFront(overlay)
            }
        }
        if let editor = coordinator.inlineTextEditor {
            canvasView.bringSubviewToFront(editor)
        }
        if let hoverPreview = coordinator.hoverPreview {
            canvasView.bringSubviewToFront(hoverPreview)
        }
    }

    func updateObjectOverlays(in canvasView: PKCanvasView, coordinator: Coordinator) {
        guard coordinator.overlayObjects != nonStrokeObjects
                || coordinator.overlayAssets != assets
                || coordinator.highlightedStrokeIDs != highlightedStrokeIDs
                || coordinator.isLassoOverlayEnabled != (configuration.tool == .lasso)
                || coordinator.isTextPlacementOverlayEnabled != isTextToolActive
                || coordinator.shapePlacementKind != shapePlacementKind else { return }
        coordinator.overlayObjects = nonStrokeObjects
        coordinator.overlayAssets = assets
        coordinator.highlightedStrokeIDs = highlightedStrokeIDs
        coordinator.isLassoOverlayEnabled = configuration.tool == .lasso
        coordinator.isTextPlacementOverlayEnabled = isTextToolActive
        coordinator.shapePlacementKind = shapePlacementKind
        let contentOverlayTag = 8_417
        let selectionOverlayTag = 8_418
        let highlightOverlayTag = 8_419
        let textPlacementOverlayTag = 8_420
        canvasView.viewWithTag(contentOverlayTag)?.removeFromSuperview()
        canvasView.viewWithTag(selectionOverlayTag)?.removeFromSuperview()
        canvasView.viewWithTag(highlightOverlayTag)?.removeFromSuperview()
        canvasView.viewWithTag(textPlacementOverlayTag)?.removeFromSuperview()
        if !nonStrokeObjects.isEmpty || shapePlacementKind != nil {
            addObjectOverlays(
                to: canvasView,
                coordinator: coordinator,
                contentTag: contentOverlayTag,
                selectionTag: selectionOverlayTag
            )
        }
        addSearchHighlights(to: canvasView, tag: highlightOverlayTag)
        addTextPlacementOverlay(to: canvasView, tag: textPlacementOverlayTag)
    }

    private func addSearchHighlights(to canvasView: PKCanvasView, tag: Int) {
        let highlightedStrokes = strokes.filter { highlightedStrokeIDs.contains($0.id) }
        guard !highlightedStrokes.isEmpty else { return }
        let highlightOverlay = CanvasSearchHighlightView(
            frame: CGRect(origin: .zero, size: canvasView.contentSize),
            strokes: highlightedStrokes
        )
        highlightOverlay.tag = tag
        highlightOverlay.isUserInteractionEnabled = false
        canvasView.addSubview(highlightOverlay)
    }

    private func addTextPlacementOverlay(to canvasView: PKCanvasView, tag: Int) {
        guard isTextToolActive else { return }
        let placementOverlay = CanvasTextPlacementOverlayView(
            frame: CGRect(origin: .zero, size: canvasView.contentSize),
            objects: nonStrokeObjects,
            onPlaceText: onPlaceText,
            onEditText: onEditText
        )
        placementOverlay.tag = tag
        canvasView.addSubview(placementOverlay)
    }

    private func addObjectOverlays(
        to canvasView: PKCanvasView,
        coordinator: Coordinator,
        contentTag: Int,
        selectionTag: Int
    ) {
        let contentOverlay = CanvasObjectOverlayView(
            frame: CGRect(origin: .zero, size: canvasView.contentSize),
            objects: nonStrokeObjects,
            assets: assets
        )
        contentOverlay.tag = contentTag
        contentOverlay.isUserInteractionEnabled = false
        contentOverlay.backgroundColor = .clear
        canvasView.addSubview(contentOverlay)

        let selectionOverlay = CanvasSelectionOverlayView(
            frame: CGRect(origin: .zero, size: canvasView.contentSize),
            objects: configuration.tool == .lasso
                ? strokes.map(CanvasObject.stroke) + nonStrokeObjects
                : nonStrokeObjects,
            isLassoEnabled: configuration.tool == .lasso,
            onTransform: onTransformObjects,
            onDelete: onDeleteObjects,
            onPaste: onPasteObjects,
            onMoveToLayer: onMoveObjectsToLayer,
            onEditText: onEditText,
            shapePlacementKind: shapePlacementKind,
            onPlaceShape: onPlaceShape,
            onSelectionChanged: onObjectSelectionChanged
        )
        selectionOverlay.tag = selectionTag
        canvasView.addSubview(selectionOverlay)
        coordinator.objectSelectionOverlay = selectionOverlay
    }
}
