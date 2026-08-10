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
    case invalidFolderTree
    case notebookIDMismatch
    case contentHashMismatch
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
        var inheritedTrashDates: [NotebookID: Date] = [:]
        for record in manifest.notebookTrashProvenance {
            inheritedTrashDates[record.notebookID] = record.inheritedTrashDate
        }
        for content in contents {
            var notebook = content.package.notebook
            var inheritedTrashDate = inheritedTrashDates[notebook.id]
            if let folderID = notebook.parentFolderID, restored.folder(id: folderID) == nil {
                notebook.parentFolderID = nil
                inheritedTrashDate = nil
            }
            let existing = restored.notebook(id: notebook.id)
            let choice = choices[notebook.id] ?? .keepLocal
            if existing != nil, choice == .keepLocal { continue }
            let restoredNotebook = existing != nil && choice == .importCopy
                ? notebook.duplicated(at: now())
                : notebook
            restored.restoreNotebookFromBackup(
                restoredNotebook,
                inheritedTrashDate: restoredNotebook.id == notebook.id ? inheritedTrashDate : nil
            )
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
        for record in records {
            let remoteFolder = record.folder
            guard var localFolder = library.folder(id: record.id) else {
                library.restoreFolderFromBackup(remoteFolder)
                continue
            }
            if shouldRestoreAppearance(from: remoteFolder, over: localFolder) {
                localFolder.icon = remoteFolder.icon
                localFolder.iconColor = remoteFolder.iconColor
                localFolder.appearanceModifiedAt = remoteFolder.appearanceModifiedAt
            }
            library.restoreFolderFromBackup(localFolder)
        }
        do {
            for record in records {
                _ = try NotionFolderPathResolver.path(for: record.id, in: library)
            }
        } catch {
            throw NotionRestoreError.invalidFolderTree
        }
    }

    private func shouldRestoreAppearance(from remote: Folder, over local: Folder) -> Bool {
        guard let remoteDate = remote.appearanceModifiedAt else { return false }
        guard let localDate = local.appearanceModifiedAt else { return true }
        return remoteDate > localDate
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
