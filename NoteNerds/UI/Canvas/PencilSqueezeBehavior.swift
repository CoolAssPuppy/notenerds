import UIKit

enum PencilSqueezeResponse: Equatable {
    case none
    case switchEraser
    case switchPreviousTool
    case showRadialPalette
}

enum PencilSqueezeBehavior {
    static func response(
        for preference: UIPencilPreferredAction,
        phase: UIPencilInteraction.Phase
    ) -> PencilSqueezeResponse {
        guard phase == .ended else { return .none }
        switch preference {
        case .switchEraser:
            return .switchEraser
        case .switchPrevious:
            return .switchPreviousTool
        case .showColorPalette, .showInkAttributes, .showContextualPalette:
            return .showRadialPalette
        case .ignore, .runSystemShortcut:
            return .none
        @unknown default:
            return .none
        }
    }

    static func location(poseLocation: CGPoint?, lastHoverLocation: CGPoint?) -> CGPoint? {
        poseLocation ?? lastHoverLocation
    }
}

struct PencilRadialMenuLayout {
    let anchor: CGPoint

    init(size: CGSize, requestedOrigin: CGPoint?) {
        let requestedOrigin = requestedOrigin ?? CGPoint(x: size.width / 2, y: size.height / 2)
        anchor = CGPoint(
            x: min(max(107, requestedOrigin.x), max(107, size.width - 107)),
            y: min(max(107, requestedOrigin.y), max(107, size.height - 107))
        )
    }

    func offset(itemAt index: Int, itemCount: Int) -> CGSize {
        guard itemCount > 0 else { return .zero }
        let angle = (-90 + (Double(index) / Double(itemCount)) * 360) * Double.pi / 180
        let radius = 80.0
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    func position(itemAt index: Int, itemCount: Int) -> CGPoint {
        let offset = offset(itemAt: index, itemCount: itemCount)
        return CGPoint(x: anchor.x + offset.width, y: anchor.y + offset.height)
    }
}
