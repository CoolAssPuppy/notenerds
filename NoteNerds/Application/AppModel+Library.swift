import Foundation

extension AppModel {
    func createNotebook(paperType: PaperType? = nil) {
        guard canCreateNotebook else { return }
        let now = Date()
        let selectedPaper = paperType ?? PaperType(
            rawValue: UserDefaults.standard.string(forKey: "defaultPaperType") ?? ""
        ) ?? .blankWhite
        let notebook = Notebook(
            title: "Untitled notebook",
            canvases: [Canvas(title: "Canvas 1", template: selectedPaper, createdAt: now, modifiedAt: now)],
            createdAt: now,
            modifiedAt: now,
            lastOpenedAt: now,
            parentFolderID: currentFolderID
        )
        do {
            try library.addNotebook(notebook, to: currentFolderID)
            searchIndex.update(notebook)
            selectedNotebookID = notebook.id
            persistLibrary()
            persistCheckpoint(notebook)
            enqueueForSync(.createNotebook(notebook), notebookID: notebook.id)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func createFolder() {
        guard canCreateFolder else { return }
        do {
            let folder = try library.createFolder(named: "New folder", in: currentFolderID, at: Date())
            persistLibrary()
            enqueueForSync(.createFolder(folder), notebookID: NotebookID(rawValue: folder.id.rawValue))
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func open(_ notebookID: NotebookID) {
        guard var notebook = library.notebook(id: notebookID) else { return }
        if let selectedNotebookID, selectedNotebookID != notebookID {
            PencilStrokeArchiveCache.shared.removeAll()
        }
        notebook.lastOpenedAt = Date()
        library.updateNotebook(notebook)
        searchIndex.update(notebook)
        selectedNotebookID = notebookID
        persistLibrary()
        Task { [weak self] in
            await self?.loadAssets(for: notebook)
        }
        syncNotebookMetadata(notebookID)
    }

    func closeNotebook() {
        if let selectedNotebookID, let notebook = library.notebook(id: selectedNotebookID) {
            persistCheckpoint(notebook)
        }
        PencilStrokeArchiveCache.shared.removeAll()
        selectedNotebookID = nil
    }
    func openFolder(_ folderID: FolderID) { currentFolderID = folderID }

    func navigateUpFolder() {
        guard let currentFolderID else { return }
        self.currentFolderID = library.folder(id: currentFolderID)?.parentID
    }

    func setSortMode(_ mode: LibrarySortMode) {
        library.preferredSortMode = mode
        persistLibrary()
    }

    func renameNotebook(_ id: NotebookID, to title: String) {
        library.renameNotebook(id, to: title, at: Date())
        refreshSearchIndex(for: id)
        persistLibrary()
        syncNotebookMetadata(id)
    }

    func duplicateNotebook(_ id: NotebookID) {
        do {
            let duplicateID = try library.duplicateNotebook(id, at: Date())
            persistLibrary()
            if let duplicate = library.notebook(id: duplicateID) {
                refreshHandwritingSearch(in: duplicate.id)
                persistCheckpoint(duplicate)
                enqueueForSync(.createNotebook(duplicate), notebookID: duplicateID)
            }
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func addTag(_ tag: String, to notebookID: NotebookID) {
        guard var notebook = library.notebook(id: notebookID) else { return }
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTag.isEmpty else { return }
        notebook.tags.insert(normalizedTag)
        library.updateNotebook(notebook)
        searchIndex.update(notebook)
        persistLibrary()
        syncNotebookMetadata(notebookID)
    }

    func editFolder(
        _ id: FolderID,
        name: String,
        icon: FolderIcon,
        iconColor: FolderIconColor?
    ) {
        do {
            try library.editFolder(
                id,
                name: name,
                icon: icon,
                iconColor: iconColor,
                at: Date()
            )
            persistLibrary()
            syncFolder(id)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func addTag(_ tag: String, to folderID: FolderID) {
        performFolderChange { try $0.addTag(tag, to: folderID, at: Date()) }
        syncFolder(folderID)
    }

    func toggleFolderFavorite(_ id: FolderID) {
        do {
            try library.toggleFolderFavorite(id)
            persistLibrary()
            syncFolder(id)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func deleteFolder(_ id: FolderID) {
        let date = Date()
        performFolderChange { try $0.moveFolderToTrash(id, at: date) }
        leaveInactiveCurrentFolder()
        rebuildSearchIndex()
        enqueueForSync(.trashFolder(id, date: date), notebookID: NotebookID(rawValue: id.rawValue))
    }

    func restoreFolder(_ id: FolderID) {
        let previouslyTrashedNotebookIDs = trashedNotebookIDs
        performFolderChange { try $0.restoreFolder(id) }
        rebuildSearchIndex()
        refreshHandwritingSearchForRestoredNotebooks(previouslyTrashedNotebookIDs)
        syncFolderRestoration(id)
    }

    func permanentlyDeleteFolder(_ id: FolderID) {
        let scope = library.permanentDeletionScope(forFolder: id)
        performFolderChange { try $0.permanentlyDeleteFolder(id) }
        leaveInactiveCurrentFolder()
        rebuildSearchIndex()
        let descendantFolderIDs = scope.folderIDs
            .subtracting([id])
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        let notebookIDs = scope.notebookIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
        for folderID in [id] + descendantFolderIDs {
            enqueueForSync(
                .deleteFolder(folderID),
                notebookID: NotebookID(rawValue: folderID.rawValue)
            )
        }
        for notebookID in notebookIDs {
            enqueueForSync(.deleteNotebook(notebookID), notebookID: notebookID)
        }
    }

    func emptyTrash() {
        let deletedNotebookIDs = library.notebooks.filter { $0.trashedAt != nil }.map(\.id)
        let deletedFolderIDs = library.folders.filter { $0.trashedAt != nil }.map(\.id)
        library.emptyTrash()
        leaveInactiveCurrentFolder()
        rebuildSearchIndex()
        persistLibrary()
        for id in deletedNotebookIDs { enqueueForSync(.deleteNotebook(id), notebookID: id) }
        for id in deletedFolderIDs {
            enqueueForSync(.deleteFolder(id), notebookID: NotebookID(rawValue: id.rawValue))
        }
    }

    func moveNotebook(_ id: NotebookID, to folderID: FolderID?) {
        do {
            try library.moveNotebook(id, to: folderID)
            persistLibrary()
            syncNotebookMetadata(id)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func moveFolder(_ id: FolderID, to parentID: FolderID?) {
        guard canMoveFolder(id, to: parentID) else { return }
        performFolderChange { try $0.moveFolder(id, to: parentID, at: Date()) }
        syncFolder(id)
    }

    func moveItems(_ items: Set<LibraryItemID>, to parentID: FolderID?) {
        guard canMoveItems(items, to: parentID) else { return }
        performFolderChange { try $0.moveItems(items, to: parentID, at: Date()) }
        sync(items)
    }

    func deleteItems(_ items: Set<LibraryItemID>) {
        let date = Date()
        performFolderChange { try $0.moveItemsToTrash(items, at: date) }
        leaveInactiveCurrentFolder()
        rebuildSearchIndex()
        for item in items {
            switch item {
            case let .folder(id):
                enqueueForSync(.trashFolder(id, date: date), notebookID: NotebookID(rawValue: id.rawValue))
            case let .notebook(id): syncNotebookMetadata(id)
            }
        }
    }

    func restoreItems(_ items: Set<LibraryItemID>) {
        let previouslyTrashedNotebookIDs = trashedNotebookIDs
        performFolderChange { try $0.restoreItems(items) }
        rebuildSearchIndex()
        refreshHandwritingSearchForRestoredNotebooks(previouslyTrashedNotebookIDs)
        for item in items {
            switch item {
            case let .folder(id):
                syncFolderRestoration(id)
            case let .notebook(id):
                syncNotebookRestoration(id)
            }
        }
    }

    func toggleFavorite(_ notebookID: NotebookID) {
        library.toggleFavorite(notebookID)
        persistLibrary()
        syncNotebookMetadata(notebookID)
    }

    func delete(_ notebookID: NotebookID) {
        let notebooksBeforeChange = notebooksByID
        library.moveNotebookToTrash(notebookID, at: Date())
        searchIndex.remove(notebookID: notebookID)
        persistLibrary()
        persistChangedNotebookCheckpoints(from: notebooksBeforeChange)
        syncNotebookMetadata(notebookID)
    }

    func restore(_ notebookID: NotebookID) {
        let notebooksBeforeChange = notebooksByID
        let previouslyTrashedNotebookIDs = trashedNotebookIDs
        library.restoreNotebook(notebookID)
        refreshHandwritingSearchForRestoredNotebooks(previouslyTrashedNotebookIDs)
        persistLibrary()
        persistChangedNotebookCheckpoints(from: notebooksBeforeChange)
        syncNotebookRestoration(notebookID)
    }

    func permanentlyDelete(_ notebookID: NotebookID) {
        library.permanentlyDeleteNotebook(notebookID)
        searchIndex.remove(notebookID: notebookID)
        persistLibrary()
        enqueueForSync(.deleteNotebook(notebookID), notebookID: notebookID)
    }

    private func performFolderChange(_ change: (inout LibraryState) throws -> Void) {
        let notebooksBeforeChange = notebooksByID
        do {
            try change(&library)
            persistLibrary()
            persistChangedNotebookCheckpoints(from: notebooksBeforeChange)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private var notebooksByID: [NotebookID: Notebook] {
        library.notebooks.reduce(into: [:]) { notebooks, notebook in
            notebooks[notebook.id] = notebook
        }
    }

    private func persistChangedNotebookCheckpoints(
        from previousNotebooks: [NotebookID: Notebook]
    ) {
        for notebook in library.notebooks where previousNotebooks[notebook.id] != notebook {
            persistCheckpoint(notebook)
        }
    }

    private func rebuildSearchIndex() {
        searchIndex = LibrarySearchIndex()
        for notebook in library.notebooks { searchIndex.update(notebook) }
    }

    private var trashedNotebookIDs: Set<NotebookID> {
        Set(library.notebooks.lazy.filter { $0.trashedAt != nil }.map(\.id))
    }

    private func refreshHandwritingSearchForRestoredNotebooks(
        _ previouslyTrashedNotebookIDs: Set<NotebookID>
    ) {
        for notebook in library.notebooks where notebook.trashedAt == nil
            && previouslyTrashedNotebookIDs.contains(notebook.id) {
            refreshHandwritingSearch(in: notebook.id)
        }
    }

    func leaveInactiveCurrentFolder() {
        guard let currentFolderID else { return }
        guard let currentFolder = library.folder(id: currentFolderID) else {
            self.currentFolderID = nil
            return
        }
        guard currentFolder.trashedAt != nil else { return }
        self.currentFolderID = currentFolder.parentID.flatMap { parentID in
            guard library.folder(id: parentID)?.trashedAt == nil else { return nil }
            return parentID
        }
    }
}
