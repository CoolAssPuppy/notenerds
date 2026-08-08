import SwiftUI

struct CanvasToolbarView: View {
    let editor: NotebookEditorView
    @State private var layerToRename: Layer?
    @State private var proposedLayerName = ""
    @State private var presentedInspector: CanvasToolbarInspector?
    @AppStorage("isCanvasToolbarExpanded") private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @Environment(\.accessibilityReduceTransparency) private var isReduceTransparencyEnabled

    private let drawingTools: [CanvasTool] = [
        .ballpoint, .fineliner, .mechanicalPencil, .pencil,
        .marker, .highlighter, .brush, .calligraphyPen, .handwritingToText
    ]

    var body: some View {
        toolbarContainer
        .padding(4)
        .background(toolbarBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.09), radius: 18, y: 6)
        .animation(toolbarAnimation, value: isExpanded)
        .alert("Rename layer", isPresented: renamePresentation) {
            TextField("Layer name", text: $proposedLayerName)
            Button("Rename") {
                if let layerToRename { editor.renameLayer(layerToRename, to: proposedLayerName) }
                layerToRename = nil
            }
            Button("Cancel", role: .cancel) { layerToRename = nil }
        }
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
            ScrollView(scrollAxes, showsIndicators: false) {
                toolbarLayout { toolbarActionItems }
            }
            .accessibilityLabel("Expanded tools")
            .frame(
                maxWidth: editor.toolbarOrientation == .horizontal ? maximumExpandedLength : nil,
                maxHeight: editor.toolbarOrientation == .vertical ? maximumExpandedLength : nil
            )
            .scrollBounceBehavior(.basedOnSize)
        } else {
            toolbarLayout { toolbarActionItems }
        }
    }

    @ViewBuilder
    private var toolbarActionItems: some View {
        drawingToolInspectorButton
        widthInspectorButton
        colorInspectorButton
        eraserInspectorButton
        if isExpanded {
            chromeDivider
            chromeButton("Lasso", symbol: "lasso", isSelected: editor.configuration.tool == .lasso) {
                editor.selectTool(.lasso)
            }
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
            chromeButton("Zoom to content", symbol: "arrow.up.left.and.arrow.down.right") {
                editor.zoomToContent()
            }
            chromeButton("Minimap", symbol: "map") { editor.toggleMinimap() }
            chromeButton("Change paper", symbol: "doc.text.image") { editor.showPaperGallery() }
            chromeButton("Import", symbol: "square.and.arrow.down") { editor.importContent() }
            layersButton
            chromeButton("Home", symbol: "house") { editor.returnHome() }
        }
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
        .popover(isPresented: inspectorBinding(.drawing)) {
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
    }

    private var shapeInspectorButton: some View {
        Button { presentedInspector = .shapes } label: {
            CanvasChromeIcon(symbol: "square.on.circle", isSelected: editor.selectedShapeKind != nil)
        }
        .accessibilityLabel("Shapes")
        .accessibilityValue(editor.selectedShapeKind?.displayName ?? "Not selected")
        .help("Shapes")
        .popover(isPresented: inspectorBinding(.shapes)) {
            CanvasShapeInspector(selectedKind: editor.selectedShapeKind) { kind in
                editor.activateShapeTool(kind)
                presentedInspector = nil
            }
        }
    }

    private var widthInspectorButton: some View {
        Button { presentedInspector = .width } label: {
            CanvasChromeIcon(symbol: "lineweight")
        }
        .accessibilityLabel("Stroke width")
        .accessibilityValue(editor.configuration.width.label)
        .help("Stroke width")
        .popover(isPresented: inspectorBinding(.width)) {
            CanvasWidthInspector(
                selectedWidth: editor.configuration.width,
                onSelect: editor.setWidth
            )
        }
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
        .popover(isPresented: inspectorBinding(.color)) {
            CanvasColorInspector(
                selectedColor: editor.configuration.color,
                onSelect: editor.setColor
            )
        }
    }

    private var eraserInspectorButton: some View {
        Button {
            editor.selectTool(.eraser)
            presentedInspector = .eraser
        } label: {
            CanvasChromeIcon(symbol: "eraser", isSelected: editor.configuration.tool == .eraser)
        }
        .accessibilityLabel("Eraser")
        .accessibilityValue(editor.configuration.eraserMode.rawValue.capitalized)
        .help("Eraser")
        .popover(isPresented: inspectorBinding(.eraser)) {
            CanvasEraserInspector(
                selectedMode: editor.configuration.eraserMode,
                selectedWidth: editor.configuration.width,
                onSelectMode: editor.selectEraser,
                onSelectWidth: editor.setWidth
            )
        }
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
        Menu("Layers", systemImage: "square.3.layers.3d") {
            ForEach(editor.currentCanvas.layers) { layer in
                Button(layer.isVisible ? "Hide \(layer.name)" : "Show \(layer.name)") {
                    editor.toggleLayer(layer)
                }
                Button("Rename \(layer.name)", systemImage: "pencil") {
                    proposedLayerName = layer.name
                    layerToRename = layer
                }
                if layer.id != editor.currentCanvas.layers.first?.id {
                    Button("Move \(layer.name) down", systemImage: "arrow.down") {
                        editor.moveLayer(layer, by: -1)
                    }
                }
                if layer.id != editor.currentCanvas.layers.last?.id {
                    Button("Move \(layer.name) up", systemImage: "arrow.up") {
                        editor.moveLayer(layer, by: 1)
                    }
                }
                if editor.currentCanvas.layers.count > 1 {
                    Button("Delete \(layer.name)", role: .destructive) { editor.deleteLayer(layer) }
                }
            }
            Divider()
            Button("New layer", systemImage: "plus", action: editor.addLayer)
        }
        .labelStyle(.iconOnly)
        .frame(width: 44, height: 44)
        .accessibilityLabel("Layers")
        .help("Layers")
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

    private var renamePresentation: Binding<Bool> {
        Binding(
            get: { layerToRename != nil },
            set: { if !$0 { layerToRename = nil } }
        )
    }

    private func inspectorBinding(_ inspector: CanvasToolbarInspector) -> Binding<Bool> {
        Binding(
            get: { presentedInspector == inspector },
            set: { isPresented in
                presentedInspector = isPresented ? inspector : nil
            }
        )
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

private enum CanvasToolbarInspector {
    case drawing
    case width
    case color
    case eraser
    case shapes
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

extension CanvasTool {
    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .ballpoint: "b"
        case .fineliner: "f"
        case .mechanicalPencil: "m"
        case .pencil: "p"
        case .marker: "k"
        case .highlighter: "h"
        case .brush: "r"
        case .calligraphyPen: "g"
        case .eraser: "e"
        case .lasso: "l"
        case .handwritingToText: "t"
        }
    }
}
