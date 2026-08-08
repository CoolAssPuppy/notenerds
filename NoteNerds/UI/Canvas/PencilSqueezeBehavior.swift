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

    static func viewportLocation(
        poseLocation: CGPoint?,
        lastHoverLocation: CGPoint?,
        visibleBounds: CGRect
    ) -> CGPoint? {
        guard let viewLocation = location(
            poseLocation: poseLocation,
            lastHoverLocation: lastHoverLocation
        ) else { return nil }
        return CGPoint(
            x: viewLocation.x - visibleBounds.minX,
            y: viewLocation.y - visibleBounds.minY
        )
    }

#if DEBUG
    static func radialMenuTestOrigin(arguments: [String]) -> CGPoint? {
        guard arguments.contains("-ui-testing"),
              let markerIndex = arguments.firstIndex(of: "-radial-menu-origin"),
              arguments.indices.contains(markerIndex + 2),
              let x = Double(arguments[markerIndex + 1]),
              let y = Double(arguments[markerIndex + 2]),
              x.isFinite,
              y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }
#endif
}

struct PencilRadialMenuLayout {
    let anchor: CGPoint
    private let radiusScale: Double

    init(size: CGSize, requestedOrigin: CGPoint?, maximumItemCount: Int = 6) {
        let requestedOrigin = requestedOrigin ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = RadialPalettePresentation.maximumRadius(for: maximumItemCount)
        let shortestDimension = min(size.width, size.height)
        let availableRadius = max(0, shortestDimension / 2 - 27)
        radiusScale = outerRadius > 0 ? min(1, availableRadius / outerRadius) : 1
        let safeInset = outerRadius * radiusScale + 27
        anchor = CGPoint(
            x: Self.clamped(requestedOrigin.x, inset: safeInset, length: size.width),
            y: Self.clamped(requestedOrigin.y, inset: safeInset, length: size.height)
        )
    }

    func offset(itemAt index: Int, itemCount: Int) -> CGSize {
        guard itemCount > 0 else { return .zero }
        let placement = RadialPalettePresentation.placement(for: index, itemCount: itemCount)
        let angle = (
            -90 + (Double(placement.indexInRing) / Double(placement.itemCountInRing)) * 360
        ) * Double.pi / 180
        return CGSize(
            width: cos(angle) * placement.radius * radiusScale,
            height: sin(angle) * placement.radius * radiusScale
        )
    }

    func position(itemAt index: Int, itemCount: Int) -> CGPoint {
        let offset = offset(itemAt: index, itemCount: itemCount)
        return CGPoint(x: anchor.x + offset.width, y: anchor.y + offset.height)
    }

    private static func clamped(_ value: Double, inset: Double, length: Double) -> Double {
        min(max(inset, value), max(inset, length - inset))
    }
}
