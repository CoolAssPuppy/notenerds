import Foundation

struct NotebookSyncMetadata: Codable, Hashable, Sendable {
    let id: NotebookID
    let title: String
    let parentFolderID: FolderID?
    let modifiedAt: Date
    let lastOpenedAt: Date
    let isFavorite: Bool
    let tags: Set<String>
    let trashedAt: Date?

    init(notebook: Notebook) {
        id = notebook.id
        title = notebook.title
        parentFolderID = notebook.parentFolderID
        modifiedAt = notebook.modifiedAt
        lastOpenedAt = notebook.lastOpenedAt
        isFavorite = notebook.isFavorite
        tags = notebook.tags
        trashedAt = notebook.trashedAt
    }
}

struct LibraryDeletionTombstones: Codable, Equatable, Sendable {
    var folderIDs: Set<FolderID>
    var notebookIDs: Set<NotebookID>

    static let empty = LibraryDeletionTombstones(folderIDs: [], notebookIDs: [])
}

enum LibrarySyncMutation: Codable, Hashable, Sendable {
    case createFolder(Folder)
    case updateFolder(Folder)
    case trashFolder(FolderID, date: Date)
    case restoreFolder(FolderID)
    case deleteFolder(FolderID)
    case createNotebook(Notebook)
    case updateNotebookMetadata(NotebookSyncMetadata)
    case restoreNotebook(NotebookID)
    case deleteNotebook(NotebookID)

    func apply(to library: inout LibraryState) throws {
        switch self {
        case let .createFolder(folder), let .updateFolder(folder):
            try library.mergeSyncedFolder(folder)
        case let .trashFolder(id, date):
            try library.moveFolderToTrash(id, at: date)
        case let .restoreFolder(id):
            try library.restoreFolder(id)
        case let .deleteFolder(id):
            try library.permanentlyDeleteFolder(id)
        case let .createNotebook(notebook):
            try applyCreatedNotebook(notebook, to: &library)
        case let .updateNotebookMetadata(metadata):
            applyNotebookMetadata(metadata, to: &library)
        case let .restoreNotebook(id):
            library.restoreNotebook(id)
        case let .deleteNotebook(id):
            library.permanentlyDeleteNotebook(id)
        }
    }

    private func applyCreatedNotebook(
        _ notebook: Notebook,
        to library: inout LibraryState
    ) throws {
        guard library.notebook(id: notebook.id) == nil,
              !library.isPermanentlyDeleted(notebook.id) else { return }
        var syncedNotebook = notebook
        if let parentTrashDate = inheritedTrashDate(
            for: notebook.parentFolderID,
            in: library
        ) {
            syncedNotebook.trashedAt = parentTrashDate
        }
        try library.addNotebook(syncedNotebook, to: syncedNotebook.parentFolderID)
    }

    private func applyNotebookMetadata(
        _ metadata: NotebookSyncMetadata,
        to library: inout LibraryState
    ) {
        if let parentID = metadata.parentFolderID,
           library.isPermanentlyDeleted(parentID) {
            library.permanentlyDeleteNotebook(metadata.id)
            return
        }
        guard var notebook = library.notebook(id: metadata.id) else { return }
        let resolvedTrash = resolvedTrash(
            for: metadata,
            replacing: notebook,
            in: library
        )
        notebook.title = metadata.title
        notebook.parentFolderID = metadata.parentFolderID
        notebook.modifiedAt = metadata.modifiedAt
        notebook.lastOpenedAt = metadata.lastOpenedAt
        notebook.isFavorite = metadata.isFavorite
        notebook.tags = metadata.tags
        notebook.trashedAt = resolvedTrash.date
        library.updateNotebook(notebook)
        if let inheritedDate = resolvedTrash.inheritedDate {
            library.markNotebookTrashAsInherited(notebook.id, at: inheritedDate)
        } else if metadata.trashedAt != nil {
            library.clearInheritedTrashDate(forNotebook: notebook.id)
        }
    }

    private func resolvedTrash(
        for metadata: NotebookSyncMetadata,
        replacing notebook: Notebook,
        in library: LibraryState
    ) -> (date: Date?, inheritedDate: Date?) {
        if let incomingTrashDate = metadata.trashedAt {
            return (incomingTrashDate, nil)
        }
        let parentTrashDate = inheritedTrashDate(for: metadata.parentFolderID, in: library)
        if parentTrashDate == nil, isLegacyPureRestore(metadata, of: notebook) {
            return (nil, nil)
        }
        if let storedTrashDate = notebook.trashedAt,
           library.inheritedTrashDate(forNotebook: notebook.id) == nil {
            return (storedTrashDate, nil)
        }
        if let parentTrashDate {
            return (parentTrashDate, parentTrashDate)
        }
        if movedOutOfInheritedTrash(metadata, replacing: notebook, in: library) {
            return (nil, nil)
        }
        return (notebook.trashedAt, library.inheritedTrashDate(forNotebook: notebook.id))
    }

