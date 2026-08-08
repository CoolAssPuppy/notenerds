import Foundation

protocol NotionRemoteLibraryLoading: Sendable {
    func load() async throws -> NotionRemoteLibrarySnapshot
}

actor NotionRemoteLibraryLoader: NotionRemoteLibraryLoading {
    private static let maximumManifestByteCount = 10 * 1_024 * 1_024
    private static let maximumArchiveByteCount = 1_124 * 1_024 * 1_024

    private let api: any NotionRestoreAPI
    private let registry: NotionSyncRegistry
    private let archive = NotionTransportArchive()

    init(api: any NotionRestoreAPI, registry: NotionSyncRegistry) {
        self.api = api
        self.registry = registry
    }

    func load() async throws -> NotionRemoteLibrarySnapshot {
        let state = try await registry.snapshot()
        guard let destination = state.destination,
              let manifestPageID = state.manifestPageID else {
            throw NotionOAuthError.noConnection
        }
        let rootBlockID = try await resolveManifestRoot(state: state, pageID: manifestPageID)
        let manifestURL = try await api.findManagedFile(rootBlockID: rootBlockID)
        let manifestData = try await api.downloadFile(
            from: manifestURL,
            maximumByteCount: Self.maximumManifestByteCount
        )
        let files = try await api.listNativeNotebookFiles(
            dataSourceID: destination.dataSourceID
        )
        var archives: [Data] = []
        archives.reserveCapacity(files.count)
        for file in files {
            let archiveData = try await api.downloadFile(
                from: file.url,
                maximumByteCount: Self.maximumArchiveByteCount
            )
            let decoded = try archive.decode(archiveData)
            let archiveNotebookID = decoded.package.notebook.id.rawValue.uuidString.lowercased()
            guard archiveNotebookID == file.notebookID else {
                throw NotionRestoreError.notebookIDMismatch
            }
            archives.append(archiveData)
        }
        return NotionRemoteLibrarySnapshot(
            manifestData: manifestData,
            databaseID: destination.databaseID,
            archives: archives
        )
    }

    private func resolveManifestRoot(
        state: NotionSyncState,
        pageID: String
    ) async throws -> String {
        if let rootBlockID = state.manifestRootBlockID { return rootBlockID }
        guard let discovered = try await api.findLibraryManifestRootBlock(pageID: pageID) else {
            throw NotionAPIError.invalidResponse
        }
        return discovered
    }
}
