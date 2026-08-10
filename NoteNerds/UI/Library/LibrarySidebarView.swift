import SwiftUI

struct LibrarySidebarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notion: NotionIntegrationModel
    @Binding var isSelecting: Bool
    @Binding var selectedItems: Set<LibraryItemID>
    @State private var isConfirmingEmptyTrash = false
    @State private var isAppSettingsPresented = false
    @State private var expandedFolderIDs = Set<FolderID>()

    var body: some View {
        List(selection: selectedSection) {
            Section("Library") {
                ForEach(LibrarySection.allCases) { section in
                    Label(section.rawValue, systemImage: section.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(section)
                        .modifier(TrashSidebarDropTarget(
                            isEnabled: section == .trash,
                            onDrop: moveNotebooksToTrash
                        ))
                }
            }
            Section {
                ForEach(folderTree) { node in
                    LibraryFolderTreeRow(
                        model: model,
                        node: node,
                        expandedFolderIDs: $expandedFolderIDs,
                        isSelecting: isSelecting,
                        selectedItems: selectedItems,
                        onActivate: activate
                    )
                }
            } header: {
                HStack {
                    Text("Folders")
                    Spacer()
                    if model.canCreateFolder && !isSelecting {
                        Button(newFolderLabel, systemImage: "plus", action: createFolder)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                    }
                }
                .textCase(nil)
            }
            if model.selectedSection == .trash && !trashedFolders.isEmpty {
                Section("Folders in Trash") {
                    ForEach(trashedFolders) { folder in
                        LibraryFolderSidebarRow(
                            model: model,
                            folder: folder,
                            isCurrent: false,
                            isSelecting: isSelecting,
                            isSelected: selectedItems.contains(.folder(folder.id)),
                            onActivate: { toggleSelection(.folder(folder.id)) }
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Note Nerds")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { libraryMenu } }
        .confirmationDialog(
            "Delete all items permanently?",
            isPresented: $isConfirmingEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive, action: model.emptyTrash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $isAppSettingsPresented) {
            AppSettingsView(model: model, notion: notion)
        }
    }

    private var folderTree: [LibraryFolderNode] {
        let folders = model.library.folders(sortedBy: model.library.preferredSortMode)
            .filter { $0.trashedAt == nil }
        let foldersByParent = Dictionary(grouping: folders, by: \.parentID)
        func nodes(parentID: FolderID?) -> [LibraryFolderNode] {
            foldersByParent[parentID, default: []].map { folder in
                let childNodes = nodes(parentID: folder.id)
                return LibraryFolderNode(folder: folder, children: childNodes.isEmpty ? nil : childNodes)
            }
        }
        return nodes(parentID: nil)
    }

    private var trashedFolders: [Folder] {
        model.library.folders(sortedBy: .recentlyModified).filter { $0.trashedAt != nil }
    }

    private var newFolderLabel: String {
        model.currentFolderID == nil ? "New folder" : "New subfolder"
    }

    private var selectedSection: Binding<LibrarySection?> {
        Binding(
            get: { model.currentFolderID == nil ? model.selectedSection : nil },
            set: { section in
                guard let section else { return }
                model.selectedSection = section
                model.currentFolderID = nil
                stopSelecting()
            }
        )
    }

    private var libraryMenu: some View {
        Menu("More", systemImage: AppSymbol.more) {
            if [.files, .trash].contains(model.selectedSection) && model.searchQuery.isEmpty {
                Button(isSelecting ? "Done" : "Select", systemImage: isSelecting ? "checkmark" : AppSymbol.select) {
                    isSelecting.toggle()
                    if !isSelecting { selectedItems = [] }
                }
            }
            selectionActions
            trashActions
            Divider()
            Button("App settings", systemImage: AppSymbol.settings) {
                isAppSettingsPresented = true
            }
            privacyInformation
        }
    }

    @ViewBuilder
    private var selectionActions: some View {
        if isSelecting && !selectedItems.isEmpty {
            if model.selectedSection == .files {
                Menu("Move", systemImage: AppSymbol.folder) {
                    Button("My Notebooks") { moveSelection(to: nil) }
                    ForEach(availableMoveDestinations) { folder in
                        Button(moveDestinationName(folder)) { moveSelection(to: folder.id) }
                    }
                }
                Button("Move selected to Trash", systemImage: AppSymbol.trash, role: .destructive) {
                    model.deleteItems(selectedItems)
                    stopSelecting()
                }
            } else if model.selectedSection == .trash {
                Button("Restore selected", systemImage: "arrow.uturn.backward") {
                    model.restoreItems(selectedItems)
                    stopSelecting()
                }
            }
        }
    }

    @ViewBuilder
    private var trashActions: some View {
        if model.selectedSection == .trash && (!trashedFolders.isEmpty || !model.visibleNotebooks.isEmpty) {
            Button("Empty Trash", systemImage: "trash.slash", role: .destructive) {
                isConfirmingEmptyTrash = true
            }
        }
    }

    private var privacyInformation: some View {
        Menu("iCloud and privacy", systemImage: "lock.icloud") {
            Text("Notebooks and organization data sync through your private iCloud database.")
            Text("Handwriting recognition runs on this iPad.")
            if let syncIssue = model.syncIssue { Text(syncIssue) }
        }
    }

    private func activate(_ folder: Folder) {
        if isSelecting {
            toggleSelection(.folder(folder.id))
        } else {
            model.selectedSection = .files
            model.openFolder(folder.id)
        }
    }

    private func createFolder() {
        if let parentID = model.currentFolderID {
            expandedFolderIDs.insert(parentID)
        }
        model.createFolder()
    }

    private func toggleSelection(_ item: LibraryItemID) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }

    private func moveSelection(to folderID: FolderID?) {
        model.moveItems(selectedItems, to: folderID)
        stopSelecting()
    }

    private var availableMoveDestinations: [Folder] {
        model.availableMoveDestinations(for: selectedItems)
            .sorted { lhs, rhs in
                let leftName = moveDestinationName(lhs)
                let rightName = moveDestinationName(rhs)
                if leftName == rightName {
                    return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
                }
                return leftName.localizedStandardCompare(rightName) == .orderedAscending
            }
    }

    private func moveDestinationName(_ folder: Folder) -> String {
        var names = [folder.name]
        var parentID = folder.parentID
        var visited = Set([folder.id])
        while let identifier = parentID,
              visited.insert(identifier).inserted,
              let parent = model.library.folder(id: identifier) {
            names.append(parent.name)
            parentID = parent.parentID
        }
        return names.reversed().joined(separator: " / ")
    }

    private func moveNotebooksToTrash(_ items: [String]) -> Bool {
        let notebookIDs = Set(items.compactMap { item -> LibraryItemID? in
            guard case let .notebook(id) = LibraryDragPayload(encodedValue: item) else { return nil }
            return .notebook(id)
        })
        guard !notebookIDs.isEmpty else { return false }
        model.deleteItems(notebookIDs)
        return true
    }

    private func stopSelecting() {
        selectedItems = []
        isSelecting = false
    }
}

private struct TrashSidebarDropTarget: ViewModifier {
    let isEnabled: Bool
    let onDrop: ([String]) -> Bool
    @State private var isTargeted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .listRowBackground(isTargeted ? Color.red.opacity(0.14) : Color.clear)
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

extension LibrarySection {
    var symbol: String {
        switch self {
        case .files: AppSymbol.allNotes
        case .favorites: AppSymbol.favorites
        case .recents: AppSymbol.recents
        case .trash: AppSymbol.trash
        }
    }
}
