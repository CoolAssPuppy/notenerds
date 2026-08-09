import Foundation

struct NotionNotebookPayload: Equatable, Sendable {
    let snapshot: NotionNotebookSnapshot
    let nativeArchive: Data
    let pdf: Data
    let previews: [String: Data]
}

enum NotionSyncResult: Equatable, Sendable {
    case skippedUnchanged
    case uploaded(pageID: String)
}

protocol NotionSyncAPI: Sendable {
    func uploadFile(data: Data, filename: String, contentType: String) async throws -> String
    func findNotebookPage(dataSourceID: String, notebookID: String) async throws -> NotionPageBinding?
    func createNotebookPage(
        dataSourceID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) async throws -> NotionPageBinding
    func updateNotebookPage(
        pageID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) async throws -> NotionPageBinding
    func trashNotebookPage(pageID: String) async throws
    func findManagedRootBlock(pageID: String, notebookID: String) async throws -> String?
    func replaceManagedPage(
        pageID: String,
        oldRootID: String?,
        plan: NotionManagedPagePlan
    ) async throws -> String
}

extension NotionAPIClient: NotionSyncAPI {}

actor NotionSyncCoordinator {
    private let api: any NotionSyncAPI
    private let registry: NotionSyncRegistry
    private let now: @Sendable () -> Date
    private let retryJitter: @Sendable (ClosedRange<TimeInterval>) -> TimeInterval

    init(
        api: any NotionSyncAPI,
        registry: NotionSyncRegistry,
        now: @escaping @Sendable () -> Date = Date.init,
        retryJitter: @escaping @Sendable (ClosedRange<TimeInterval>) -> TimeInterval = {
            Double.random(in: $0)
        }
    ) {
        self.api = api
        self.registry = registry
        self.now = now
        self.retryJitter = retryJitter
    }

    func sync(
        _ payload: NotionNotebookPayload,
        to destination: NotionDestination
    ) async throws -> NotionSyncResult {
        let notebookID = payload.snapshot.row.notebookID
        guard try await registry.needsSync(
            notebookID: notebookID,
            contentHash: payload.snapshot.row.contentHash,
            destination: destination
        ) else {
            return .skippedUnchanged
        }
        try validate(payload)
        try await registry.enqueue(notebookID: notebookID)
        do {
            return try await performSync(payload, destination: destination)
        } catch {
            let failure = Self.failureCategory(error)
            if failure == .missingRemotePage {
                try? await registry.removeBinding(notebookID: notebookID)
            }
            let state = try? await registry.snapshot()
            let attempt = state?.queue.first { $0.notebookID == notebookID }?.attemptCount ?? 0
            try? await registry.recordFailure(
                notebookID: notebookID,
                failure: failure,
                retryAt: retryDate(for: failure, attempt: attempt)
            )
            throw error
        }
    }

    private func performSync(
        _ payload: NotionNotebookPayload,
        destination: NotionDestination
    ) async throws -> NotionSyncResult {
        let notebookID = payload.snapshot.row.notebookID
        let uploads = try await uploadRepresentations(payload, notebookID: notebookID)
        let state = try await registry.snapshot()
        let existingBinding = state.binding(notebookID: notebookID)
        let page = try await resolvePage(
            payload: payload,
            destination: destination,
            existingBinding: existingBinding,
            files: uploads.files
        )
        let oldRootID = try await managedRootID(
            pageID: page.pageID,
            notebookID: notebookID,
            existingBinding: existingBinding
        )
        let syncedAt = now()
        let plan = try NotionManagedPageBuilder.plan(
            snapshot: payload.snapshot,
            previewUploadIDs: uploads.previewIDs,
            files: uploads.files,
            syncedAt: syncedAt
        )
        let managedRootID = try await api.replaceManagedPage(
            pageID: page.pageID,
            oldRootID: oldRootID,
            plan: plan
        )
        try await recordSuccess(
            payload,
            pageID: page.pageID,
            rootID: managedRootID,
            syncedAt: syncedAt
        )
        return .uploaded(pageID: page.pageID)
    }

    private func uploadRepresentations(
        _ payload: NotionNotebookPayload,
        notebookID: String
    ) async throws -> UploadedRepresentations {
        let nativeID = try await api.uploadFile(
            data: payload.nativeArchive,
            filename: "\(notebookID.lowercased()).notenerds.json",
            contentType: "application/json"
        )
        let pdfID = try await api.uploadFile(
            data: payload.pdf,
            filename: "\(notebookID.lowercased()).pdf",
            contentType: "application/pdf"
        )
        var previewIDs: [String: String] = [:]
        for canvas in payload.snapshot.canvases {
            guard let preview = payload.previews[canvas.canvasID] else {
                throw NotionManagedPageError.missingPreview(canvas.canvasID)
            }
            previewIDs[canvas.canvasID] = try await api.uploadFile(
                data: preview,
                filename: "\(canvas.canvasID.lowercased()).png",
                contentType: "image/png"
            )
        }
        return UploadedRepresentations(
            files: NotionNotebookRemoteFiles(nativeUploadID: nativeID, pdfUploadID: pdfID),
            previewIDs: previewIDs
        )
    }

    private func managedRootID(
        pageID: String,
        notebookID: String,
        existingBinding: NotionNotebookBinding?
    ) async throws -> String? {
        if let existingBinding, existingBinding.pageID == pageID {
            return existingBinding.managedRootBlockID
        }
        return try await api.findManagedRootBlock(pageID: pageID, notebookID: notebookID)
    }

    private func recordSuccess(
        _ payload: NotionNotebookPayload,
        pageID: String,
        rootID: String,
        syncedAt: Date
    ) async throws {
        try await registry.recordSuccess(
            NotionNotebookBinding(
                notebookID: payload.snapshot.row.notebookID,
                pageID: pageID,
                managedRootBlockID: rootID,
                contentHash: payload.snapshot.row.contentHash,
                syncedAt: syncedAt,
                notionLastEditedAt: nil
            )
        )
    }

    private func resolvePage(
        payload: NotionNotebookPayload,
        destination: NotionDestination,
        existingBinding: NotionNotebookBinding?,
        files: NotionNotebookRemoteFiles
    ) async throws -> NotionPageBinding {
        if let existingBinding {
            return try await api.updateNotebookPage(
                pageID: existingBinding.pageID,
                snapshot: payload.snapshot,
                files: files
            )
        }
        if let remote = try await api.findNotebookPage(
            dataSourceID: destination.dataSourceID,
            notebookID: payload.snapshot.row.notebookID
        ) {
            return try await api.updateNotebookPage(
                pageID: remote.pageID,
                snapshot: payload.snapshot,
                files: files
            )
        }
        return try await api.createNotebookPage(
            dataSourceID: destination.dataSourceID,
            snapshot: payload.snapshot,
            files: files
        )
    }

    private func validate(_ payload: NotionNotebookPayload) throws {
        guard !payload.nativeArchive.isEmpty, !payload.pdf.isEmpty else {
            throw NotionAPIError.emptyFile
        }
        for canvas in payload.snapshot.canvases {
            guard let preview = payload.previews[canvas.canvasID], !preview.isEmpty else {
                throw NotionManagedPageError.missingPreview(canvas.canvasID)
            }
        }
    }

    private static func failureCategory(_ error: Error) -> NotionSyncFailure {
        guard let apiError = error as? NotionAPIError else { return .persistent }
        return switch apiError {
        case .httpStatus(401): NotionSyncFailure.authentication
        case .httpStatus(403): NotionSyncFailure.accessDenied
        case .httpStatus(404): NotionSyncFailure.missingRemotePage
        case .httpStatus(429): NotionSyncFailure.rateLimited
        case .httpStatus(500), .httpStatus(502), .httpStatus(503), .httpStatus(504):
            NotionSyncFailure.serviceUnavailable
        case .invalidIdentifier, .invalidFilename, .invalidContentType, .emptyFile,
             .invalidResponse, .repeatedCursor, .paginationLimit, .duplicateNotebookRows,
             .duplicateManagedSections, .payloadTooLarge, .httpStatus:
            NotionSyncFailure.validation
        }
    }

    private func retryDate(for failure: NotionSyncFailure, attempt: Int) -> Date? {
        guard failure == .rateLimited || failure == .serviceUnavailable || failure == .persistent else {
            return nil
        }
        let base = min(pow(2, Double(attempt)), 300)
        let delay = min(base + retryJitter(0...base), 300)
        return now().addingTimeInterval(delay)
    }
}

private struct UploadedRepresentations {
    let files: NotionNotebookRemoteFiles
    let previewIDs: [String: String]
}
