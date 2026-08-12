import Combine
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notion: NotionIntegrationModel
    @State private var selectedItems: Set<LibraryItemID> = []
    @State private var isSelecting = false

    var body: some View {
        Group {
            if !model.hasRestoredLibrary {
                ProgressView("Opening library")
                    .accessibilityIdentifier("Opening library")
            } else if let notebookID = model.selectedNotebookID, let notebook = model.notebook(notebookID) {
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
            notion.updateOpenNotebookLibrary(library)
        }
        .onChange(of: model.selectedNotebookID, initial: true) { previousID, notebookID in
            if let notebookID {
                notion.openNotebook(notebookID, library: model.library)
            } else {
                notion.closeNotebookMeetingLinks()
                if previousID != nil {
                    notion.scheduleEditingSessionSync(model.library)
                }
            }
        }
        .task {
            await model.restoreLocalLibrary()
            await notion.restore(library: model.library)
            if let notebookID = model.selectedNotebookID {
                notion.openNotebook(notebookID, library: model.library)
            }
        }
        .confirmationDialog(
            "Choose the active Notion meeting",
            isPresented: meetingChoiceBinding,
            titleVisibility: .visible
        ) {
            ForEach(notion.meetingChoices) { meeting in
                Button(meeting.title.isEmpty ? "Untitled meeting" : meeting.title) {
                    notion.chooseMeeting(meeting)
                }
            }
            Button("Not now", role: .cancel) { notion.dismissMeetingChoices() }
        }
        .overlay(alignment: .top) {
            if let message = notion.meetingLinkMessage {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 12)
                    .accessibilityIdentifier("Notion meeting link confirmation")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })
    }

    private var meetingChoiceBinding: Binding<Bool> {
        Binding(
            get: { !notion.meetingChoices.isEmpty },
            set: { if !$0 { notion.dismissMeetingChoices() } }
        )
    }
}
