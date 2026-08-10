import SwiftUI

enum LibraryDragPayload: Equatable {
    case folder(FolderID)
    case notebook(NotebookID)

    init?(encodedValue: String) {
        let parts = encodedValue.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let rawID = UUID(uuidString: String(parts[1])) else { return nil }

        switch parts[0] {
        case "folder": self = .folder(FolderID(rawValue: rawID))
        case "notebook": self = .notebook(NotebookID(rawValue: rawID))
        default: return nil
        }
    }

    var encodedValue: String {
        switch self {
        case let .folder(id): "folder:\(id.rawValue.uuidString)"
        case let .notebook(id): "notebook:\(id.rawValue.uuidString)"
        }
    }
}

struct LibraryFolderSidebarRow: View {
    @ObservedObject var model: AppModel
    let folder: Folder
    let isCurrent: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let onActivate: () -> Void
    @State private var isEditing = false
    @State private var isAddingTag = false
    @State private var proposedTag = ""
    @State private var isConfirmingPermanentDelete = false

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 10) {
                FolderIconView(icon: folder.icon, color: folder.iconColor)
                    .opacity(folder.trashedAt == nil ? 1 : 0.55)
                    .overlay(alignment: .bottomTrailing) {
                        if folder.trashedAt != nil {
                            Image(systemName: "minus.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                Text(folder.name).lineLimit(1)
                Spacer(minLength: 4)
                if folder.isFavorite { Image(systemName: "star.fill").font(.caption) }
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.16) : Color.clear)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isSelecting && isSelected ? .isSelected : [])
        .contextMenu { folderActions }
        .modifier(FolderSidebarDragAndDrop(
            isEnabled: !isSelecting && folder.trashedAt == nil,
            payload: LibraryDragPayload.folder(folder.id).encodedValue,
            onDrop: handleDrop
        ))
        .sheet(isPresented: $isEditing) {
            FolderEditorView(folder: folder) { name, icon, color in
                model.editFolder(folder.id, name: name, icon: icon, iconColor: color)
            }
        }
        .alert("Add tag", isPresented: $isAddingTag) {
            TextField("Tag", text: $proposedTag)
            Button("Add") { model.addTag(proposedTag, to: folder.id) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \(folder.name) permanently?",
            isPresented: $isConfirmingPermanentDelete,
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) { model.permanentlyDeleteFolder(folder.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The folder and everything inside it will be deleted.")
        }
    }

    private var accessibilityValue: String {
        guard isSelecting else { return folder.icon.accessibilityDescription }
        let selectionState = isSelected ? "Selected" : "Not selected"
        return "\(folder.icon.accessibilityDescription), \(selectionState)"
    }

    private var accessibilityLabel: String {
        folder.parentID == nil ? "Folder, \(folder.name)" : "Subfolder, \(folder.name)"
    }

    private var accessibilityHint: String {
        if isSelecting { return "Toggles folder selection" }
        return folder.trashedAt == nil ? "Shows notebooks in this folder" : "Folder in Trash"
    }

    private func handleDrop(_ items: [String]) -> Bool {
        for item in items {
            guard let payload = LibraryDragPayload(encodedValue: item) else { continue }
            switch payload {
            case let .notebook(id):
                model.moveNotebook(id, to: folder.id)
                return true
            case let .folder(id):
                guard model.canMoveFolder(id, to: folder.id) else { continue }
                model.moveFolder(id, to: folder.id)
                return true
            }
        }
        return false
    }

    @ViewBuilder
    private var folderActions: some View {
        if folder.trashedAt == nil {
            Button("Edit folder", systemImage: "pencil") {
                isEditing = true
            }
            Button(folder.isFavorite ? "Remove favorite" : "Favorite", systemImage: "star") {
                model.toggleFolderFavorite(folder.id)
            }
            Button("Add tag", systemImage: "tag") { isAddingTag = true }
            Button("Move to Trash", systemImage: AppSymbol.trash, role: .destructive) {
                model.deleteFolder(folder.id)
            }
        } else {
            Button("Restore", systemImage: "arrow.uturn.backward") { model.restoreFolder(folder.id) }
            Button("Delete permanently", systemImage: AppSymbol.trash, role: .destructive) {
                isConfirmingPermanentDelete = true
            }
        }
    }
}

private struct FolderSidebarDragAndDrop: ViewModifier {
    let isEnabled: Bool
    let payload: String
    let onDrop: ([String]) -> Bool
    @State private var isTargeted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .draggable(payload)
                .background(isTargeted ? Color.accentColor.opacity(0.18) : Color.clear)
                .dropDestination(for: String.self) { items, _ in
                    onDrop(items)
                } isTargeted: { isTargeted in
                    self.isTargeted = isTargeted
                }
        } else {
            content
        }
    }
}
