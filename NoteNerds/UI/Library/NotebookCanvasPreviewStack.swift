import SwiftUI

enum NotebookCanvasPreviewPaging {
    static func destination(from index: Int, translation: CGFloat, canvasCount: Int) -> Int {
        guard canvasCount > 0, abs(translation) >= 40 else { return index }
        let proposedIndex = translation < 0 ? index + 1 : index - 1
        return min(max(proposedIndex, 0), canvasCount - 1)
    }
}

struct NotebookCanvasPreviewStack: View {
    let notebook: Notebook
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var selectedIndex = 0
    @GestureState private var dragOffset = CGFloat.zero

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            stackedPages
            CanvasContentThumbnail(canvas: selectedCanvas)
                .offset(x: dragOffset * 0.16)
                .shadow(color: .black.opacity(0.09), radius: 8, y: 3)
            if notebook.canvases.count > 1 {
                Text("\(selectedIndex + 1) of \(notebook.canvases.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
            }
        }
        .padding(.trailing, stackDepth)
        .padding(.bottom, stackDepth)
        .contentShape(Rectangle())
        .gesture(previewSwipe)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Canvas previews")
        .accessibilityValue("Canvas \(selectedIndex + 1) of \(notebook.canvases.count)")
        .accessibilityAdjustableAction { direction in
            let translation: CGFloat = direction == .increment ? -80 : 80
            move(to: NotebookCanvasPreviewPaging.destination(
                from: selectedIndex,
                translation: translation,
                canvasCount: notebook.canvases.count
            ))
        }
        .onChange(of: notebook.canvases.count) { _, count in
            selectedIndex = min(selectedIndex, max(count - 1, 0))
        }
    }

    private var selectedCanvas: Canvas {
        notebook.canvases[min(selectedIndex, notebook.canvases.count - 1)]
    }

    private var stackDepth: CGFloat {
        CGFloat(min(notebook.canvases.count - 1, 2)) * 5
    }

    @ViewBuilder
    private var stackedPages: some View {
        ForEach((1..<min(notebook.canvases.count, 3)).reversed(), id: \.self) { depth in
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.secondary.opacity(0.25))
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                .offset(x: CGFloat(depth) * 5, y: CGFloat(depth) * 5)
        }
    }

    private var previewSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .updating($dragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                move(to: NotebookCanvasPreviewPaging.destination(
                    from: selectedIndex,
                    translation: value.translation.width,
                    canvasCount: notebook.canvases.count
                ))
            }
    }

    private func move(to index: Int) {
        withAnimation(isReduceMotionEnabled ? nil : .snappy(duration: 0.22)) {
            selectedIndex = index
        }
    }
}
