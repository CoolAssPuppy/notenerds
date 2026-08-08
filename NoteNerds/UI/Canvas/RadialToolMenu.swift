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

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea().onTapGesture { isVisible = false }
            GeometryReader { proxy in
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 270, height: 270)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let angle = (Double(index) / Double(items.count)) * Double.pi * 2 - Double.pi / 2
                        Button(item.label, systemImage: item.symbol) {
                            perform(item.action)
                        }
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(width: 52, height: 52)
                        .background(
                            item.action.selectedTool == configuration.tool
                                ? Color.primary.opacity(0.14)
                                : Color.clear,
                            in: Circle()
                        )
                        .offset(x: cos(angle) * 98, y: sin(angle) * 98)
                    }
                    Button("Close quick tools", systemImage: "xmark") { isVisible = false }
                        .labelStyle(.iconOnly)
                        .frame(width: 48, height: 48)
                }
                .position(adaptedOrigin(in: proxy.size))
            }
        }
        .animation(
            isReduceMotionEnabled ? nil : .spring(response: 0.3, dampingFraction: 0.85),
            value: configuration.tool
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick tools")
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
            RadialItem(
                id: "pen",
                label: configuration.tool.label,
                symbol: configuration.tool.symbol,
                action: .tool(configuration.tool)
            ),
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

    private func adaptedOrigin(in size: CGSize) -> CGPoint {
        let desired = requestedOrigin ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let inset = 125.0
        return CGPoint(
            x: min(max(inset, desired.x), size.width - inset),
            y: min(max(inset, desired.y - 90), size.height - inset)
        )
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
