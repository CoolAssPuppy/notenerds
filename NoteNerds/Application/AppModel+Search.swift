import Foundation

extension AppModel {
    var visibleNotebooks: [Notebook] {
        let scoped: [Notebook]
        switch selectedSection {
        case .files:
            let sortMode: LibrarySortMode = currentFolderID == nil ? .recentlyModified : library.preferredSortMode
            scoped = library.notebooks(in: currentFolderID, sortedBy: sortMode)
        case .favorites:
            scoped = library.notebooks(sortedBy: library.preferredSortMode).filter(\.isFavorite)
        case .recents:
            scoped = library.notebooks(sortedBy: .recentlyOpened)
        case .trash:
            scoped = library.notebooks.filter { $0.trashedAt != nil }.sorted { $0.modifiedAt > $1.modifiedAt }
        }
        guard !searchQuery.isEmpty else { return scoped }
        let matchedIDs = Set(searchIndex.search(searchQuery).map(\.notebookID))
        return scoped.filter { matchedIDs.contains($0.id) }
    }

    var visibleFolders: [Folder] {
        switch selectedSection {
        case .files:
            let active = library.folders(sortedBy: library.preferredSortMode).filter { $0.trashedAt == nil }
            return searchQuery.isEmpty
                ? active.filter { $0.parentID == currentFolderID }
                : active.filter {
                    $0.name.localizedCaseInsensitiveContains(searchQuery)
                        || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
                }
        case .favorites:
            return library.folders(sortedBy: library.preferredSortMode).filter {
                $0.isFavorite && $0.trashedAt == nil
            }
        case .recents:
            return []
        case .trash:
            return library.folders(sortedBy: .recentlyModified).filter { $0.trashedAt != nil }
        }
    }

    var searchResults: [LibrarySearchResult] {
        searchIndex.search(searchQuery)
    }
}
