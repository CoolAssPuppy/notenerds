import PencilKit
import UIKit

extension PencilCanvasView {
    func applyPaper(to canvasView: PKCanvasView, coordinator: Coordinator) {
        let marginRuleTag = 8_421
        if coordinator.paperType != template {
            coordinator.hasAppliedInitialPlannerViewport = false
        }
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
}
