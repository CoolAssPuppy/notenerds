import SwiftUI

enum CanvasToolbarPreferences {
    static let isExpandedKey = "isCanvasToolbarExpanded"
    static let isExpandedByDefault = false
}

struct CanvasToolbarView: View {
    let editor: NotebookEditorView
    @State private var presentedInspector: CanvasToolbarInspector?
    @AppStorage(CanvasToolbarPreferences.isExpandedKey)
    private var isExpanded = CanvasToolbarPreferences.isExpandedByDefault
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @Environment(\.accessibilityReduceTransparency) private var isReduceTransparencyEnabled

    private let drawingTools = CanvasToolbarPresentation.specializedDrawingTools

    var body: some View {
        toolbarContainer
        .popover(item: $presentedInspector) { inspector in
            inspectorContent(inspector)
        }
        .padding(4)
        .background(toolbarBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.09), radius: 18, y: 6)
        .animation(toolbarAnimation, value: isExpanded)
    }

    @ViewBuilder
    private var toolbarContainer: some View {
        if editor.toolbarOrientation == .vertical {
            VStack(spacing: 2) {
                toolbarViewport
                expansionButton
            }
        } else {
            HStack(spacing: 2) {
                toolbarViewport
                expansionButton
            }
        }
    }

    @ViewBuilder
    private var toolbarViewport: some View {
        if isExpanded {
            toolbarLayout {
                coreActionItems
                ScrollView(scrollAxes, showsIndicators: false) {
                    toolbarLayout { expandedActionItems }
                }
                .accessibilityLabel("Expanded tools")
                .frame(
                    maxWidth: editor.toolbarOrientation == .horizontal ? maximumExpandedLength : nil,
                    maxHeight: editor.toolbarOrientation == .vertical ? maximumExpandedLength : nil
                )
                .scrollBounceBehavior(.basedOnSize)
            }
        } else {
            toolbarLayout { coreActionItems }
        }
    }

    @ViewBuilder
    private var coreActionItems: some View {
        drawingToolInspectorButton
        widthInspectorButton
        colorInspectorButton
        eraserInspectorButton
        chromeButton("Lasso", symbol: "lasso", isSelected: editor.configuration.tool == .lasso) {
            editor.selectTool(.lasso)
        }
    }

    @ViewBuilder
    private var expandedActionItems: some View {
        chromeDivider
        chromeButton("Add text", symbol: "textformat", isSelected: editor.isTextToolActive) {
            editor.activateTextTool()
        }
        .accessibilityValue(editor.isTextToolActive ? "Selected" : "Not selected")
        shapeInspectorButton
        chromeDivider
        chromeButton("Undo", symbol: "arrow.uturn.backward") { editor.model.undo(editor.notebook.id) }
            .keyboardShortcut("z", modifiers: .command)
        chromeButton("Redo", symbol: "arrow.uturn.forward") { editor.model.redo(editor.notebook.id) }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        chromeDivider
        layersButton
    }

    private var toolbarLayout: AnyLayout {
        switch editor.toolbarOrientation {
        case .vertical: AnyLayout(VStackLayout(spacing: 4))
        case .horizontal: AnyLayout(HStackLayout(spacing: 4))
        }
    }

    private var drawingToolInspectorButton: some View {
        Button { presentedInspector = .drawing } label: {
            CanvasChromeIcon(
                symbol: editor.selectedDrawingTool.symbol,
                isSelected: editor.configuration.tool.instrument != nil
            )
        }
        .accessibilityLabel("Drawing tools")
        .accessibilityValue(editor.selectedDrawingTool.label)
        .help(editor.selectedDrawingTool.label)
    }

    private var shapeInspectorButton: some View {
        Button { presentedInspector = .shapes } label: {
            CanvasChromeIcon(symbol: "square.on.circle", isSelected: editor.selectedShapeKind != nil)
        }
        .accessibilityLabel("Shapes")
        .accessibilityValue(editor.selectedShapeKind?.displayName ?? "Not selected")
        .help("Shapes")
    }

    private var widthInspectorButton: some View {
        Button { presentedInspector = .width } label: {
            CanvasChromeIcon(symbol: "lineweight")
        }
        .accessibilityLabel("Stroke width")
        .accessibilityValue(editor.configuration.width.label)
        .help("Stroke width")
    }

    private var colorInspectorButton: some View {
        Button { presentedInspector = .color } label: {
            Circle()
                .fill(Color(uiColor: UIColor(editor.configuration.color)))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.primary.opacity(0.28), lineWidth: 0.75))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Ink color")
        .help("Ink color")
    }

    private var eraserInspectorButton: some View {
        Button { presentedInspector = .eraser } label: {
            CanvasChromeIcon(symbol: "eraser", isSelected: editor.configuration.tool == .eraser)
        }
        .accessibilityLabel("Eraser")
        .accessibilityValue(editor.configuration.eraserMode.rawValue.capitalized)
        .help("Eraser")
    }

    private var eraserInspector: some View {
        CanvasEraserInspector(
            selectedMode: editor.configuration.eraserMode,
            selectedWidth: editor.configuration.width,
            onSelectMode: { mode in
                editor.selectEraser(mode)
                presentedInspector = nil
            },
            onSelectWidth: editor.setWidth
        )
        .onAppear { editor.selectTool(.eraser) }
    }

    private var expansionButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(toolbarAnimation) { isExpanded.toggle() }
        } label: {
            Image(systemName: CanvasToolbarPresentation.chevronSymbol(orientation: editor.toolbarOrientation))
                .font(.system(size: 16, weight: .semibold))
                .rotationEffect(.degrees(CanvasToolbarPresentation.chevronRotation(isExpanded: isExpanded)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Show fewer tools" : "Show more tools")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .help(isExpanded ? "Show fewer tools" : "Show more tools")
    }

    private var layersButton: some View {
        Button { presentedInspector = .layers } label: {
            CanvasChromeIcon(symbol: "square.3.layers.3d", isSelected: false)
        }
        .accessibilityLabel("Layers")
        .help("Layers")
    }

    @ViewBuilder
    private func inspectorContent(_ inspector: CanvasToolbarInspector) -> some View {
        switch inspector {
        case .drawing:
            drawingInspector
        case .width:
            CanvasWidthInspector(
                selectedWidth: editor.configuration.width,
                onSelect: editor.setWidth
            )
        case .color:
            CanvasColorInspector(
                selectedColor: editor.configuration.color,
                onSelect: editor.setColor
            )
        case .eraser:
            eraserInspector
        case .shapes:
            CanvasShapeInspector(selectedKind: editor.selectedShapeKind) { kind in
                editor.activateShapeTool(kind)
                presentedInspector = nil
            }
        case .layers:
            CanvasLayersPanel(
                canvas: editor.currentCanvas,
                selectedLayerID: editor.activeLayer.id,
                onSelect: editor.selectLayer,
                onCreate: editor.addLayer,
                onToggleVisibility: editor.toggleLayer,
                onRename: editor.renameLayer,
                onMove: editor.moveLayer,
                onDelete: editor.deleteLayer
            )
        }
    }

    private var drawingInspector: some View {
        CanvasDrawingToolInspector(
            tools: drawingTools,
            selectedTool: editor.selectedDrawingTool,
            favoriteOne: editor.favoriteOne,
            favoriteTwo: editor.favoriteTwo,
            isFingerDrawingEnabled: editor.$isFingerDrawingEnabled,
            onSelectTool: { tool in
                editor.selectTool(tool)
                presentedInspector = nil
            },
            onSelectFavorite: { configuration in
                editor.select(configuration)
                presentedInspector = nil
            },
            onSaveFavoriteOne: editor.saveFavoriteOne,
            onSaveFavoriteTwo: editor.saveFavoriteTwo
        )
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if isReduceTransparencyEnabled {
            shape.fill(Color(uiColor: .systemBackground))
        } else {
            shape.fill(.thinMaterial)
        }
    }

    private var toolbarAnimation: Animation? {
        isReduceMotionEnabled ? .linear(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.88)
    }

    private var scrollAxes: Axis.Set {
        editor.toolbarOrientation == .vertical ? .vertical : .horizontal
    }

    private var maximumExpandedLength: CGFloat {
        CanvasToolbarPresentation.maximumExpandedLength(orientation: editor.toolbarOrientation)
    }

    private var chromeDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(
                width: editor.toolbarOrientation == .vertical ? 24 : 1,
                height: editor.toolbarOrientation == .vertical ? 1 : 24
            )
            .padding(editor.toolbarOrientation == .vertical ? .vertical : .horizontal, 3)
    }

    private func chromeButton(
        _ title: String,
        symbol: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CanvasChromeIcon(symbol: symbol, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

}

private enum CanvasToolbarInspector: Identifiable {
    case drawing
    case width
    case color
    case eraser
    case shapes
    case layers

    var id: Self { self }
}

private struct CanvasChromeIcon: View {
    let symbol: String
    var isSelected = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(width: 44, height: 44)
            .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
            .contentShape(Rectangle())
    }
}
