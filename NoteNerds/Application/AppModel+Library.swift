import Foundation

extension AppModel {
    func createNotebook(paperType: PaperType? = nil) {
        let now = Date()
        let selectedPaper = paperType ?? PaperType(
            rawValue: UserDefaults.standard.string(forKey: "defaultPaperType") ?? ""
        ) ?? .blankWhite
        let notebook = Notebook(
            title: "Untitled notebook",
            canvases: [Canvas(title: "Canvas 1", template: selectedPaper, createdAt: now, modifiedAt: now)],
            createdAt: now,
            modifiedAt: now,
            lastOpenedAt: now
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
        notebook.lastOpenedAt = Date()
        library.updateNotebook(notebook)
        searchIndex.update(notebook)
        selectedNotebookID = notebookID
        persistLibrary()
        syncNotebookMetadata(notebookID)
    }

    func closeNotebook() { selectedNotebookID = nil }
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

    func renameFolder(_ id: FolderID, to name: String) {
        do {
            try library.renameFolder(id, to: name, at: Date())
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
        rebuildSearchIndex()
        enqueueForSync(.trashFolder(id, date: date), notebookID: NotebookID(rawValue: id.rawValue))
    }

    func restoreFolder(_ id: FolderID) {
        performFolderChange { try $0.restoreFolder(id) }
        rebuildSearchIndex()
        enqueueForSync(.restoreFolder(id), notebookID: NotebookID(rawValue: id.rawValue))
    }

    func permanentlyDeleteFolder(_ id: FolderID) {
        performFolderChange { try $0.permanentlyDeleteFolder(id) }
        rebuildSearchIndex()
        enqueueForSync(.deleteFolder(id), notebookID: NotebookID(rawValue: id.rawValue))
    }

    func emptyTrash() {
        let deletedNotebookIDs = library.notebooks.filter { $0.trashedAt != nil }.map(\.id)
        let deletedFolderIDs = library.folders.filter { $0.trashedAt != nil }.map(\.id)
        library.emptyTrash()
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
        performFolderChange { try $0.moveFolder(id, to: parentID, at: Date()) }
        syncFolder(id)
    }

    func moveItems(_ items: Set<LibraryItemID>, to parentID: FolderID?) {
        performFolderChange { try $0.moveItems(items, to: parentID, at: Date()) }
        sync(items)
    }

    func deleteItems(_ items: Set<LibraryItemID>) {
        let date = Date()
        performFolderChange { try $0.moveItemsToTrash(items, at: date) }
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
        performFolderChange { try $0.restoreItems(items) }
        rebuildSearchIndex()
        for item in items {
            switch item {
            case let .folder(id):
                enqueueForSync(.restoreFolder(id), notebookID: NotebookID(rawValue: id.rawValue))
            case let .notebook(id): syncNotebookMetadata(id)
            }
        }
    }

    func toggleFavorite(_ notebookID: NotebookID) {
        library.toggleFavorite(notebookID)
        persistLibrary()
        syncNotebookMetadata(notebookID)
    }

    func delete(_ notebookID: NotebookID) {
        library.moveNotebookToTrash(notebookID, at: Date())
        searchIndex.remove(notebookID: notebookID)
        persistLibrary()
        syncNotebookMetadata(notebookID)
    }

    func restore(_ notebookID: NotebookID) {
        library.restoreNotebook(notebookID)
        refreshSearchIndex(for: notebookID)
        persistLibrary()
        syncNotebookMetadata(notebookID)
    }

    func permanentlyDelete(_ notebookID: NotebookID) {
        library.permanentlyDeleteNotebook(notebookID)
        searchIndex.remove(notebookID: notebookID)
        persistLibrary()
        enqueueForSync(.deleteNotebook(notebookID), notebookID: notebookID)
    }

    private func performFolderChange(_ change: (inout LibraryState) throws -> Void) {
        do {
            try change(&library)
            persistLibrary()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func syncNotebookMetadata(_ id: NotebookID) {
        guard let notebook = library.notebook(id: id) else { return }
        enqueueForSync(.updateNotebookMetadata(NotebookSyncMetadata(notebook: notebook)), notebookID: id)
    }

    private func syncFolder(_ id: FolderID) {
        guard let folder = library.folder(id: id) else { return }
        enqueueForSync(.updateFolder(folder), notebookID: NotebookID(rawValue: id.rawValue))
    }

    private func sync(_ items: Set<LibraryItemID>) {
        for item in items {
            switch item {
            case let .folder(id): syncFolder(id)
            case let .notebook(id): syncNotebookMetadata(id)
            }
        }
    }

    private func rebuildSearchIndex() {
        searchIndex = LibrarySearchIndex()
        for notebook in library.notebooks { searchIndex.update(notebook) }
    }
}
