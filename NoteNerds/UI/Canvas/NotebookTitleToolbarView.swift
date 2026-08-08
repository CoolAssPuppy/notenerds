import SwiftUI
import UIKit

struct NotebookTitleToolbarView: View {
    let notebookTitle: String
    let canvasTitle: String
    let canvasIndex: Int
    let canvasCount: Int
    let onRename: (String) -> Void
    let onOpenBrowser: () -> Void
    @State private var draftTitle: String
    @State private var isEditing = false

    init(
        notebookTitle: String,
        canvasTitle: String,
        canvasIndex: Int,
        canvasCount: Int,
        onRename: @escaping (String) -> Void,
        onOpenBrowser: @escaping () -> Void
    ) {
        self.notebookTitle = notebookTitle
        self.canvasTitle = canvasTitle
        self.canvasIndex = canvasIndex
        self.canvasCount = canvasCount
        self.onRename = onRename
        self.onOpenBrowser = onOpenBrowser
        _draftTitle = State(initialValue: notebookTitle)
    }

    var body: some View {
        VStack(spacing: 1) {
            titleControl
            Button(action: onOpenBrowser) {
                Text("\(canvasTitle), \(canvasIndex + 1) of \(canvasCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Canvas browser")
            .accessibilityValue("\(canvasIndex + 1) of \(canvasCount)")
        }
        .onChange(of: notebookTitle) { _, newTitle in
            if !isEditing { draftTitle = newTitle }
        }
    }

    @ViewBuilder
    private var titleControl: some View {
        if isEditing {
            InlineTitleField(
                text: $draftTitle,
                onCommit: commit,
                onCancel: cancel,
                accessibilityLabel: "Notebook title"
            )
                .frame(minWidth: 140, idealWidth: 220, maxWidth: 280)
        } else {
            Button(action: beginEditing) {
                Text(notebookTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notebook title, \(notebookTitle)")
            .accessibilityHint("Edits the notebook title in place")
        }
    }

    private func beginEditing() {
        draftTitle = notebookTitle
        isEditing = true
    }

    private func commit(_ proposedTitle: String) {
        let cleanTitle = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        guard !cleanTitle.isEmpty else {
            draftTitle = notebookTitle
            return
        }
        draftTitle = cleanTitle
        guard cleanTitle != notebookTitle else { return }
        Task { @MainActor in
            await Task.yield()
            onRename(cleanTitle)
        }
    }

    private func cancel() {
        draftTitle = notebookTitle
        isEditing = false
    }
}

struct InlineTitleField: UIViewRepresentable {
    @Binding var text: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    let accessibilityLabel: String
    var textAlignment: NSTextAlignment = .center

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    func makeUIView(context: Context) -> InlineTitleTextField {
        let textField = InlineTitleTextField()
        textField.text = text
        textField.font = .preferredFont(forTextStyle: .headline)
        textField.textAlignment = textAlignment
        textField.borderStyle = .none
        textField.clearButtonMode = .never
        textField.returnKeyType = .done
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        textField.onEscape = context.coordinator.cancel
        textField.accessibilityLabel = accessibilityLabel
        return textField
    }

    func updateUIView(_ textField: InlineTitleTextField, context: Context) {
        if textField.text != text { textField.text = text }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        private var text: Binding<String>
        private let onCommit: (String) -> Void
        private let onCancel: () -> Void
        private var isFinishing = false

        init(
            text: Binding<String>,
            onCommit: @escaping (String) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        @objc func textChanged(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard !isFinishing else { return false }
            isFinishing = true
            let proposedTitle = textField.text ?? ""
            text.wrappedValue = proposedTitle
            onCommit(proposedTitle)
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard !isFinishing else { return }
            isFinishing = true
            let proposedTitle = textField.text ?? ""
            text.wrappedValue = proposedTitle
            onCommit(proposedTitle)
        }

        func cancel() {
            guard !isFinishing else { return }
            isFinishing = true
            onCancel()
        }
    }
}

final class InlineTitleTextField: UITextField {
    var onEscape: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, becomeFirstResponder() else { return }
            selectAll(nil)
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        let cancelCommand = UIKeyCommand(
            input: UIKeyCommand.inputEscape,
            modifierFlags: [],
            action: #selector(cancelEditing)
        )
        cancelCommand.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [cancelCommand]
    }

    @objc private func cancelEditing() {
        onEscape?()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(cancelEditing) || super.canPerformAction(action, withSender: sender)
    }
}
