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

enum LibrarySyncMutation: Codable, Hashable, Sendable {
    case createFolder(Folder)
    case updateFolder(Folder)
    case trashFolder(FolderID, date: Date)
    case restoreFolder(FolderID)
    case deleteFolder(FolderID)
    case createNotebook(Notebook)
    case updateNotebookMetadata(NotebookSyncMetadata)
    case deleteNotebook(NotebookID)

    func apply(to library: inout LibraryState) throws {
        switch self {
        case let .createFolder(folder), let .updateFolder(folder):
            library.updateFolder(folder)
        case let .trashFolder(id, date):
            try library.moveFolderToTrash(id, at: date)
        case let .restoreFolder(id):
            try library.restoreFolder(id)
        case let .deleteFolder(id):
            try library.permanentlyDeleteFolder(id)
        case let .createNotebook(notebook):
            if library.notebook(id: notebook.id) == nil {
                try library.addNotebook(notebook, to: notebook.parentFolderID)
            }
        case let .updateNotebookMetadata(metadata):
            guard var notebook = library.notebook(id: metadata.id) else { return }
            notebook.title = metadata.title
            notebook.parentFolderID = metadata.parentFolderID
            notebook.modifiedAt = metadata.modifiedAt
            notebook.lastOpenedAt = metadata.lastOpenedAt
            notebook.isFavorite = metadata.isFavorite
            notebook.tags = metadata.tags
            notebook.trashedAt = metadata.trashedAt
            library.updateNotebook(notebook)
        case let .deleteNotebook(id):
            library.permanentlyDeleteNotebook(id)
        }
    }

    var objectKey: String {
        switch self {
        case let .createFolder(folder), let .updateFolder(folder): "folder:\(folder.id.rawValue.uuidString)"
        case let .trashFolder(id, _), let .restoreFolder(id), let .deleteFolder(id):
            "folder:\(id.rawValue.uuidString)"
        case let .createNotebook(notebook): "notebook:\(notebook.id.rawValue.uuidString)"
        case let .updateNotebookMetadata(metadata): "notebook:\(metadata.id.rawValue.uuidString)"
        case let .deleteNotebook(id): "notebook:\(id.rawValue.uuidString)"
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
        case let .deleteNotebook(id): id
        case .createFolder, .updateFolder, .trashFolder, .restoreFolder, .deleteFolder: nil
        }
    }
}
