import SwiftUI

extension NotebookEditorView {
    var floatingToolbar: some View {
        GeometryReader { proxy in
            CanvasToolbarView(editor: self)
                .fixedSize()
                .offset(toolbarDragTranslation)
                .scaleEffect(isToolbarDragging ? 1.025 : 1)
                .simultaneousGesture(toolbarDockGesture(in: proxy.size))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: toolbarAlignment
                )
                .padding(16)
                .animation(toolbarDockAnimation, value: toolbarOrientation)
                .animation(toolbarDockAnimation, value: isToolbarOnLeft)
                .animation(toolbarLiftAnimation, value: isToolbarDragging)
        }
        .coordinateSpace(name: "canvasToolbarArea")
    }

    private var toolbarAlignment: Alignment {
        guard toolbarOrientation == .vertical else { return .top }
        return isToolbarOnLeft ? .leading : .trailing
    }

    private var toolbarDockAnimation: Animation? {
        isReduceMotionEnabled ? .linear(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.84)
    }

    private var toolbarLiftAnimation: Animation? {
        isReduceMotionEnabled ? nil : .spring(response: 0.24, dampingFraction: 0.76)
    }

    private func toolbarDockGesture(in availableSize: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.22, maximumDistance: 14)
            .sequenced(
                before: DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named("canvasToolbarArea")
                )
            )
            .updating($toolbarDragTranslation) { value, translation, _ in
                guard case let .second(true, drag?) = value else { return }
                translation = drag.translation
            }
            .updating($isToolbarDragging) { value, isDragging, _ in
                guard case .second(true, _) = value else { return }
                isDragging = true
            }
            .onEnded { value in
                guard case let .second(true, drag?) = value else { return }
                dockToolbar(at: drag.predictedEndLocation, in: availableSize)
            }
    }

    private func dockToolbar(at location: CGPoint, in availableSize: CGSize) {
        let destination = CanvasToolbarDocking.destination(for: location, in: availableSize)
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(toolbarDockAnimation) {
            toolbarOrientationRawValue = destination.orientation.rawValue
            isToolbarOnLeft = destination.isOnLeft
        }
    }
}
