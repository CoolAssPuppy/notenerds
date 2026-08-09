import Foundation

enum LibraryError: Error, Equatable {
    case folderNotFound
    case notebookAlreadyExists
    case folderNameRequired
    case folderCycle
    case notebookNotFound
}

enum LibrarySortMode: String, Codable, CaseIterable, Sendable {
    case recentlyModified
    case oldestModified
    case recentlyOpened
    case nameAscending
    case nameDescending
    case dateCreated
}

enum LibraryItemID: Hashable, Sendable {
    case folder(FolderID)
    case notebook(NotebookID)
}

struct Folder: Codable, Hashable, Identifiable, Sendable {
    let id: FolderID
    var name: String
    var parentID: FolderID?
    let createdAt: Date
    var modifiedAt: Date
    var isFavorite: Bool
    var tags: Set<String>
    var trashedAt: Date?

    init(
        id: FolderID = FolderID(),
        name: String,
        parentID: FolderID?,
        createdAt: Date,
        modifiedAt: Date,
        isFavorite: Bool = false,
        tags: Set<String> = [],
        trashedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isFavorite = isFavorite
        self.tags = tags
        self.trashedAt = trashedAt
    }
}

extension Folder {
    private enum CodingKeys: String, CodingKey {
        case id, name, parentID, createdAt, modifiedAt, isFavorite, tags, trashedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(FolderID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        parentID = try values.decodeIfPresent(FolderID.self, forKey: .parentID)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        tags = try values.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
        trashedAt = try values.decodeIfPresent(Date.self, forKey: .trashedAt)
    }
}

struct LibraryState: Codable, Equatable, Sendable {
    private var folderStorage: [FolderID: Folder]
    private var notebookStorage: [NotebookID: Notebook]
    private var assetStorage: [AssetID: DocumentAsset]
    var preferredSortMode: LibrarySortMode

    init(
        folders: [Folder] = [],
        notebooks: [Notebook] = [],
        preferredSortMode: LibrarySortMode = .recentlyModified
    ) {
        folderStorage = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        notebookStorage = Dictionary(uniqueKeysWithValues: notebooks.map { ($0.id, $0) })
        assetStorage = [:]
        self.preferredSortMode = preferredSortMode
    }

    func folder(id: FolderID) -> Folder? {
        folderStorage[id]
    }

    mutating func updateFolder(_ folder: Folder) {
        folderStorage[folder.id] = folder
    }

    func notebook(id: NotebookID) -> Notebook? {
        notebookStorage[id]
    }

    var folders: [Folder] {
        Array(folderStorage.values)
    }

    var notebooks: [Notebook] {
        Array(notebookStorage.values)
    }

    func asset(id: AssetID) -> DocumentAsset? {
        assetStorage[id]
    }

    var assets: [DocumentAsset] {
        Array(assetStorage.values)
    }

    mutating func storeAsset(_ asset: DocumentAsset) {
        assetStorage[asset.id] = asset
    }

    func replacingAssetDataWithPlaceholders() -> LibraryState {
        var copy = self
        for asset in assets {
            copy.assetStorage[asset.id] = DocumentAsset(
                id: asset.id,
                data: Data(),
                contentType: asset.contentType
            )
        }
        return copy
    }

    mutating func createFolder(named name: String, in parentID: FolderID?, at date: Date) throws -> Folder {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw LibraryError.folderNameRequired }
        if let parentID, folderStorage[parentID] == nil { throw LibraryError.folderNotFound }
        let folder = Folder(
            name: normalizedName,
            parentID: parentID,
            createdAt: date,
            modifiedAt: date
        )
        folderStorage[folder.id] = folder
        return folder
    }

