import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notion: NotionIntegrationModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultPaperType") private var defaultPaperTypeRawValue = PaperType.blankWhite.rawValue
    @State private var isPaperGalleryPresented = false
    @State private var isConfirmingDisconnect = false
    @State private var isRestoreReviewPresented = false
    @State private var restoreChoices: [NotebookID: NotionRestoreChoice] = [:]

    var body: some View {
        NavigationStack {
            Form {
                paperSection
                notionSection
                privacySection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .sheet(isPresented: $isPaperGalleryPresented) {
                PaperGalleryView(initialSelection: defaultPaperType, confirmationTitle: "Done") {
                    defaultPaperTypeRawValue = $0.rawValue
                }
            }
            .sheet(isPresented: $isRestoreReviewPresented) {
                NotionRestoreReviewView(
                    candidates: notion.restoreCandidates,
                    choices: $restoreChoices,
                    onRestore: restoreSelectedNotebooks
                )
            }
            .confirmationDialog(
                "Disconnect Notion?",
                isPresented: $isConfirmingDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) { Task { await notion.disconnect() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your notebooks will remain in Notion. Note Nerds will remove its device credentials.")
            }
        }
    }

    private var paperSection: some View {
        Section("Paper") {
            Button("Default paper", systemImage: "doc.text.image") {
                isPaperGalleryPresented = true
            }
        }
    }

    @ViewBuilder
    private var notionSection: some View {
        Section {
            switch notion.state {
            case .unavailable:
                Label("Notion is unavailable in this build", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            case .disconnected:
                Button("Connect to Notion", systemImage: "link") {
                    Task { await notion.connect() }
                }
            case .connecting:
                progressRow("Connecting to Notion")
            case let .connected(workspaceName):
                connectedNotionRows(workspaceName: workspaceName, isSyncing: false)
            case .selectingDestination:
                progressRow("Creating database")
            case .syncing:
                connectedNotionRows(
                    workspaceName: notion.workspaceName ?? "Connected",
                    isSyncing: true
                )
            case .preparingRestore:
                progressRow("Checking Notion notebooks")
            case .reviewingRestore:
                progressRow("Reviewing restore")
            case .restoring:
                progressRow("Restoring notebooks")
            case .disconnecting:
                progressRow("Disconnecting")
            case .actionNeeded:
                Label(
                    notion.failureMessage ?? "Notion needs attention.",
                    systemImage: "exclamationmark.triangle"
                )
                Button("Try again") { Task { await notion.restore() } }
            }
        } header: {
            Text("Notion")
        } footer: {
            Text("Note Nerds sends notebooks to Notion only after you connect and choose a page.")
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Label("iCloud sync uses your private CloudKit database", systemImage: "lock.icloud")
            Label("Handwriting recognition runs on this iPad", systemImage: "hand.draw")
            if let syncIssue = model.syncIssue {
                Label(syncIssue, systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defaultPaperType: PaperType {
        PaperType(rawValue: defaultPaperTypeRawValue) ?? .blankWhite
    }

    private func progressRow(_ title: String) -> some View {
        HStack {
            ProgressView()
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func connectedNotionRows(workspaceName: String, isSyncing: Bool) -> some View {
        LabeledContent("Workspace", value: workspaceName)
        NavigationLink {
            NotionDestinationPickerView(model: notion, library: model.library)
        } label: {
            LabeledContent(
                "Notebook database",
                value: notion.destination == nil ? "Choose location" : "Connected"
            )
        }
        if notion.destination != nil {
            LabeledContent("AI Meeting Notes links") {
                Text(notion.isMeetingLinkPermissionRequired ? "Share meeting notes" : "Automatic")
                    .foregroundStyle(
                        notion.isMeetingLinkPermissionRequired ? Color.orange : Color.secondary
                    )
            }
            if notion.isMeetingLinkPermissionRequired {
                Text("Share the AI Meeting Notes page or its parent with Note Nerds in Notion.")
                    .foregroundStyle(.secondary)
            }
            if isSyncing {
                progressRow("Sending notebooks to Notion")
            }
            Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                Task { await notion.sync(model.library) }
            }
            .disabled(isSyncing)
            if let summary = notion.lastSyncSummary {
                Text(summary)
                    .foregroundStyle(.secondary)
            }
            Button("Restore from Notion", systemImage: "arrow.down.doc") {
                Task { await prepareRestore() }
            }
            .disabled(isSyncing)
        }
        Button("Disconnect Notion", systemImage: "link.badge.minus", role: .destructive) {
            isConfirmingDisconnect = true
        }
        .disabled(isSyncing)
    }

    private func prepareRestore() async {
        let candidates = await notion.prepareRestore(local: model.library)
        guard notion.state == .reviewingRestore else { return }
        restoreChoices = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.notebookID, $0.defaultChoice) }
        )
        isRestoreReviewPresented = true
    }

    private func restoreSelectedNotebooks() {
        guard let restored = notion.completeRestore(
            local: model.library,
            choices: restoreChoices
        ) else { return }
        isRestoreReviewPresented = false
        Task { await model.replaceLibraryAfterNotionRestore(restored) }
    }
}
