import SwiftUI

struct CanvasBrowserView: View {
    let notebook: Notebook
    @Binding var selectedIndex: Int
    let onRename: (CanvasID, String) -> Void
    let onDuplicate: (CanvasID) -> Void
    let onMove: (Int, Int) -> Void
    let onDelete: (CanvasID) -> Void
    let onChangePaper: (CanvasID, PaperType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var paperSelection: CanvasPaperSelection?
    @State private var editingCanvasID: CanvasID?
    @State private var draftName = ""

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Array(notebook.canvases.enumerated()), id: \.element.id) { index, canvas in
                        canvasCard(canvas, at: index)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Canvases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $paperSelection) { selection in
            if let canvas = notebook.canvases.first(where: { $0.id == selection.canvasID }) {
                PaperGalleryView(initialSelection: canvas.template, confirmationTitle: "Apply") { paperType in
                    onChangePaper(canvas.id, paperType)
                }
            }
        }
    }

    private func canvasCard(_ canvas: Canvas, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedIndex = index
                dismiss()
            } label: {
                CanvasThumbnail(canvas: canvas)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Canvas thumbnail, \(canvas.title)")
            .accessibilityValue(canvas.template.displayName)

            HStack(alignment: .center, spacing: 8) {
                canvasMetadata(canvas)
                Spacer(minLength: 4)
                Menu {
                    canvasActions(for: canvas, at: index)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .rotationEffect(.degrees(90))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Canvas actions, \(canvas.title)")
                .help("Canvas actions")
            }
        }
        .contextMenu { canvasActions(for: canvas, at: index) }
    }

    @ViewBuilder
    private func canvasMetadata(_ canvas: Canvas) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if editingCanvasID == canvas.id {
                InlineTitleField(
                    text: $draftName,
                    onCommit: { _ in commitRename(canvasID: canvas.id) },
                    onCancel: cancelRename,
                    accessibilityLabel: "Canvas name",
                    textAlignment: .left
                )
                .frame(minWidth: 100, idealWidth: 150, maxWidth: 220, minHeight: 24)
            } else {
                Text(canvas.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            Text(canvas.template.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func canvasActions(for canvas: Canvas, at index: Int) -> some View {
        ForEach(CanvasBrowserAction.allCases, id: \.self) { action in
            Button(action.label, systemImage: action.symbol) {
                perform(action, on: canvas)
            }
        }
        Divider()
        if index > 0 {
            Button("Move earlier", systemImage: "arrow.left") { onMove(index, index - 1) }
        }
        if index < notebook.canvases.count - 1 {
            Button("Move later", systemImage: "arrow.right") { onMove(index, index + 1) }
        }
        if notebook.canvases.count > 1 {
            Divider()
            Button("Delete canvas", systemImage: AppSymbol.trash, role: .destructive) {
                onDelete(canvas.id)
            }
        }
    }

    private func perform(_ action: CanvasBrowserAction, on canvas: Canvas) {
        switch action {
        case .rename: beginRename(canvas)
        case .duplicate: onDuplicate(canvas.id)
        case .changePaper: paperSelection = CanvasPaperSelection(canvasID: canvas.id)
        }
    }

    private func beginRename(_ canvas: Canvas) {
        draftName = canvas.title
        editingCanvasID = canvas.id
    }

    private func commitRename(canvasID: CanvasID) {
        guard editingCanvasID == canvasID else { return }
        let proposedName = draftName
        editingCanvasID = nil
        guard CanvasName.normalized(proposedName) != nil else { return }
        onRename(canvasID, proposedName)
    }

    private func cancelRename() {
        editingCanvasID = nil
        draftName = ""
    }
}

private struct CanvasThumbnail: View {
    let canvas: Canvas

    var body: some View {
        CanvasContentThumbnail(canvas: canvas)
    }
}
