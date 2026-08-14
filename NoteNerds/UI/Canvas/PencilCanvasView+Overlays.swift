import PencilKit
import UIKit

enum CanvasOverlayPresentation {
    static func requiresSelectionOverlay(
        strokeCount: Int,
        nonStrokeObjectCount: Int,
        isLassoEnabled: Bool,
        isShapePlacementEnabled: Bool
    ) -> Bool {
        nonStrokeObjectCount > 0
            || isShapePlacementEnabled
            || (isLassoEnabled && strokeCount > 0)
    }
}

/// Keeps the canvas overlays sitting exactly on top of the ink.
///
/// PencilKit zooms its own drawing view, and our overlays are siblings of it
/// rather than children, so they keep their unzoomed size unless we scale them
/// ourselves. Anchoring each one to the content origin and scaling it by the
/// zoom leaves overlay coordinates equal to canvas coordinates at every zoom,
/// which is what lasso selection, hit testing, and drag distances all read.
@MainActor
enum CanvasOverlayGeometry {
    static let tags = 8_417...8_420

    static func pinToContentOrigin(_ overlay: UIView) {
        overlay.layer.anchorPoint = .zero
        overlay.layer.position = .zero
    }

    static func synchronizeZoom(in canvasView: PKCanvasView) {
        let scale = max(canvasView.zoomScale, CGFloat(CanvasViewport.minimumZoom))
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        for tag in tags {
            guard let overlay = canvasView.viewWithTag(tag), overlay.transform != transform else { continue }
            overlay.transform = transform
        }
    }

    /// The content size with any zoom taken back out, which is the coordinate
    /// space strokes are stored in.
    static func unzoomedContentSize(of canvasView: PKCanvasView) -> CGSize {
        let scale = max(canvasView.zoomScale, CGFloat(CanvasViewport.minimumZoom))
        return CGSize(
            width: canvasView.contentSize.width / scale,
            height: canvasView.contentSize.height / scale
        )
    }
}

enum CanvasOverlayModelReconciliation {
    static func requiresRefresh(
        currentStrokes: [Stroke],
        incomingStrokes: [Stroke],
        isLassoEnabled: Bool
    ) -> Bool {
        isLassoEnabled && currentStrokes != incomingStrokes
    }
}

extension PencilCanvasView {
    func bringCanvasOverlaysToFront(in canvasView: PKCanvasView, coordinator: Coordinator) {
        for tag in CanvasOverlayGeometry.tags {
            if let overlay = canvasView.viewWithTag(tag) {
                canvasView.bringSubviewToFront(overlay)
            }
        }
        if let editor = coordinator.inlineTextEditor {
            canvasView.bringSubviewToFront(editor)
        }
    }

    func updateObjectOverlays(in canvasView: PKCanvasView, coordinator: Coordinator) {
        guard CanvasOverlayModelReconciliation.requiresRefresh(
                currentStrokes: coordinator.overlayStrokes,
                incomingStrokes: strokes,
                isLassoEnabled: configuration.tool == .lasso
              )
                || coordinator.overlayObjects != nonStrokeObjects
                || coordinator.overlayAssets != assets
                || coordinator.highlightedStrokeIDs != highlightedStrokeIDs
                || coordinator.isLassoOverlayEnabled != (configuration.tool == .lasso)
                || coordinator.isTextPlacementOverlayEnabled != isTextToolActive
                || coordinator.shapePlacementKind != shapePlacementKind else { return }
        coordinator.overlayStrokes = strokes
        coordinator.overlayObjects = nonStrokeObjects
        coordinator.overlayAssets = assets
        coordinator.highlightedStrokeIDs = highlightedStrokeIDs
        coordinator.isLassoOverlayEnabled = configuration.tool == .lasso
        coordinator.isTextPlacementOverlayEnabled = isTextToolActive
        coordinator.shapePlacementKind = shapePlacementKind
        let contentOverlayTag = CanvasOverlayGeometry.tags.lowerBound
        let selectionOverlayTag = contentOverlayTag + 1
        let highlightOverlayTag = contentOverlayTag + 2
        let textPlacementOverlayTag = contentOverlayTag + 3
        canvasView.viewWithTag(contentOverlayTag)?.removeFromSuperview()
        canvasView.viewWithTag(selectionOverlayTag)?.removeFromSuperview()
        canvasView.viewWithTag(highlightOverlayTag)?.removeFromSuperview()
        canvasView.viewWithTag(textPlacementOverlayTag)?.removeFromSuperview()
        if CanvasOverlayPresentation.requiresSelectionOverlay(
            strokeCount: strokes.count,
            nonStrokeObjectCount: nonStrokeObjects.count,
            isLassoEnabled: configuration.tool == .lasso,
            isShapePlacementEnabled: shapePlacementKind != nil
        ) {
            addObjectOverlays(
                to: canvasView,
                coordinator: coordinator,
                contentTag: contentOverlayTag,
                selectionTag: selectionOverlayTag
            )
        }
        addSearchHighlights(to: canvasView, tag: highlightOverlayTag)
        addTextPlacementOverlay(to: canvasView, tag: textPlacementOverlayTag)
        CanvasOverlayGeometry.synchronizeZoom(in: canvasView)
    }

