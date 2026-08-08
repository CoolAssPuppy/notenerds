import SwiftUI

struct CanvasHeaderView: ToolbarContent {
    let notebookTitle: String
    let canvasTitle: String
    @Binding var canvasIndex: Int
    let canvasCount: Int
    let layers: [Layer]
    let isSelectionMenuVisible: Bool
    let isObjectSelectionActive: Bool
    @Binding var isFingerDrawingEnabled: Bool
    let onClose: () -> Void
    let onRenameNotebook: (String) -> Void
    let onOpenBrowser: () -> Void
    let onNewCanvas: () -> Void
    let onSelectionAction: (CanvasEditingAction) -> Void
    let onExportPDF: () -> Void
    let onExportPNG: () -> Void
    let onExportNative: () -> Void
    let onSharePDF: () -> Void
    let onDuplicateCanvas: () -> Void
    let onDeleteCanvas: () -> Void
    let onMoveCanvas: (Int) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Library", systemImage: AppSymbol.back, action: onClose)
        }
        ToolbarItem(placement: .principal) {
            NotebookTitleToolbarView(
                notebookTitle: notebookTitle,
                canvasTitle: canvasTitle,
                canvasIndex: canvasIndex,
                canvasCount: canvasCount,
                onRename: onRenameNotebook,
                onOpenBrowser: onOpenBrowser
            )
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isSelectionMenuVisible { selectionMenu }
            Button("New canvas", systemImage: AppSymbol.add, action: onNewCanvas)
                .keyboardShortcut("n", modifiers: [.command, .shift])
            shareMenu
            documentMenu
        }
    }

    private var selectionMenu: some View {
        Menu("Selection actions", systemImage: "selection.pin.in.out") {
            Button("Copy", systemImage: "doc.on.doc") { onSelectionAction(.copy) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Cut", systemImage: "scissors") { onSelectionAction(.cut) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Paste", systemImage: "doc.on.clipboard") { onSelectionAction(.paste) }
                .keyboardShortcut("v", modifiers: .command)
            Button("Select all", systemImage: "checkmark.circle") { onSelectionAction(.selectAll) }
                .keyboardShortcut("a", modifiers: .command)
            Button("Duplicate", systemImage: "plus.square.on.square") { onSelectionAction(.duplicate) }
            Button("Convert handwriting to text", systemImage: "character.cursor.ibeam") {
                onSelectionAction(.convertToText)
            }
            Menu("Move to layer", systemImage: "square.3.layers.3d") {
                ForEach(layers) { layer in
                    Button(layer.name) { onSelectionAction(.moveToLayer(layer.id)) }
                }
            }
            Divider()
            Button("Delete selection", systemImage: AppSymbol.trash, role: .destructive) {
                onSelectionAction(.delete)
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
        .accessibilityValue(isObjectSelectionActive ? "Selection active" : "Selection tool")
    }

    private var shareMenu: some View {
        Menu("Share", systemImage: AppSymbol.share) {
            Button("Share PDF", systemImage: AppSymbol.share, action: onSharePDF)
            Divider()
            Button("Export PDF", systemImage: "doc.richtext", action: onExportPDF)
            Button("Export canvas image", systemImage: "photo", action: onExportPNG)
            Button("Export editable notebook", systemImage: AppSymbol.notebook, action: onExportNative)
        }
    }

    private var documentMenu: some View {
        Menu("More", systemImage: AppSymbol.more) {
            Button("Duplicate canvas", systemImage: "plus.square.on.square", action: onDuplicateCanvas)
            if canvasIndex > 0 {
                Button("Move canvas earlier", systemImage: "arrow.up") { onMoveCanvas(canvasIndex - 1) }
            }
            if canvasIndex < canvasCount - 1 {
                Button("Move canvas later", systemImage: "arrow.down") { onMoveCanvas(canvasIndex + 1) }
            }
            Toggle("Draw with finger", isOn: $isFingerDrawingEnabled)
            Divider()
            Button("Delete canvas", systemImage: AppSymbol.trash, role: .destructive, action: onDeleteCanvas)
                .disabled(canvasCount == 1)
        }
    }
}
