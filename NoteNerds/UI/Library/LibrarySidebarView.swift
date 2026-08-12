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
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
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
        let folders = model.library.folders(sortedBy: .nameAscending)
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

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            if isSelecting && !selectedItems.isEmpty {
                selectionActions
                Divider()
            } else if shouldOfferEmptyTrash {
                Button(role: .destructive) {
                    isConfirmingEmptyTrash = true
                } label: {
                    sidebarFooterLabel("Empty Trash", systemImage: "trash.slash")
                }
                .buttonStyle(.plain)
                Divider()
            }
            if notion.state == .syncing {
                notionSyncStatus
                Divider()
            }
            Button {
                isAppSettingsPresented = true
            } label: {
                sidebarFooterLabel("Settings", systemImage: AppSymbol.settings)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var notionSyncStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: AppSymbol.notionSync)
                .foregroundStyle(.tint)
            Text("Syncing")
            Spacer()
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notion syncing")
    }

    @ViewBuilder
    private var selectionActions: some View {
        if model.selectedSection == .files {
            Menu {
                Button("My Notebooks") { moveSelection(to: nil) }
                ForEach(availableMoveDestinations) { folder in
                    Button(moveDestinationName(folder)) { moveSelection(to: folder.id) }
                }
            } label: {
                sidebarFooterLabel("Move", systemImage: AppSymbol.folder)
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                model.deleteItems(selectedItems)
                stopSelecting()
            } label: {
                sidebarFooterLabel("Move selected to Trash", systemImage: AppSymbol.trash)
            }
            .buttonStyle(.plain)
        } else if model.selectedSection == .trash {
            Button {
                model.restoreItems(selectedItems)
                stopSelecting()
            } label: {
                sidebarFooterLabel("Restore selected", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
        }
    }

    private var shouldOfferEmptyTrash: Bool {
        model.selectedSection == .trash
            && (!trashedFolders.isEmpty || !model.visibleNotebooks.isEmpty)
            && !isSelecting
    }

    private func sidebarFooterLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
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