    private func addSearchHighlights(to canvasView: PKCanvasView, tag: Int) {
        let highlightedStrokes = strokes.filter { highlightedStrokeIDs.contains($0.id) }
        guard !highlightedStrokes.isEmpty else { return }
        let highlightOverlay = CanvasSearchHighlightView(
            frame: CGRect(origin: .zero, size: CanvasOverlayGeometry.unzoomedContentSize(of: canvasView)),
            strokes: highlightedStrokes
        )
        highlightOverlay.tag = tag
        highlightOverlay.isUserInteractionEnabled = false
        canvasView.addSubview(highlightOverlay)
        CanvasOverlayGeometry.pinToContentOrigin(highlightOverlay)
    }

    private func addTextPlacementOverlay(to canvasView: PKCanvasView, tag: Int) {
        guard isTextToolActive else { return }
        let placementOverlay = CanvasTextPlacementOverlayView(
            frame: CGRect(origin: .zero, size: CanvasOverlayGeometry.unzoomedContentSize(of: canvasView)),
            objects: nonStrokeObjects,
            onPlaceText: onPlaceText,
            onEditText: onEditText
        )
        placementOverlay.tag = tag
        canvasView.addSubview(placementOverlay)
        CanvasOverlayGeometry.pinToContentOrigin(placementOverlay)
    }

    private func addObjectOverlays(
        to canvasView: PKCanvasView,
        coordinator: Coordinator,
        contentTag: Int,
        selectionTag: Int
    ) {
        let contentOverlay = CanvasObjectOverlayView(
            frame: CGRect(origin: .zero, size: CanvasOverlayGeometry.unzoomedContentSize(of: canvasView)),
            objects: nonStrokeObjects,
            assets: assets
        )
        contentOverlay.tag = contentTag
        contentOverlay.isUserInteractionEnabled = false
        contentOverlay.backgroundColor = .clear
        canvasView.addSubview(contentOverlay)
        CanvasOverlayGeometry.pinToContentOrigin(contentOverlay)

        let selectionOverlay = CanvasSelectionOverlayView(
            frame: CGRect(origin: .zero, size: CanvasOverlayGeometry.unzoomedContentSize(of: canvasView)),
            objects: configuration.tool == .lasso
                ? strokes.map(CanvasObject.stroke) + nonStrokeObjects
                : nonStrokeObjects,
            isLassoEnabled: configuration.tool == .lasso,
            onTransform: { objectIDs, transform, center in
                let transformedStrokes = coordinator.applySelectionTransform(
                    objectIDs: objectIDs,
                    transform: transform,
                    center: center,
                    in: canvasView
                )
                onTransformObjects(objectIDs, transform, center, transformedStrokes)
            },
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
        CanvasOverlayGeometry.pinToContentOrigin(selectionOverlay)
        coordinator.objectSelectionOverlay = selectionOverlay
    }
}
