import SwiftUI

enum NotebookCanvasOpeningPolicy {
    static func initialIndex(
        canvasIDs: [CanvasID],
        pendingCanvasID: CanvasID?,
        storedCanvasID: CanvasID?
    ) -> Int {
        if let pendingCanvasID,
           let index = canvasIDs.firstIndex(of: pendingCanvasID) {
            return index
        }
        if let storedCanvasID,
           let index = canvasIDs.firstIndex(of: storedCanvasID) {
            return index
        }
        return 0
    }
}

extension NotebookEditorView {
    var plannerRegions: [CanvasRegion] {
        plannerRegions(for: currentCanvas.id)
    }

    var selectedPlannerRegionIndex: Int {
        selectedPlannerRegionIndex(for: currentCanvas.id)
    }

    var selectedPlannerRegion: CanvasRegion? {
        selectedPlannerRegion(for: currentCanvas.id)
    }

    var isPlannerRegionPagingPresented: Bool {
        isPlannerRegionPagingPresented(for: currentCanvas.id)
    }

    var allowsFingerDrawingOnCanvas: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-disable-simulator-finger-drawing") { return false }
        #endif
        return DrawingInputPolicy.allowsFingerDrawingForCurrentBuild(userPreference: isFingerDrawingEnabled)
    }

    func selectPlannerRegion(_ index: Int) {
        guard plannerRegions.indices.contains(index) else { return }
        plannerRegionSelection.select(regionID: plannerRegions[index].id, for: currentCanvas.id)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func plannerContentRegion(at point: CanvasPoint) -> CanvasRegion? {
        plannerContentRegion(at: point, canvasID: currentCanvas.id)
    }

    func constrainStrokesToPlannerRegions(_ strokes: [Stroke]) -> [Stroke] {
        constrainStrokesToPlannerRegions(strokes, canvasID: currentCanvas.id)
    }

    func constrainStrokesToPlannerRegions(
        _ strokes: [Stroke],
        canvasID: CanvasID
    ) -> [Stroke] {
        strokes.map { stroke in
            guard let firstPoint = stroke.samples.first?.point else { return stroke }
            return PlannerRegionContentPolicy.constrainedStroke(
                stroke,
                to: plannerContentRegion(at: firstPoint, canvasID: canvasID)?.frame
            )
        }
    }

    func constrainTextBlockToPlannerRegion(_ textBlock: TextBlock) -> TextBlock {
        var constrained = textBlock
        let region = plannerContentRegion(at: textBlock.frame.origin)
        constrained.frame = PlannerRegionContentPolicy.constrainedFrame(textBlock.frame, to: region?.frame)
        return constrained
    }

    private func plannerRegions(for canvasID: CanvasID) -> [CanvasRegion] {
        guard let canvas = notebook.canvases.first(where: { $0.id == canvasID }) else { return [] }
        return PlannerRegionCatalog.regions(for: canvas.template)
    }

    private func selectedPlannerRegionIndex(for canvasID: CanvasID) -> Int {
        plannerRegionSelection.selectedIndex(for: canvasID, in: plannerRegions(for: canvasID))
    }

    private func selectedPlannerRegion(for canvasID: CanvasID) -> CanvasRegion? {
        let regions = plannerRegions(for: canvasID)
        let selectedIndex = selectedPlannerRegionIndex(for: canvasID)
        guard regions.indices.contains(selectedIndex) else { return nil }
        return regions[selectedIndex]
    }

    private func isPlannerRegionPagingPresented(for canvasID: CanvasID) -> Bool {
        guard !plannerRegions(for: canvasID).isEmpty else { return false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-force-phone-planner-pager") { return true }
        #endif
        return UIDevice.current.userInterfaceIdiom == .phone
    }

    private func plannerContentRegion(
        at point: CanvasPoint,
        canvasID: CanvasID
    ) -> CanvasRegion? {
        if isPlannerRegionPagingPresented(for: canvasID) {
            return selectedPlannerRegion(for: canvasID)
        }
        return PlannerRegionContentPolicy.region(
            containing: point,
            in: plannerRegions(for: canvasID)
        )
    }
}
