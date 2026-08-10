import SwiftUI
import UniformTypeIdentifiers

struct FolderEditorView: View {
    private enum IconType: String, CaseIterable, Identifiable {
        case symbol = "Symbol"
        case emoji = "Emoji"
        case image = "Image"

        var id: Self { self }
    }

    private struct PaletteColor: Identifiable {
        let name: String
        let value: FolderIconColor?

        var id: String { name }

        static var choices: [PaletteColor] {
            [
                PaletteColor(name: "App color", value: nil),
                PaletteColor(name: "Red", value: FolderIconColor(red: 0.95, green: 0.24, blue: 0.2, alpha: 1)),
                PaletteColor(name: "Orange", value: FolderIconColor(red: 1, green: 0.55, blue: 0.1, alpha: 1)),
                PaletteColor(name: "Yellow", value: FolderIconColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1)),
                PaletteColor(name: "Green", value: FolderIconColor(red: 0.2, green: 0.7, blue: 0.35, alpha: 1)),
                PaletteColor(name: "Blue", value: FolderIconColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 1)),
                PaletteColor(name: "Purple", value: FolderIconColor(red: 0.55, green: 0.3, blue: 0.9, alpha: 1)),
                PaletteColor(name: "Pink", value: FolderIconColor(red: 0.95, green: 0.3, blue: 0.58, alpha: 1)),
                PaletteColor(name: "Gray", value: FolderIconColor(red: 0.45, green: 0.47, blue: 0.5, alpha: 1))
            ]
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var iconType: IconType
    @State private var selectedSymbol: FolderSystemSymbol
    @State private var selectedColor: FolderIconColor?
    @State private var emojiText: String
    @State private var customPNG: FolderIconPNG?
    @State private var isChoosingImage = false
    @State private var isImportingImage = false
    @State private var importError: String?

    private let onSave: (String, FolderIcon, FolderIconColor?) -> Void

    init(
        folder: Folder,
        onSave: @escaping (String, FolderIcon, FolderIconColor?) -> Void
    ) {
        let initialType: IconType
        let initialSymbol: FolderSystemSymbol
        let initialEmoji: String
        let initialPNG: FolderIconPNG?
        switch folder.icon {
        case let .systemSymbol(symbol):
            initialType = .symbol
            initialSymbol = symbol
            initialEmoji = ""
            initialPNG = nil
        case let .emoji(emoji):
            initialType = .emoji
            initialSymbol = .folder
            initialEmoji = emoji.value
            initialPNG = nil
        case let .customPNG(image):
            initialType = .image
            initialSymbol = .folder
            initialEmoji = ""
            initialPNG = image
        }
        _name = State(initialValue: folder.name)
        _iconType = State(initialValue: initialType)
        _selectedSymbol = State(initialValue: initialSymbol)
        _selectedColor = State(initialValue: folder.iconColor)
        _emojiText = State(initialValue: initialEmoji)
        _customPNG = State(initialValue: initialPNG)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        FolderIconView(icon: previewIcon, color: previewColor, size: 44)
                        TextField("Folder name", text: $name)
                            .textInputAutocapitalization(.words)
                    }
                    .padding(.vertical, 4)
                }
                Section("Icon") {
                    Picker("Folder icon type", selection: $iconType) {
                        ForEach(IconType.allCases) { iconType in
                            Text(iconType.rawValue).tag(iconType)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("Folder icon type")
                    iconOptions
                }
            }
            .navigationTitle("Edit folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $isChoosingImage,
                allowedContentTypes: [.png, .svg],
                allowsMultipleSelection: false,
                onCompletion: importImage
            )
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var iconOptions: some View {
        switch iconType {
        case .symbol:
            symbolGrid
            colorChoices
        case .emoji:
            TextField("Emoji", text: $emojiText)
                .font(.title2)
            if !emojiText.isEmpty, (try? FolderEmoji(emojiText)) == nil {
                Text("Enter one emoji.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        case .image:
            if let customPNG {
                FolderIconView(icon: .customPNG(customPNG), color: nil, size: 64)
                    .frame(maxWidth: .infinity)
            }
            Button("Choose PNG or SVG", systemImage: "photo.on.rectangle") {
                isChoosingImage = true
            }
            .disabled(isImportingImage)
            if isImportingImage {
                ProgressView("Preparing image")
            }
            if let importError {
                Text(importError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
            ForEach(FolderSystemSymbol.allCases, id: \.self) { symbol in
                Button {
                    selectedSymbol = symbol
                } label: {
                    Image(systemName: symbol.rawValue)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(
                            selectedSymbol == symbol ? Color.accentColor.opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol.displayName)
                .accessibilityAddTraits(selectedSymbol == symbol ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var colorChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color").font(.subheadline).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(PaletteColor.choices) { choice in
                        Button {
                            selectedColor = choice.value
                        } label: {
                            Circle()
                                .fill(choice.value?.swiftUIColor ?? Color.accentColor)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if selectedColor == choice.value {
                                        Circle().stroke(Color.primary, lineWidth: 2)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.name)
                        .accessibilityAddTraits(selectedColor == choice.value ? .isSelected : [])
                    }
                }
            }
            ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { selectedColor?.swiftUIColor ?? Color.accentColor },
            set: { selectedColor = FolderIconColor(swiftUIColor: $0) }
        )
    }

    private var proposedIcon: FolderIcon? {
        switch iconType {
        case .symbol: .systemSymbol(selectedSymbol)
        case .emoji: (try? FolderEmoji(emojiText)).map(FolderIcon.emoji)
        case .image: customPNG.map(FolderIcon.customPNG)
        }
    }

    private var previewIcon: FolderIcon {
        proposedIcon ?? .standard
    }

    private var previewColor: FolderIconColor? {
        iconType == .symbol ? selectedColor : nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && proposedIcon != nil
            && !isImportingImage
    }

    private func save() {
        guard let proposedIcon else { return }
        onSave(name, proposedIcon, iconType == .symbol ? selectedColor : nil)
        dismiss()
    }

    private func importImage(_ result: Result<[URL], any Error>) {
        guard !isImportingImage else { return }
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result { importError = error.localizedDescription }
            return
        }
        isImportingImage = true
        importError = nil
        Task { @MainActor in
            defer { isImportingImage = false }
            do {
                let icon = try await FolderIconImporter().importIcon(at: url)
                guard case let .customPNG(image) = icon else { return }
                customPNG = image
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}
