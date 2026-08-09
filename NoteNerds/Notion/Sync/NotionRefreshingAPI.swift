import Foundation

actor NotionRefreshingAPI: NotionSyncAPI {
    private let credentialStore: any NotionCredentialStore
    private let refresh: @Sendable () async throws -> NotionStoredConnection
    private let apiFactory: @Sendable (String) -> any NotionSyncAPI

    init(
        credentialStore: any NotionCredentialStore,
        refresh: @escaping @Sendable () async throws -> NotionStoredConnection,
        apiFactory: @escaping @Sendable (String) -> any NotionSyncAPI = {
            NotionAPIClient(accessToken: $0)
        }
    ) {
        self.credentialStore = credentialStore
        self.refresh = refresh
        self.apiFactory = apiFactory
    }

    func uploadFile(data: Data, filename: String, contentType: String) async throws -> String {
        try await withRefresh { api in
            try await api.uploadFile(data: data, filename: filename, contentType: contentType)
        }
    }

    func findNotebookPage(
        dataSourceID: String,
        notebookID: String
    ) async throws -> NotionPageBinding? {
        try await withRefresh { api in
            try await api.findNotebookPage(dataSourceID: dataSourceID, notebookID: notebookID)
        }
    }

    func createNotebookPage(
        dataSourceID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) async throws -> NotionPageBinding {
        try await withRefresh { api in
            try await api.createNotebookPage(
                dataSourceID: dataSourceID,
                snapshot: snapshot,
                files: files
            )
        }
    }

    func updateNotebookPage(
        pageID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) async throws -> NotionPageBinding {
        try await withRefresh { api in
            try await api.updateNotebookPage(pageID: pageID, snapshot: snapshot, files: files)
        }
    }

    func trashNotebookPage(pageID: String) async throws {
        try await withRefresh { api in
            try await api.trashNotebookPage(pageID: pageID)
        }
    }

    func findManagedRootBlock(pageID: String, notebookID: String) async throws -> String? {
        try await withRefresh { api in
            try await api.findManagedRootBlock(pageID: pageID, notebookID: notebookID)
        }
    }

    func replaceManagedPage(
        pageID: String,
        oldRootID: String?,
        plan: NotionManagedPagePlan
    ) async throws -> String {
        try await withRefresh { api in
            try await api.replaceManagedPage(pageID: pageID, oldRootID: oldRootID, plan: plan)
        }
    }

    private func withRefresh<Value: Sendable>(
        _ operation: @Sendable (any NotionSyncAPI) async throws -> Value
    ) async throws -> Value {
        guard let current = try credentialStore.load() else {
            throw NotionOAuthError.noConnection
        }
        do {
            return try await operation(apiFactory(current.credentials.accessToken))
        } catch let error as NotionAPIError where error == .httpStatus(401) {
            let updated = try await refresh()
            return try await operation(apiFactory(updated.credentials.accessToken))
        }
    }
}

extension NotionRefreshingAPI: NotionRestoreAPI {
    func fetchNativeNotebookFile(pageID: String) async throws -> NotionRemoteNotebookFile {
        try await withRefresh { api in
            guard let restoreAPI = api as? any NotionRestoreAPI else {
                throw NotionAPIError.invalidResponse
            }
            return try await restoreAPI.fetchNativeNotebookFile(pageID: pageID)
        }
    }

    func listNativeNotebookFiles(
        dataSourceID: String
    ) async throws -> [NotionRemoteNotebookFile] {
        try await withRefresh { api in
            guard let restoreAPI = api as? any NotionRestoreAPI else {
                throw NotionAPIError.invalidResponse
            }
            return try await restoreAPI.listNativeNotebookFiles(dataSourceID: dataSourceID)
        }
    }

    func findLibraryManifestRootBlock(pageID: String) async throws -> String? {
        try await withRefresh { api in
            guard let restoreAPI = api as? any NotionRestoreAPI else {
                throw NotionAPIError.invalidResponse
            }
            return try await restoreAPI.findLibraryManifestRootBlock(pageID: pageID)
        }
    }

    func findManagedFile(rootBlockID: String) async throws -> URL {
        try await withRefresh { api in
            guard let restoreAPI = api as? any NotionRestoreAPI else {
                throw NotionAPIError.invalidResponse
            }
            return try await restoreAPI.findManagedFile(rootBlockID: rootBlockID)
        }
    }

    func downloadFile(from url: URL, maximumByteCount: Int) async throws -> Data {
        try await withRefresh { api in
            guard let restoreAPI = api as? any NotionRestoreAPI else {
                throw NotionAPIError.invalidResponse
            }
            return try await restoreAPI.downloadFile(
                from: url,
                maximumByteCount: maximumByteCount
            )
        }
    }
}

extension NotionRefreshingAPI: NotionDestinationProviding {
    func searchPages(query: String?) async throws -> [NotionPageSummary] {
        try await withRefresh { api in
            guard let destinationAPI = api as? any NotionDestinationProviding else {
                throw NotionAPIError.invalidResponse
            }
            return try await destinationAPI.searchPages(query: query)
        }
    }

    func createDatabase(parentPageID: String) async throws -> NotionDestination {
        try await withRefresh { api in
            guard let destinationAPI = api as? any NotionDestinationProviding else {
                throw NotionAPIError.invalidResponse
            }
            return try await destinationAPI.createDatabase(parentPageID: parentPageID)
        }
    }

    func createLibraryManifestPage(parentPageID: String) async throws -> NotionPageBinding {
        try await withRefresh { api in
            guard let destinationAPI = api as? any NotionDestinationProviding else {
                throw NotionAPIError.invalidResponse
            }
            return try await destinationAPI.createLibraryManifestPage(parentPageID: parentPageID)
        }
    }
}
