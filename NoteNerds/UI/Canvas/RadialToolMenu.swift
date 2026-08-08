import SwiftUI

struct RadialToolMenu: View {
    let configuration: ToolConfiguration
    @Binding var isVisible: Bool
    let requestedOrigin: CGPoint?
    let isSelectionActive: Bool
    let onSelect: (CanvasTool) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCycleWidth: () -> Void
    let onCycleColor: () -> Void
    let onSelectionAction: (CanvasEditingAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var isExpanded = false
    @State private var isRippleExpanded = false

    var body: some View {
        GeometryReader { proxy in
            let layout = PencilRadialMenuLayout(size: proxy.size, requestedOrigin: requestedOrigin)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isVisible = false }

                Circle()
                    .stroke(Color.accentColor.opacity(isRippleExpanded ? 0 : 0.5), lineWidth: 2)
                    .frame(
                        width: isRippleExpanded ? 68 : 18,
                        height: isRippleExpanded ? 68 : 18
                    )
                    .opacity(isRippleExpanded ? 0 : 1)
                    .position(layout.anchor)
                    .animation(.easeOut(duration: 0.38), value: isRippleExpanded)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button(item.label, systemImage: item.symbol) {
                        perform(item.action)
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(foregroundStyle(for: item.action))
                    .frame(width: 54, height: 54)
                    .background(buttonBackground(for: item.action))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.82), lineWidth: 1)
                    }
                    .shadow(
                        color: item.action.selectedTool == configuration.tool
                            ? Color.accentColor.opacity(0.28)
                            : Color.black.opacity(0.14),
                        radius: 12,
                        y: 8
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
        .onAppear(perform: beginAppearance)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick tools")
    }

    @ViewBuilder
    private func buttonBackground(for action: RadialAction) -> some View {
        if action.selectedTool == configuration.tool {
            Color.accentColor
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private func foregroundStyle(for action: RadialAction) -> Color {
        if action == .color { return configuration.color.swiftUIColor }
        return action.selectedTool == configuration.tool ? .white : .primary
    }

    private func itemAnimation(for index: Int) -> Animation? {
        guard !isReduceMotionEnabled else { return nil }
        return .spring(response: 0.42, dampingFraction: 0.72)
            .delay(Double(index) * 0.026)
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

    private var items: [RadialItem] {
        if isSelectionActive {
            return [
                RadialItem(id: "copy", label: "Copy", symbol: "doc.on.doc", action: .selection(.copy)),
                RadialItem(id: "cut", label: "Cut", symbol: "scissors", action: .selection(.cut)),
                RadialItem(
                    id: "duplicate",
                    label: "Duplicate",
                    symbol: "plus.square.on.square",
                    action: .selection(.duplicate)
                ),
                RadialItem(id: "delete", label: "Delete", symbol: "trash", action: .selection(.delete)),
                RadialItem(id: "undo", label: "Undo", symbol: "arrow.uturn.backward", action: .undo),
                RadialItem(id: "redo", label: "Redo", symbol: "arrow.uturn.forward", action: .redo)
            ]
        }
        return [
            RadialItem(id: "eraser", label: "Eraser", symbol: "eraser", action: .tool(.eraser)),
            RadialItem(id: "lasso", label: "Lasso", symbol: "lasso", action: .tool(.lasso)),
            RadialItem(id: "undo", label: "Undo", symbol: "arrow.uturn.backward", action: .undo),
            RadialItem(id: "redo", label: "Redo", symbol: "arrow.uturn.forward", action: .redo),
            RadialItem(id: "width", label: "Width", symbol: "lineweight", action: .width),
            RadialItem(id: "color", label: "Color", symbol: "circle.fill", action: .color)
        ]
    }

    private func perform(_ action: RadialAction) {
        switch action {
        case let .tool(tool): onSelect(tool)
        case .undo: onUndo()
        case .redo: onRedo()
        case .width: onCycleWidth()
        case .color: onCycleColor()
        case let .selection(action): onSelectionAction(action)
        }
        UISelectionFeedbackGenerator().selectionChanged()
        isVisible = false
    }

}

private struct RadialItem {
    let id: String
    let label: String
    let symbol: String
    let action: RadialAction
}

private enum RadialAction: Equatable {
    case tool(CanvasTool)
    case undo
    case redo
    case width
    case color
    case selection(CanvasEditingAction)

    var selectedTool: CanvasTool? {
        guard case let .tool(tool) = self else { return nil }
        return tool
    }
}

extension CanvasTool {
    var label: String {
        switch self {
        case .ballpoint: "Ballpoint"
        case .fineliner: "Fineliner"
        case .mechanicalPencil: "Mechanical pencil"
        case .pencil: "Pencil"
        case .marker: "Marker"
        case .highlighter: "Highlighter"
        case .brush: "Brush"
        case .calligraphyPen: "Calligraphy pen"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        case .handwritingToText: "Handwriting to text"
        }
    }

    var symbol: String {
        switch self {
        case .eraser: "eraser"
        case .lasso: "lasso"
        case .highlighter, .marker: "highlighter"
        case .pencil, .mechanicalPencil: "pencil"
        case .brush: "paintbrush.pointed"
        case .calligraphyPen: "pencil.tip.crop.circle"
        case .handwritingToText: "character.cursor.ibeam"
        case .ballpoint, .fineliner: "pencil.tip"
        }
    }
}

private extension InkColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
