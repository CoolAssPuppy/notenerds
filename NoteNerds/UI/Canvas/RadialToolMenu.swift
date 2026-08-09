import SwiftUI
import UIKit

struct RadialToolMenu: View {
    let configuration: ToolConfiguration
    @Binding var isVisible: Bool
    let requestedOrigin: CGPoint?
    let isSelectionActive: Bool
    let onSelect: (CanvasTool) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSetWidth: (ToolWidth) -> Void
    let onSetColor: (InkColor) -> Void
    let onSelectEraser: (EraserMode) -> Void
    let onSelectionAction: (CanvasEditingAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var page = RadialPalettePage.root
    @State private var isExpanded = false
    @State private var isRippleExpanded = false

    var body: some View {
        GeometryReader { proxy in
            let layout = PencilRadialMenuLayout(
                size: proxy.size,
                requestedOrigin: requestedOrigin,
                maximumItemCount: RadialPalettePresentation.maximumItemCount
            )
            ZStack {
                dismissBackground(around: layout.anchor)
                anchorMarker(at: layout.anchor)
                squeezeRipple(at: layout.anchor)
                itemCluster(layout: layout)
                    .id(page)
                    .transition(pageTransition)
                if page.parent != nil, !isSelectionActive {
                    backButton(at: layout.anchor)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .animation(pageAnimation, value: page)
        }
        .onAppear(perform: beginAppearance)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick tools")
    }

    private func dismissBackground(around anchor: CGPoint) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { location in
                let distance = hypot(location.x - anchor.x, location.y - anchor.y)
                if distance > 32 { isVisible = false }
            }
    }

    private func anchorMarker(at point: CGPoint) -> some View {
        Color.clear
            .frame(width: 2, height: 2)
            .position(point)
            .accessibilityElement()
            .accessibilityIdentifier("Radial menu anchor")
            .accessibilityLabel("Radial menu anchor")
            .accessibilityHidden(!ProcessInfo.processInfo.arguments.contains("-ui-testing"))
    }

    private func squeezeRipple(at point: CGPoint) -> some View {
        Circle()
            .stroke(Color.accentColor.opacity(isRippleExpanded ? 0 : 0.5), lineWidth: 2)
            .frame(
                width: isRippleExpanded ? 68 : 18,
                height: isRippleExpanded ? 68 : 18
            )
            .opacity(isRippleExpanded ? 0 : 1)
            .position(point)
            .animation(.easeOut(duration: 0.38), value: isRippleExpanded)
    }

    private func itemCluster(layout: PencilRadialMenuLayout) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                itemControl(item)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected(item.action) ? Color.white : Color.primary)
                    .frame(width: 50, height: 50)
                    .background(buttonBackground(for: item.action))
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.86), lineWidth: 1)
                    }
                    .shadow(
                        color: isSelected(item.action)
                            ? Color.accentColor.opacity(0.28)
                            : Color.black.opacity(0.14),
                        radius: 11,
                        y: 7
                    )
                    .scaleEffect(isExpanded ? 1 : 0.24)
                    .opacity(isExpanded ? 1 : 0)
                    .position(
                        isExpanded
                            ? layout.position(itemAt: index, itemCount: items.count)
                            : layout.anchor
                    )
                    .animation(itemAnimation(for: index), value: isExpanded)
            }
        }
    }

    @ViewBuilder
    private func itemControl(_ item: RadialPaletteItem) -> some View {
        if item.action == .customColor {
            ColorPicker(
                "Custom color",
                selection: customColor,
                supportsOpacity: true
            )
            .labelsHidden()
            .accessibilityLabel("Custom color")
            .accessibilityIdentifier("Radial custom color")
            .frame(width: 50, height: 50)
            .contentShape(Rectangle())
        } else {
            Button {
                perform(item.action)
            } label: {
                itemLabel(item)
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.label)
            .accessibilityValue(isSelected(item.action) ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected(item.action) ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func itemLabel(_ item: RadialPaletteItem) -> some View {
        switch item.action {
        case let .color(color):
            Circle()
                .fill(Color(uiColor: UIColor(color)))
                .frame(width: 25, height: 25)
                .overlay(Circle().stroke(Color.primary.opacity(0.22), lineWidth: 0.75))
        case let .width(width):
            Capsule()
                .fill(isSelected(item.action) ? Color.white : Color.primary)
                .frame(width: 30, height: max(2, min(10, width.points)))
        default:
            Image(systemName: item.symbol)
        }
    }

    @ViewBuilder
    private func buttonBackground(for action: RadialPaletteAction) -> some View {
        if isSelected(action) {
            Color.accentColor
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private func backButton(at point: CGPoint) -> some View {
        Button("Back", systemImage: "chevron.backward") {
            returnToParentPage()
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 16, weight: .semibold))
        .frame(width: 42, height: 42)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.82), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
        .position(point)
        .accessibilityLabel("Back")
        .highPriorityGesture(TapGesture().onEnded(returnToParentPage))
    }

    private func returnToParentPage() {
        guard let parent = page.parent else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        page = parent
    }

    private var items: [RadialPaletteItem] {
        if isSelectionActive {
            return selectionItems
        }
        return RadialPalettePresentation.items(for: page)
    }

    private var selectionItems: [RadialPaletteItem] {
        [
            RadialPaletteItem(
                id: "copy",
                label: "Copy",
                symbol: "doc.on.doc",
                action: .selection(.copy)
            ),
            RadialPaletteItem(id: "cut", label: "Cut", symbol: "scissors", action: .selection(.cut)),
            RadialPaletteItem(
                id: "duplicate",
                label: "Duplicate",
                symbol: "plus.square.on.square",
                action: .selection(.duplicate)
            ),
            RadialPaletteItem(
                id: "delete",
                label: "Delete",
                symbol: "trash",
                action: .selection(.delete)
            ),
            RadialPaletteItem(id: "undo", label: "Undo", symbol: "arrow.uturn.backward", action: .undo),
            RadialPaletteItem(id: "redo", label: "Redo", symbol: "arrow.uturn.forward", action: .redo)
        ]
    }

    private func perform(_ action: RadialPaletteAction) {
        if let destination = action.destination {
            if action == .eraserMode(.precision) {
                onSelectEraser(.precision)
            }
            UISelectionFeedbackGenerator().selectionChanged()
            page = destination
            return
        }

        switch action {
        case let .tool(tool):
            onSelect(tool)
        case let .width(width):
            onSetWidth(width)
        case let .color(color):
            onSetColor(color)
        case let .eraserMode(mode):
            onSelectEraser(mode)
        case .undo:
            onUndo()
        case .redo:
            onRedo()
        case let .selection(action):
            onSelectionAction(action)
        case .open, .customColor:
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        isVisible = false
    }

    private func isSelected(_ action: RadialPaletteAction) -> Bool {
        switch action {
        case let .tool(tool):
            configuration.tool == tool
        case let .width(width):
            configuration.width == width
        case let .color(color):
            configuration.color == color
        case let .eraserMode(mode):
            configuration.tool == .eraser && configuration.eraserMode == mode
        case .open, .customColor, .undo, .redo, .selection:
            false
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(configuration.color)) },
            set: { onSetColor(InkColor(uiColor: UIColor($0))) }
        )
    }

    private func itemAnimation(for index: Int) -> Animation? {
        guard !isReduceMotionEnabled else { return nil }
        return .spring(response: 0.4, dampingFraction: 0.76)
            .delay(Double(index) * 0.018)
    }

    private var pageAnimation: Animation? {
        isReduceMotionEnabled ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    private var pageTransition: AnyTransition {
        guard !isReduceMotionEnabled else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.72).combined(with: .opacity),
            removal: .scale(scale: 1.08).combined(with: .opacity)
        )
    }

    private func beginAppearance() {
        guard !isReduceMotionEnabled else {
            isExpanded = true
            return
        }
        Task { @MainActor in
            await Task.yield()
            isRippleExpanded = true
            isExpanded = true
        }
    }
}
