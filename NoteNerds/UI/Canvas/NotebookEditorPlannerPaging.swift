import SwiftUI

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
}