    private func movedOutOfInheritedTrash(
        _ metadata: NotebookSyncMetadata,
        replacing notebook: Notebook,
        in library: LibraryState
    ) -> Bool {
        guard metadata.parentFolderID != notebook.parentFolderID,
              let storedTrashDate = notebook.trashedAt,
              library.inheritedTrashDate(forNotebook: notebook.id) == storedTrashDate else {
            return false
        }
        return inheritedTrashDate(for: metadata.parentFolderID, in: library) == nil
    }

    private func isLegacyPureRestore(
        _ metadata: NotebookSyncMetadata,
        of notebook: Notebook
    ) -> Bool {
        guard notebook.trashedAt != nil, metadata.trashedAt == nil else { return false }
        return metadata.title == notebook.title
            && metadata.parentFolderID == notebook.parentFolderID
            && metadata.modifiedAt == notebook.modifiedAt
            && metadata.lastOpenedAt == notebook.lastOpenedAt
            && metadata.isFavorite == notebook.isFavorite
            && metadata.tags == notebook.tags
    }

    private func inheritedTrashDate(
        for folderID: FolderID?,
        in library: LibraryState
    ) -> Date? {
        guard let folderID else { return nil }
        return library.folder(id: folderID)?.trashedAt
    }

    var objectKey: String {
        switch self {
        case let .createFolder(folder), let .updateFolder(folder): "folder:\(folder.id.rawValue.uuidString)"
        case let .trashFolder(id, _), let .restoreFolder(id), let .deleteFolder(id):
            "folder:\(id.rawValue.uuidString)"
        case let .createNotebook(notebook): "notebook:\(notebook.id.rawValue.uuidString)"
        case let .updateNotebookMetadata(metadata): "notebook:\(metadata.id.rawValue.uuidString)"
        case let .restoreNotebook(id), let .deleteNotebook(id): "notebook:\(id.rawValue.uuidString)"
        }
    }

    var isPermanentDeletion: Bool {
        switch self {
        case .deleteFolder, .deleteNotebook: true
        default: false
        }
    }

    var affectedNotebookID: NotebookID? {
        switch self {
        case let .createNotebook(notebook): notebook.id
        case let .updateNotebookMetadata(metadata): metadata.id
        case let .restoreNotebook(id), let .deleteNotebook(id): id
        case .createFolder, .updateFolder, .trashFolder, .restoreFolder, .deleteFolder: nil
        }
    }
}

extension LibraryState {
    mutating func clearInheritedTrashDate(forNotebook id: NotebookID) {
        inheritedNotebookTrashDates[id] = nil
    }

    func isPermanentlyDeleted(_ id: FolderID) -> Bool {
        deletionTombstones.folderIDs.contains(id)
    }

    func permanentDeletionScope(
        forFolder id: FolderID
    ) -> (folderIDs: Set<FolderID>, notebookIDs: Set<NotebookID>) {
        guard folderStorage[id] != nil else { return ([id], []) }
        let folderIDs = descendantFolderIDs(of: id).union([id])
        let notebookIDs = Set(notebookStorage.values.compactMap { notebook -> NotebookID? in
            guard notebook.parentFolderID.map(folderIDs.contains) == true else { return nil }
            return notebook.id
        })
        return (folderIDs, notebookIDs)
    }

    mutating func restoreFolderFromBackup(_ folder: Folder) {
        deletionTombstones.folderIDs.remove(folder.id)
        folderStorage[folder.id] = folder
    }

    mutating func restoreNotebookFromBackup(
        _ notebook: Notebook,
        inheritedTrashDate: Date? = nil
    ) {
        deletionTombstones.notebookIDs.remove(notebook.id)
        inheritedNotebookTrashDates[notebook.id] = inheritedTrashDate == notebook.trashedAt
            ? inheritedTrashDate
            : nil
        notebookStorage[notebook.id] = notebook
    }

