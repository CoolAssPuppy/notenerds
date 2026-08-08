import SwiftUI
import UIKit

struct PlannerRegionPageControl: UIViewRepresentable {
    let regions: [CanvasRegion]
    let selectedIndex: Int
    let onSelect: @MainActor (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> UIPageControl {
        let pageControl = UIPageControl()
        pageControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:)),
            for: .valueChanged
        )
        pageControl.allowsContinuousInteraction = true
        pageControl.backgroundStyle = .prominent
        pageControl.hidesForSinglePage = true
        pageControl.accessibilityIdentifier = "Planner sections"
        return pageControl
    }

    func updateUIView(_ pageControl: UIPageControl, context: Context) {
        context.coordinator.onSelect = onSelect
        pageControl.numberOfPages = regions.count
        pageControl.currentPage = min(max(0, selectedIndex), max(0, regions.count - 1))
        pageControl.accessibilityLabel = "Planner sections"
        guard regions.indices.contains(pageControl.currentPage) else {
            pageControl.accessibilityValue = nil
            return
        }
        pageControl.accessibilityValue = "\(pageControl.currentPage + 1) of \(regions.count), "
            + regions[pageControl.currentPage].title
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: @MainActor (Int) -> Void

        init(onSelect: @escaping @MainActor (Int) -> Void) {
            self.onSelect = onSelect
        }

        @objc func selectionChanged(_ sender: UIPageControl) {
            onSelect(sender.currentPage)
        }
    }
}
