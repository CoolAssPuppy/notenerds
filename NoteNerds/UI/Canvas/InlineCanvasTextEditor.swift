import PencilKit
import UIKit

/// Tells the two decisions in the text toolbar apart at a glance.
///
/// Keep and discard used to be two grey glyphs of the same weight next to each
/// other, so the only thing separating them was the shape of a small symbol.
enum InlineTextEditorButtonRole {
    case confirm
    case cancel
    case plain

    var backgroundColor: UIColor {
        switch self {
        case .confirm: .tintColor
        case .cancel: .tertiarySystemFill
        case .plain: .clear
        }
    }

    var foregroundColor: UIColor {
        switch self {
        case .confirm: .white
        case .cancel: .secondaryLabel
        case .plain: .tintColor
        }
    }
}

@MainActor
final class InlineCanvasTextEditor: UIView, UITextViewDelegate {
    var sessionID: ObjectID?
    private var textBlock: TextBlock
    private let onCommit: (TextBlock) -> Void
    private let onCancel: () -> Void
    private let textView = InlineTextView()
    private var isFinishingEditing = false
    private let fontButton = UIButton(type: .system)
    private let sizeLabel = UILabel()
    private let alignmentControl = UISegmentedControl(items: [
        UIImage(systemName: "text.alignleft") as Any,
        UIImage(systemName: "text.aligncenter") as Any,
        UIImage(systemName: "text.alignright") as Any
    ])

