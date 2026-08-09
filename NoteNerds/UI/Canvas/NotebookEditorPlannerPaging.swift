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
        PlannerRegionCatalog.regions(for: currentCanvas.template)
    }

    var selectedPlannerRegionIndex: Int {
        plannerRegionSelection.selectedIndex(for: currentCanvas.id, in: plannerRegions)
    }

    var selectedPlannerRegion: CanvasRegion? {
        guard plannerRegions.indices.contains(selectedPlannerRegionIndex) else { return nil }
        return plannerRegions[selectedPlannerRegionIndex]
    }

    var isPlannerRegionPagingPresented: Bool {
        guard !plannerRegions.isEmpty else { return false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-force-phone-planner-pager") { return true }
        #endif
        return UIDevice.current.userInterfaceIdiom == .phone
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
        if isPlannerRegionPagingPresented { return selectedPlannerRegion }
        return PlannerRegionContentPolicy.region(containing: point, in: plannerRegions)
    }

    func constrainStrokesToPlannerRegions(_ strokes: [Stroke]) -> [Stroke] {
        strokes.map { stroke in
            guard let firstPoint = stroke.samples.first?.point else { return stroke }
            return PlannerRegionContentPolicy.constrainedStroke(
                stroke,
                to: plannerContentRegion(at: firstPoint)?.frame
            )
        }
    }

    func constrainTextBlockToPlannerRegion(_ textBlock: TextBlock) -> TextBlock {
        var constrained = textBlock
        let region = plannerContentRegion(at: textBlock.frame.origin)
        constrained.frame = PlannerRegionContentPolicy.constrainedFrame(textBlock.frame, to: region?.frame)
        return constrained
    }
}
