import SwiftUI

extension NotebookEditorView {
    @ViewBuilder
    var floatingToolbar: some View {
        if toolbarOrientation == .vertical {
            HStack {
                if isToolbarOnLeft { CanvasToolbarView(editor: self) }
                Spacer()
                if !isToolbarOnLeft { CanvasToolbarView(editor: self) }
            }
            .padding(16)
        } else {
            VStack {
                Spacer()
                CanvasToolbarView(editor: self)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
    }
}
