import Foundation

extension AppModel {
    func syncNotebookMetadata(_ id: NotebookID) {
        guard let notebook = library.notebook(id: id) else { return }
        enqueueForSync(
            .updateNotebookMetadata(NotebookSyncMetadata(notebook: notebook)),
            notebookID: id
        )
    }

    func syncNotebookRestoration(_ id: NotebookID) {
        guard let notebook = library.notebook(id: id) else { return }
        enqueueForSync(.restoreNotebook(id), notebookID: id)
        enqueueRestoredAncestorSnapshots(startingAt: notebook.parentFolderID)
        syncNotebookMetadata(id)
    }

    func syncFolder(_ id: FolderID) {
        guard let folder = library.folder(id: id) else { return }
        enqueueForSync(.updateFolder(folder), notebookID: NotebookID(rawValue: id.rawValue))
    }

    func sync(_ items: Set<LibraryItemID>) {
        for item in items {
            switch item {
            case let .folder(id): syncFolder(id)
            case let .notebook(id): syncNotebookMetadata(id)
            }
        }
    }

    func syncFolderRestoration(_ id: FolderID) {
        guard let folder = library.folder(id: id) else { return }
        enqueueFolderRestoration(id)
        enqueueRestoredAncestorSnapshots(startingAt: folder.parentID)
    }

    private func enqueueFolderRestoration(_ id: FolderID) {
        enqueueForSync(.restoreFolder(id), notebookID: NotebookID(rawValue: id.rawValue))
    }

    private func enqueueRestoredAncestorSnapshots(startingAt id: FolderID?) {
        var currentID = id
        var visited = Set<FolderID>()
        while let folderID = currentID,
              visited.insert(folderID).inserted,
              let folder = library.folder(id: folderID) {
            syncFolder(folderID)
            currentID = folder.parentID
        }
    }
}
