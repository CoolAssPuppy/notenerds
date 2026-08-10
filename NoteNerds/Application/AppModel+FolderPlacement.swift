import Foundation

extension AppModel {
    var canCreateFolder: Bool {
        guard let currentFolderID else { return true }
        guard let currentFolder = library.folder(id: currentFolderID) else { return false }
        return currentFolder.parentID == nil && currentFolder.trashedAt == nil
    }

    var canCreateNotebook: Bool {
        guard let currentFolderID else { return true }
        guard let currentFolder = library.folder(id: currentFolderID) else { return false }
        return currentFolder.trashedAt == nil
    }

    func canMoveFolder(_ id: FolderID, to parentID: FolderID?) -> Bool {
        guard library.folder(id: id) != nil, parentID != id else { return false }
        guard let parentID else { return true }
        guard let destination = library.folder(id: parentID), destination.parentID == nil else {
            return false
        }
        return !library.folders.contains { $0.parentID == id }
    }

    func canMoveItems(_ items: Set<LibraryItemID>, to parentID: FolderID?) -> Bool {
        if let parentID, library.folder(id: parentID) == nil { return false }
        return items.allSatisfy { item in
            switch item {
            case let .folder(id): canMoveFolder(id, to: parentID)
            case let .notebook(id): library.notebook(id: id) != nil
            }
        }
    }

    func availableMoveDestinations(for items: Set<LibraryItemID>) -> [Folder] {
        let folders = library.folders
        let selectedFolderIDs = Set(items.compactMap { item -> FolderID? in
            guard case let .folder(id) = item else { return nil }
            return id
        })
        let selectedNotebookIDs = items.compactMap { item -> NotebookID? in
            guard case let .notebook(id) = item else { return nil }
            return id
        }
        guard selectedFolderIDs.allSatisfy({ library.folder(id: $0) != nil }),
              selectedNotebookIDs.allSatisfy({ library.notebook(id: $0) != nil }) else {
            return []
        }
        let parentIDs = Set(folders.compactMap(\.parentID))
        let selectedFolderHasChildren = !selectedFolderIDs.isDisjoint(with: parentIDs)
        return folders.filter { folder in
            guard folder.trashedAt == nil, !selectedFolderIDs.contains(folder.id) else { return false }
            guard !selectedFolderIDs.isEmpty else { return true }
            return folder.parentID == nil && !selectedFolderHasChildren
        }
    }
}