    mutating func renameFolder(_ id: FolderID, to name: String, at date: Date) throws {
        guard folderStorage[id] != nil else { throw LibraryError.folderNotFound }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw LibraryError.folderNameRequired }
        folderStorage[id]?.name = normalizedName
        folderStorage[id]?.modifiedAt = date
    }

    mutating func addTag(_ tag: String, to id: FolderID, at date: Date) throws {
        guard folderStorage[id] != nil else { throw LibraryError.folderNotFound }
        let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTag.isEmpty else { return }
        folderStorage[id]?.tags.insert(cleanTag)
        folderStorage[id]?.modifiedAt = date
    }

    mutating func moveFolder(_ id: FolderID, to parentID: FolderID?, at date: Date) throws {
        guard folderStorage[id] != nil else { throw LibraryError.folderNotFound }
        if let parentID {
            guard folderStorage[parentID] != nil else { throw LibraryError.folderNotFound }
            guard parentID != id, !descendantFolderIDs(of: id).contains(parentID) else {
                throw LibraryError.folderCycle
            }
        }
        folderStorage[id]?.parentID = parentID
        folderStorage[id]?.modifiedAt = date
    }

    mutating func moveItems(_ items: Set<LibraryItemID>, to parentID: FolderID?, at date: Date) throws {
        var updatedLibrary = self
        for item in items {
            switch item {
            case let .folder(id):
                try updatedLibrary.moveFolder(id, to: parentID, at: date)
            case let .notebook(id):
                try updatedLibrary.moveNotebook(id, to: parentID)
            }
        }
        self = updatedLibrary
    }

    mutating func moveItemsToTrash(_ items: Set<LibraryItemID>, at date: Date) throws {
        var updatedLibrary = self
        for item in items {
            switch item {
            case let .folder(id): try updatedLibrary.moveFolderToTrash(id, at: date)
            case let .notebook(id): updatedLibrary.moveNotebookToTrash(id, at: date)
            }
        }
        self = updatedLibrary
    }

    mutating func restoreItems(_ items: Set<LibraryItemID>) throws {
        var updatedLibrary = self
        for item in items {
            switch item {
            case let .folder(id): try updatedLibrary.restoreFolder(id)
            case let .notebook(id): updatedLibrary.restoreNotebook(id)
            }
        }
        self = updatedLibrary
    }

    mutating func addNotebook(_ notebook: Notebook, to parentID: FolderID?) throws {
        guard notebookStorage[notebook.id] == nil else { throw LibraryError.notebookAlreadyExists }
        if let parentID, folderStorage[parentID] == nil { throw LibraryError.folderNotFound }
        var storedNotebook = notebook
        storedNotebook.parentFolderID = parentID
        notebookStorage[storedNotebook.id] = storedNotebook
    }

    mutating func updateNotebook(_ notebook: Notebook) {
        notebookStorage[notebook.id] = notebook
    }

    mutating func moveNotebookToTrash(_ id: NotebookID, at date: Date) {
        notebookStorage[id]?.trashedAt = date
    }

    mutating func restoreNotebook(_ id: NotebookID) {
        notebookStorage[id]?.trashedAt = nil
    }

    mutating func permanentlyDeleteNotebook(_ id: NotebookID) {
        notebookStorage[id] = nil
    }

    mutating func toggleFavorite(_ id: NotebookID) {
        guard let isFavorite = notebookStorage[id]?.isFavorite else { return }
        notebookStorage[id]?.isFavorite = !isFavorite
    }

    mutating func moveNotebook(_ id: NotebookID, to parentID: FolderID?) throws {
        if let parentID, folderStorage[parentID] == nil { throw LibraryError.folderNotFound }
        notebookStorage[id]?.parentFolderID = parentID
    }

    mutating func renameNotebook(_ id: NotebookID, to title: String, at date: Date) {
        notebookStorage[id]?.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notebookStorage[id]?.modifiedAt = date
    }

    mutating func duplicateNotebook(_ id: NotebookID, at date: Date) throws -> NotebookID {
        guard let notebook = notebookStorage[id] else { throw LibraryError.notebookNotFound }
        let duplicate = notebook.duplicated(at: date)
        notebookStorage[duplicate.id] = duplicate
        return duplicate.id
    }

    mutating func toggleFolderFavorite(_ id: FolderID) throws {
        guard let isFavorite = folderStorage[id]?.isFavorite else { throw LibraryError.folderNotFound }
        folderStorage[id]?.isFavorite = !isFavorite
    }

    mutating func moveFolderToTrash(_ id: FolderID, at date: Date) throws {
        guard folderStorage[id] != nil else { throw LibraryError.folderNotFound }
        let affectedFolders = descendantFolderIDs(of: id).union([id])
        for folderID in affectedFolders {
            folderStorage[folderID]?.trashedAt = date
        }
        for notebookID in Array(notebookStorage.keys) {
            guard let parentID = notebookStorage[notebookID]?.parentFolderID,
                  affectedFolders.contains(parentID) else { continue }
            notebookStorage[notebookID]?.trashedAt = date
        }
    }

    mutating func restoreFolder(_ id: FolderID) throws {
        guard folderStorage[id] != nil else { throw LibraryError.folderNotFound }
        let affectedFolders = descendantFolderIDs(of: id).union([id])
        for folderID in affectedFolders {
            folderStorage[folderID]?.trashedAt = nil
        }
        for notebookID in Array(notebookStorage.keys) {
            guard let parentID = notebookStorage[notebookID]?.parentFolderID,
                  affectedFolders.contains(parentID) else { continue }
            notebookStorage[notebookID]?.trashedAt = nil
        }
    }

    mutating func permanentlyDeleteFolder(_ id: FolderID) throws {
        guard folderStorage[id] != nil else { throw LibraryError.folderNotFound }
        let affectedFolders = descendantFolderIDs(of: id).union([id])
        folderStorage = folderStorage.filter { !affectedFolders.contains($0.key) }
        notebookStorage = notebookStorage.filter { _, notebook in
            guard let parentID = notebook.parentFolderID else { return true }
            return !affectedFolders.contains(parentID)
        }
    }

    mutating func emptyTrash() {
        notebookStorage = notebookStorage.filter { $0.value.trashedAt == nil }
        folderStorage = folderStorage.filter { $0.value.trashedAt == nil }
    }

    func notebooks(sortedBy mode: LibrarySortMode) -> [Notebook] {
        let availableNotebooks = notebookStorage.values.filter { $0.trashedAt == nil }
        return availableNotebooks.sorted { first, second in
            switch mode {
            case .recentlyModified: first.modifiedAt > second.modifiedAt
            case .oldestModified: first.modifiedAt < second.modifiedAt
            case .recentlyOpened: first.lastOpenedAt > second.lastOpenedAt
            case .nameAscending: first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            case .nameDescending: first.title.localizedCaseInsensitiveCompare(second.title) == .orderedDescending
            case .dateCreated: first.createdAt > second.createdAt
            }
        }
    }

    func notebooks(in folderID: FolderID?, sortedBy mode: LibrarySortMode) -> [Notebook] {
        let sorted = notebooks(sortedBy: mode)
        guard let folderID else { return sorted }
        return sorted.filter { $0.parentFolderID == folderID }
    }

    func folders(sortedBy mode: LibrarySortMode) -> [Folder] {
        folderStorage.values.sorted { first, second in
            switch mode {
            case .recentlyModified, .recentlyOpened: first.modifiedAt > second.modifiedAt
            case .oldestModified: first.modifiedAt < second.modifiedAt
            case .nameAscending: first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            case .nameDescending: first.name.localizedCaseInsensitiveCompare(second.name) == .orderedDescending
            case .dateCreated: first.createdAt > second.createdAt
            }
        }
    }

    private func descendantFolderIDs(of id: FolderID) -> Set<FolderID> {
        var childrenByParent: [FolderID: [FolderID]] = [:]
        for folder in folderStorage.values {
            guard let parentID = folder.parentID else { continue }
            childrenByParent[parentID, default: []].append(folder.id)
        }
        var descendants: Set<FolderID> = []
        var visited: Set<FolderID> = [id]
        var pending = [id]
        while let parentID = pending.popLast() {
            let unvisitedChildren = childrenByParent[parentID, default: []].filter {
                visited.insert($0).inserted
            }
            descendants.formUnion(unvisitedChildren)
            pending.append(contentsOf: unvisitedChildren)
        }
        return descendants
    }
}

extension LibraryState {
    private enum CodingKeys: String, CodingKey {
        case folderStorage
        case notebookStorage
        case assetStorage
        case preferredSortMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderStorage = try container.decode([FolderID: Folder].self, forKey: .folderStorage)
        notebookStorage = try container.decode([NotebookID: Notebook].self, forKey: .notebookStorage)
        assetStorage = try container.decodeIfPresent([AssetID: DocumentAsset].self, forKey: .assetStorage) ?? [:]
        preferredSortMode = try container.decode(LibrarySortMode.self, forKey: .preferredSortMode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(folderStorage, forKey: .folderStorage)
        try container.encode(notebookStorage, forKey: .notebookStorage)
        try container.encode(assetStorage, forKey: .assetStorage)
        try container.encode(preferredSortMode, forKey: .preferredSortMode)
    }
}
