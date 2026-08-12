import PencilKit
import UIKit

extension PencilCanvasView {
    static func configureViewport(_ canvasView: PKCanvasView) {
        canvasView.minimumZoomScale = CanvasViewport.minimumZoom
        canvasView.maximumZoomScale = CanvasViewport.maximumZoom
        // A single resting finger or palm must not move the page while the
        // Pencil is writing. Two fingers still pan and pinch as expected.
        canvasView.panGestureRecognizer.minimumNumberOfTouches = 2
        canvasView.contentSize = CGSize(width: 20_000, height: 20_000)
        canvasView.contentOffset = CGPoint(x: 9_500, y: 9_500)
    }

    func updatePlannerContext(_ coordinator: Coordinator) {
        if coordinator.canvasID != canvasID {
            coordinator.hasAppliedInitialPlannerViewport = false
        }
        coordinator.canvasID = canvasID
        coordinator.plannerRegions = plannerRegions
        coordinator.selectedPlannerRegionID = selectedPlannerRegionID
        coordinator.isPlannerRegionPagingEnabled = isPlannerRegionPagingEnabled
        coordinator.shouldAnimatePlannerRegionChanges = shouldAnimatePlannerRegionChanges
    }

    func applyInitialPlannerViewport(to canvasView: PKCanvasView, coordinator: Coordinator) {
        guard template.isPlanner,
              !coordinator.isPlannerRegionPagingEnabled,
              !coordinator.hasAppliedInitialPlannerViewport,
              canvasView.bounds.width > 0 else { return }
        let zoom = PlannerViewportPolicy.initialZoom(for: canvasView.bounds.size)
        let pageOrigin = PlannerPageLayout.canvasPageOrigin
        let horizontalInset = max(16, (canvasView.bounds.width - PlannerPageLayout.pageSize.width * zoom) / 2)
        canvasView.setZoomScale(zoom, animated: false)
        canvasView.setContentOffset(
            CGPoint(x: pageOrigin.x * zoom - horizontalInset, y: pageOrigin.y * zoom - 16),
            animated: false
        )
        coordinator.hasAppliedInitialPlannerViewport = true
    }

}

extension PencilCanvasView.Coordinator {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        hasRequestedRegionForCurrentPan = false
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity _: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        let translation = scrollView.panGestureRecognizer.translation(in: scrollView)
        let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
        let predictedTranslation = CGSize(
            width: translation.x + velocity.x * 0.12,
            height: translation.y + velocity.y * 0.12
        )
        guard requestPlannerRegionPage(
            translation: CGSize(width: translation.x, height: translation.y),
            predictedTranslation: predictedTranslation
        ) else { return }
        targetContentOffset.pointee = scrollView.contentOffset
    }

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func focusPlannerRegionIfNeeded(in canvasView: PKCanvasView) {
        guard isPlannerRegionPagingEnabled,
              !isApplyingPlannerViewport,
              canvasView.bounds.width > 0,
              let canvasID,
              let region = selectedPlannerRegion else { return }
        let viewportSize = canvasView.bounds.size
        let isSameFocus = lastFocusedCanvasID == canvasID
            && lastFocusedRegionID == region.id
            && lastPlannerViewportSize == viewportSize
        guard !isSameFocus else { return }
        let shouldAnimate = shouldAnimatePlannerRegionChanges
            && lastFocusedCanvasID == canvasID
            && lastPlannerViewportSize == viewportSize
        lastFocusedCanvasID = canvasID
        lastFocusedRegionID = region.id
        lastPlannerViewportSize = viewportSize
        isApplyingPlannerViewport = true
        canvasView.zoom(to: region.frame.pencilKitRect.insetBy(dx: -16, dy: -16), animated: shouldAnimate)
        isApplyingPlannerViewport = false
    }

    private var selectedPlannerRegion: CanvasRegion? {
        if let selectedPlannerRegionID,
           let region = plannerRegions.first(where: { $0.id == selectedPlannerRegionID }) {
            return region
        }
        return plannerRegions.first
    }

    private func requestPlannerRegionPage(
        translation: CGSize,
        predictedTranslation: CGSize
    ) -> Bool {
        guard let currentIndex = currentPlannerRegionIndex else { return false }
        let destinationIndex = PlannerRegionPaging.destinationIndex(
            from: currentIndex,
            regionCount: plannerRegions.count,
            translation: translation,
            predictedTranslation: predictedTranslation
        )
        return requestPlannerRegion(destinationIndex, currentIndex: currentIndex)
    }

    private var currentPlannerRegionIndex: Int? {
        guard isPlannerRegionPagingEnabled,
              plannerRegions.count > 1,
              let selectedPlannerRegionID else { return nil }
        return plannerRegions.firstIndex(where: { $0.id == selectedPlannerRegionID })
    }

    private func requestPlannerRegion(_ index: Int, currentIndex: Int) -> Bool {
        guard index != currentIndex else { return false }
        hasRequestedRegionForCurrentPan = true
        onPlannerRegionPageRequested(index)
        return true
    }
}
