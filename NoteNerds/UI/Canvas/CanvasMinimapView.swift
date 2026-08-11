import SwiftUI

/// Draws the minimap from the live viewport.
///
/// This is the only view that observes `CanvasViewportModel`, which keeps
/// scroll and zoom reports from re-evaluating the whole editor body.
struct CanvasViewportMinimap: View {
    @ObservedObject var viewport: CanvasViewportModel
    let contentBounds: CanvasRect?

    var body: some View {
        CanvasMinimapView(
            contentBounds: contentBounds ?? viewport.bounds,
            viewportBounds: viewport.bounds
        )
    }
}

struct CanvasMinimapView: View {
    let contentBounds: CanvasRect
    let viewportBounds: CanvasRect

    var body: some View {
        GeometryReader { proxy in
            let layout = MinimapLayout(
                contentBounds: contentBounds,
                viewportBounds: viewportBounds,
                displaySize: CanvasSize(width: proxy.size.width, height: proxy.size.height)
            )
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(.secondary.opacity(0.18))
                    .frame(width: layout.contentFrame.size.width, height: layout.contentFrame.size.height)
                    .offset(x: layout.contentFrame.minX, y: layout.contentFrame.minY)
                Rectangle()
                    .stroke(.primary, lineWidth: 2)
                    .frame(width: layout.viewportFrame.size.width, height: layout.viewportFrame.size.height)
                    .offset(x: layout.viewportFrame.minX, y: layout.viewportFrame.minY)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Canvas minimap")
        .accessibilityValue("Shows the visible area within the canvas content")
    }
}
