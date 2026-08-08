import Foundation

actor NotionManifestSyncCoordinator {
    private let api: any NotionSyncAPI
    private let registry: NotionSyncRegistry

    init(api: any NotionSyncAPI, registry: NotionSyncRegistry) {
        self.api = api
        self.registry = registry
    }

    func sync(
        _ manifestData: Data,
        contentHash: String? = nil
    ) async throws -> NotionSyncResult {
        guard !manifestData.isEmpty else { throw NotionAPIError.emptyFile }

        let state = try await registry.snapshot()
        guard let pageID = state.manifestPageID else {
            throw NotionOAuthError.noConnection
        }

        let contentHash = contentHash ?? NotionContentHasher.sha256Hex(of: manifestData)
        guard state.manifestContentHash != contentHash else {
            return .skippedUnchanged
        }

        let uploadID = try await api.uploadFile(
            data: manifestData,
            filename: "library-manifest.json",
            contentType: "application/json"
        )
        let plan = try NotionLibraryManifestPageBuilder.plan(uploadID: uploadID)
        let rootBlockID = try await api.replaceManagedPage(
            pageID: pageID,
            oldRootID: state.manifestRootBlockID,
            plan: plan
        )
        try await registry.recordManifestSuccess(
            rootBlockID: rootBlockID,
            contentHash: contentHash
        )
        return .uploaded(pageID: pageID)
    }
}
