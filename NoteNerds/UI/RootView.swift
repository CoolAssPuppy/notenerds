import Combine
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notion: NotionIntegrationModel
    @State private var selectedItems: Set<LibraryItemID> = []
    @State private var isSelecting = false

    var body: some View {
        Group {
            if let notebookID = model.selectedNotebookID, let notebook = model.notebook(notebookID) {
                NavigationStack {
                    NotebookEditorView(model: model, notebook: notebook)
                }
            } else {
                NavigationSplitView {
                    LibrarySidebarView(
                        model: model,
                        notion: notion,
                        isSelecting: $isSelecting,
                        selectedItems: $selectedItems
                    )
                } detail: {
                    LibraryView(
                        model: model,
                        selectedItems: $selectedItems,
                        isSelecting: $isSelecting
                    )
                }
            }
        }
        .environmentObject(notion)
        .alert("Note Nerds", isPresented: errorBinding) {
            Button("OK") { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "")
        }
        .onReceive(model.$library.dropFirst()) { library in
            notion.scheduleAutomaticSync(library)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })
    }
}