    mutating func mergeSyncedFolder(_ incoming: Folder) throws {
        guard !deletionTombstones.folderIDs.contains(incoming.id) else { return }
        var folder = incoming
        let stored = folderStorage[folder.id]
        if let stored, stored.modifiedAt > folder.modifiedAt {
            preserveMetadata(from: stored, in: &folder)
            folder.trashedAt = stored.trashedAt
            folder.inheritedTrashDate = stored.inheritedTrashDate
        }
        if let parentID = folder.parentID, isPermanentlyDeleted(parentID) {
            try permanentlyDeleteFolder(folder.id)
            return
        }
        let escapedTrashDate = inheritedTrashDateEscaped(by: folder)
        if folder.trashedAt == nil, let stored {
            folder.trashedAt = stored.trashedAt
            folder.inheritedTrashDate = stored.inheritedTrashDate
        }
        if folder.trashedAt == nil,
           let parentID = folder.parentID,
           let parentTrashDate = folderStorage[parentID]?.trashedAt {
            folder.trashedAt = parentTrashDate
            folder.inheritedTrashDate = parentTrashDate
        }
        if let stored, shouldPreserveAppearance(from: stored, over: folder) {
            folder.icon = stored.icon
            folder.iconColor = stored.iconColor
            folder.appearanceModifiedAt = stored.appearanceModifiedAt
        }
        updateFolder(folder)
        repairFolderCycle(startingAt: folder.id)
        if let escapedTrashDate {
            clearTrashDate(escapedTrashDate, forFolderSubtreeRoot: folder.id)
        } else if let trashDate = folderStorage[folder.id]?.trashedAt {
            setInheritedTrashDate(trashDate, forFolderSubtreeRoot: folder.id)
        }
    }

    private func inheritedTrashDateEscaped(by incoming: Folder) -> Date? {
        guard incoming.trashedAt == nil,
              let stored = folderStorage[incoming.id],
              stored.parentID != incoming.parentID,
              let storedTrashDate = stored.trashedAt,
              stored.inheritedTrashDate == storedTrashDate else { return nil }
        let incomingParentTrashDate = incoming.parentID.flatMap { folderStorage[$0]?.trashedAt }
        return incomingParentTrashDate == nil ? storedTrashDate : nil
    }

    private func preserveMetadata(from stored: Folder, in incoming: inout Folder) {
        incoming.name = stored.name
        incoming.parentID = stored.parentID
        incoming.modifiedAt = stored.modifiedAt
        incoming.isFavorite = stored.isFavorite
        incoming.tags = stored.tags
    }

    private func shouldPreserveAppearance(from stored: Folder, over incoming: Folder) -> Bool {
        guard let storedDate = stored.appearanceModifiedAt else { return false }
        guard let incomingDate = incoming.appearanceModifiedAt else { return true }
        return storedDate > incomingDate
    }

    private mutating func setInheritedTrashDate(_ date: Date, forFolderSubtreeRoot id: FolderID) {
        let affectedFolders = descendantFolderIDs(of: id).union([id])
        for folderID in affectedFolders where folderStorage[folderID]?.trashedAt == nil {
            folderStorage[folderID]?.trashedAt = date
            folderStorage[folderID]?.inheritedTrashDate = date
        }
        for notebookID in Array(notebookStorage.keys) {
            guard notebookStorage[notebookID]?.trashedAt == nil,
                  let parentID = notebookStorage[notebookID]?.parentFolderID,
                  affectedFolders.contains(parentID) else { continue }
            notebookStorage[notebookID]?.trashedAt = date
            inheritedNotebookTrashDates[notebookID] = date
        }
    }
}

extension LibraryState {
    private enum CodingKeys: String, CodingKey {
        case folderStorage, notebookStorage, assetStorage, preferredSortMode
        case inheritedNotebookTrashDates, deletionTombstones
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        folderStorage = try values.decode([FolderID: Folder].self, forKey: .folderStorage)
        notebookStorage = try values.decode([NotebookID: Notebook].self, forKey: .notebookStorage)
        assetStorage = try values.decodeIfPresent([AssetID: DocumentAsset].self, forKey: .assetStorage) ?? [:]
        preferredSortMode = try values.decode(LibrarySortMode.self, forKey: .preferredSortMode)
        inheritedNotebookTrashDates = try values.decodeIfPresent(
            [NotebookID: Date].self,
            forKey: .inheritedNotebookTrashDates
        ) ?? [:]
        deletionTombstones = try values.decodeIfPresent(
            LibraryDeletionTombstones.self,
            forKey: .deletionTombstones
        ) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(folderStorage, forKey: .folderStorage)
        try values.encode(notebookStorage, forKey: .notebookStorage)
        try values.encode(assetStorage, forKey: .assetStorage)
        try values.encode(preferredSortMode, forKey: .preferredSortMode)
        try values.encode(inheritedNotebookTrashDates, forKey: .inheritedNotebookTrashDates)
        try values.encode(deletionTombstones, forKey: .deletionTombstones)
    }
}