    init(
        session: CanvasTextEditingSession,
        onCommit: @escaping (TextBlock) -> Void,
        onCancel: @escaping () -> Void
    ) {
        textBlock = session.textBlock
        self.onCommit = onCommit
        self.onCancel = onCancel
        super.init(frame: Self.editorFrame(for: session.textBlock.frame))
        configureView()
        configureToolbar()
        configureTextView()
        focusTextView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private static func editorFrame(for textFrame: CanvasRect) -> CGRect {
        CGRect(
            x: textFrame.minX,
            y: textFrame.minY - 44,
            width: textFrame.size.width,
            height: textFrame.size.height + 44
        )
    }

    private func configureView() {
        backgroundColor = .clear
        accessibilityIdentifier = "InlineCanvasTextEditor"
    }

    private func configureToolbar() {
        let toolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        toolbar.layer.cornerRadius = 10
        toolbar.clipsToBounds = true
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)

        let stack = UIStackView(arrangedSubviews: [
            button(symbol: "xmark", label: "Cancel text editing", role: .cancel, action: cancel),
            fontButton,
            alignmentControl,
            button(symbol: "minus", label: "Decrease text size", action: decreaseSize),
            sizeLabel,
            button(symbol: "plus", label: "Increase text size", action: increaseSize),
            button(symbol: "checkmark", label: "Finish text editing", role: .confirm, action: commit)
        ])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.contentView.addSubview(stack)

        alignmentControl.selectedSegmentIndex = alignmentIndex
        alignmentControl.accessibilityLabel = "Text alignment"
        alignmentControl.addTarget(self, action: #selector(alignmentChanged), for: .valueChanged)
        configureFontButton()
        updateSizeLabel()

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 38),
            stack.leadingAnchor.constraint(equalTo: toolbar.contentView.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: toolbar.contentView.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: toolbar.contentView.centerYAnchor)
        ])
    }

    private func configureTextView() {
        textView.text = textBlock.text
        textView.font = textBlock.uiFont
        textView.textAlignment = textAlignment
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        textView.onEscape = { [weak self] in self?.cancel() }
        textView.returnKeyType = .done
        textView.enablesReturnKeyAutomatically = true
        textView.accessibilityLabel = "Canvas text editor"
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        resizeForContent()
    }

    private func button(
        symbol: String,
        label: String,
        role: InlineTextEditorButtonRole = .plain,
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.background.backgroundColor = role.backgroundColor
        configuration.baseForegroundColor = role.foregroundColor
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            weight: role == .plain ? .regular : .semibold
        )
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = label
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func focusTextView() {
        Task { @MainActor [weak self] in
            self?.textView.becomeFirstResponder()
        }
    }

    private func cancel() {
        guard !isFinishingEditing else { return }
        isFinishingEditing = true
        onCancel()
        textView.resignFirstResponder()
    }

    func commitIfEditing() {
        guard !isFinishingEditing else { return }
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancel()
        } else {
            commit()
        }
    }

    private func commit() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            cancel()
            return
        }
        guard !isFinishingEditing else { return }
        isFinishingEditing = true
        textBlock.text = text
        onCommit(textBlock)
        textView.resignFirstResponder()
    }

    private func decreaseSize() {
        textBlock.fontSize = max(12, textBlock.fontSize - 1)
        applyFormatting()
    }

    private func increaseSize() {
        textBlock.fontSize = min(72, textBlock.fontSize + 1)
        applyFormatting()
    }

    @objc private func alignmentChanged() {
        textBlock.alignment = [TextAlignment.left, .center, .right][alignmentControl.selectedSegmentIndex]
        applyFormatting()
    }

    private func applyFormatting() {
        textView.font = textBlock.uiFont
        textView.textAlignment = textAlignment
        configureFontMenu()
        updateSizeLabel()
        resizeForContent()
    }

    func textViewDidChange(_ textView: UITextView) {
        resizeForContent()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard !isFinishingEditing else { return }
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancel()
        } else {
            commit()
        }
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        switch text {
        case "\n":
            commit()
            return false
        case UIKeyCommand.inputEscape:
            cancel()
            return false
        default:
            return true
        }
    }

    private func configureFontButton() {
        fontButton.setImage(UIImage(systemName: "textformat"), for: .normal)
        fontButton.accessibilityLabel = "Font"
        fontButton.showsMenuAsPrimaryAction = true
        fontButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        fontButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        configureFontMenu()
    }

    private func configureFontMenu() {
        let defaultAction = UIAction(
            title: "System",
            state: textBlock.fontName == nil ? .on : .off
        ) { [weak self] _ in
            self?.textBlock.fontName = nil
            self?.applyFormatting()
        }
        let groupedFonts = Dictionary(grouping: SystemFontCatalog.availableFonts, by: \.familyName)
        let familyMenus = groupedFonts.keys.sorted().map { familyName in
            let actions = groupedFonts[familyName, default: []].map { font in
                UIAction(
                    title: font.displayName,
                    state: textBlock.fontName == font.postScriptName ? .on : .off
                ) { [weak self] _ in
                    self?.textBlock.fontName = font.postScriptName
                    self?.applyFormatting()
                }
            }
            return UIMenu(title: familyName, children: actions)
        }
        fontButton.menu = UIMenu(title: "Font", children: [defaultAction] + familyMenus)
    }

    private func resizeForContent() {
        let fittingSize = textView.sizeThatFits(
            CGSize(width: textBlock.frame.size.width, height: CGFloat.greatestFiniteMagnitude)
        )
        let textHeight = max(44, ceil(fittingSize.height))
        textBlock.frame.size.height = textHeight
        frame.size.height = textHeight + 44
    }

    private func updateSizeLabel() {
        sizeLabel.text = "\(Int(textBlock.fontSize))"
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        sizeLabel.textAlignment = .center
        sizeLabel.accessibilityLabel = "Text size"
        sizeLabel.accessibilityValue = "\(Int(textBlock.fontSize)) points"
        sizeLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private var alignmentIndex: Int {
        switch textBlock.alignment {
        case .left: 0
        case .center: 1
        case .right: 2
        }
    }

    private var textAlignment: NSTextAlignment {
        switch textBlock.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}

private final class InlineTextView: UITextView {
    var onEscape: (() -> Void)?

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
        if action == #selector(cancelEditing) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let hasEscapeKey = presses.contains { press in
            press.key?.keyCode == .keyboardEscape ||
                press.key?.charactersIgnoringModifiers == UIKeyCommand.inputEscape
        }
        guard hasEscapeKey else {
            super.pressesBegan(presses, with: event)
            return
        }
        onEscape?()
    }
}

extension PencilCanvasView {
    func updateInlineTextEditor(in canvasView: PKCanvasView, coordinator: Coordinator) {
        guard let textEditingSession else {
            coordinator.inlineTextEditor?.removeFromSuperview()
            coordinator.inlineTextEditor = nil
            return
        }
        guard coordinator.inlineTextEditor?.sessionID != textEditingSession.textBlock.id else { return }
        coordinator.inlineTextEditor?.removeFromSuperview()
        let editor = InlineCanvasTextEditor(
            session: textEditingSession,
            onCommit: actions.onCommitText,
            onCancel: actions.onCancelText
        )
        editor.sessionID = textEditingSession.textBlock.id
        canvasView.addSubview(editor)
        coordinator.inlineTextEditor = editor
    }
}
