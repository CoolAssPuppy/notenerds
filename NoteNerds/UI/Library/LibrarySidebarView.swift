import SwiftUI

struct LibrarySidebarView: View {
    @ObservedObject var model: AppModel
    @Binding var isSelecting: Bool
    @Binding var selectedItems: Set<LibraryItemID>
    @AppStorage("canvasToolbarOrientation") private var toolbarOrientation =
        CanvasToolbarOrientation.vertical.rawValue
    @AppStorage("isToolbarOnLeft") private var isToolbarOnLeft = true
    @AppStorage("defaultPaperType") private var defaultPaperTypeRawValue = PaperType.blankWhite.rawValue
    @State private var isConfirmingEmptyTrash = false
    @State private var isDefaultPaperGalleryPresented = false

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
                OutlineGroup(folderTree, children: \.children) { node in
                    LibraryFolderSidebarRow(
                        model: model,
                        folder: node.folder,
                        isCurrent: model.currentFolderID == node.id,
                        isSelecting: isSelecting,
                        isSelected: selectedItems.contains(.folder(node.id)),
                        onActivate: { activate(node.folder) }
                    )
                }
            } header: {
                HStack {
                    Text("Folders")
                    Spacer()
                    Button("New folder", systemImage: "plus", action: model.createFolder)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
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
        .sheet(isPresented: $isDefaultPaperGalleryPresented) {
            PaperGalleryView(initialSelection: defaultPaperType, confirmationTitle: "Done") { paperType in
                defaultPaperTypeRawValue = paperType.rawValue
            }
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
            Menu("Sort", systemImage: AppSymbol.sort) {
                ForEach(LibrarySortMode.allCases, id: \.self) { mode in
                    Button(mode.label) { model.setSortMode(mode) }
                }
            }
            selectionActions
            trashActions
            Divider()
            appSettings
            privacyInformation
        }
    }

    @ViewBuilder
    private var selectionActions: some View {
        if isSelecting && !selectedItems.isEmpty {
            if model.selectedSection == .files {
                Menu("Move", systemImage: AppSymbol.folder) {
                    Button("My Notebooks") { moveSelection(to: nil) }
                    ForEach(model.library.folders.filter { $0.trashedAt == nil }) { folder in
                        Button(folder.name) { moveSelection(to: folder.id) }
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

    private var appSettings: some View {
        Menu("App settings", systemImage: AppSymbol.settings) {
            Picker("Editing tools", selection: $toolbarOrientation) {
                ForEach(CanvasToolbarOrientation.allCases, id: \.self) { orientation in
                    Label(orientation.label, systemImage: orientation.symbol).tag(orientation.rawValue)
                }
            }
            Toggle("Vertical tools on left", isOn: $isToolbarOnLeft)
                .disabled(toolbarOrientation != CanvasToolbarOrientation.vertical.rawValue)
            Button("Default paper", systemImage: "doc.text.image") {
                isDefaultPaperGalleryPresented = true
            }
        }
    }

    private var defaultPaperType: PaperType {
        PaperType(rawValue: defaultPaperTypeRawValue) ?? .blankWhite
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

private struct LibraryFolderNode: Identifiable {
    let folder: Folder
    let children: [LibraryFolderNode]?
    var id: FolderID { folder.id }
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
