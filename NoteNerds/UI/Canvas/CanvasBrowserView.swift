import SwiftUI

struct CanvasBrowserView: View {
    let notebook: Notebook
    @Binding var selectedIndex: Int
    let onMove: (Int, Int) -> Void
    let onChangePaper: (CanvasID, PaperType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var paperSelection: CanvasPaperSelection?

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Array(notebook.canvases.enumerated()), id: \.element.id) { index, canvas in
                        Button {
                            selectedIndex = index
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                CanvasThumbnail(canvas: canvas)
                                Text(canvas.title).font(.headline)
                                Text(canvas.template.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Canvas thumbnail, \(canvas.title)")
                        .accessibilityValue(canvas.template.displayName)
                        .contextMenu {
                            Button("Change paper", systemImage: "doc.text.image") {
                                paperSelection = CanvasPaperSelection(canvasID: canvas.id)
                            }
                            if index > 0 {
                                Button("Move earlier", systemImage: "arrow.left") { onMove(index, index - 1) }
                            }
                            if index < notebook.canvases.count - 1 {
                                Button("Move later", systemImage: "arrow.right") { onMove(index, index + 1) }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Canvases")
            .toolbar {
                Button("Done") { dismiss() }
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
}

private struct CanvasThumbnail: View {
    let canvas: Canvas

    var body: some View {
        CanvasContentThumbnail(canvas: canvas)
    }
}
