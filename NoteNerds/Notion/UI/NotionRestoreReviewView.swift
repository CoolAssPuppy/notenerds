import SwiftUI

struct NotionRestoreReviewView: View {
    let candidates: [NotionRestoreCandidate]
    @Binding var choices: [NotebookID: NotionRestoreChoice]
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.title)
                        Text(candidate.reason.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Restore choice", selection: choiceBinding(for: candidate)) {
                        ForEach(candidate.availableChoices, id: \.self) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .accessibilityLabel(candidate.title)
                .accessibilityValue(choiceBinding(for: candidate).wrappedValue.label)
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No notebooks to restore",
                        systemImage: "checkmark.icloud"
                    )
                }
            }
            .navigationTitle("Restore from Notion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore", action: onRestore)
                        .disabled(candidates.isEmpty)
                }
            }
        }
    }

    private func choiceBinding(for candidate: NotionRestoreCandidate) -> Binding<NotionRestoreChoice> {
        Binding(
            get: { choices[candidate.notebookID] ?? candidate.defaultChoice },
            set: { choices[candidate.notebookID] = $0 }
        )
    }
}

private extension NotionRestoreCandidate {
    var availableChoices: [NotionRestoreChoice] {
        reason == .missingLocally ? [.useNotion] : [.keepLocal, .useNotion, .importCopy]
    }
}

private extension NotionRestoreChoice {
    var label: String {
        switch self {
        case .keepLocal: "Keep local"
        case .useNotion: "Use Notion"
        case .importCopy: "Import a copy"
        }
    }
}

private extension NotionRestoreCandidateReason {
    var label: String {
        switch self {
        case .missingLocally: "Missing on this device"
        case .newerInNotion: "Newer copy in Notion"
        case .sameOrOlderInNotion: "Local copy is current"
        }
    }
}
