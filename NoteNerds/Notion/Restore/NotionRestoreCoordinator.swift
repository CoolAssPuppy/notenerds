import Foundation

struct NotionRemoteLibrarySnapshot: Sendable {
    let manifestData: Data
    let databaseID: String
    let archives: [Data]
}

enum NotionRestoreChoice: Equatable, Sendable {
    case keepLocal
    case useNotion
    case importCopy
}

enum NotionRestoreError: Error, Equatable, Sendable {
    case databaseMismatch
    case duplicateNotebook(NotebookID)
    case missingParentFolder(FolderID)
    case invalidFolderTree
    case notebookIDMismatch
}

struct NotionRestoreCoordinator: Sendable {
    private let archive = NotionTransportArchive()
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func restore(
        _ remote: NotionRemoteLibrarySnapshot,
        into local: LibraryState,
        choices: [NotebookID: NotionRestoreChoice]
    ) throws -> LibraryState {
        let manifest = try NotionLibraryManifestCodec.decode(remote.manifestData)
        guard manifest.databaseID == remote.databaseID else {
            throw NotionRestoreError.databaseMismatch
        }
        let contents = try remote.archives.map(archive.decode)
        try validateUniqueNotebooks(contents)

        var restored = local
        try restoreFolders(manifest.folders, into: &restored)
        for content in contents {
            let notebook = content.package.notebook
            if let folderID = notebook.parentFolderID, restored.folder(id: folderID) == nil {
                throw NotionRestoreError.missingParentFolder(folderID)
            }
            let existing = restored.notebook(id: notebook.id)
            let choice = choices[notebook.id] ?? .keepLocal
            if existing != nil, choice == .keepLocal { continue }
            let restoredNotebook = existing != nil && choice == .importCopy
                ? notebook.duplicated(at: now())
                : notebook
            restored.updateNotebook(restoredNotebook)
            for asset in content.assets {
                restored.storeAsset(asset)
            }
        }
        return restored
    }

    private func restoreFolders(
        _ records: [NotionFolderManifestRecord],
        into library: inout LibraryState
    ) throws {
        for record in records where library.folder(id: record.id) == nil {
            library.updateFolder(
                Folder(
                    id: record.id,
                    name: record.name,
                    parentID: record.parentID,
                    createdAt: record.createdAt,
                    modifiedAt: record.modifiedAt,
                    isFavorite: record.isFavorite,
                    tags: Set(record.tags),
                    trashedAt: record.trashedAt
                )
            )
        }
        do {
            for record in records {
                _ = try NotionFolderPathResolver.path(for: record.id, in: library)
            }
        } catch {
            throw NotionRestoreError.invalidFolderTree
        }
    }

    private func validateUniqueNotebooks(_ contents: [NativeArchiveContents]) throws {
        var identifiers: Set<NotebookID> = []
        for content in contents {
            let identifier = content.package.notebook.id
            guard identifiers.insert(identifier).inserted else {
                throw NotionRestoreError.duplicateNotebook(identifier)
            }
        }
    }
}
