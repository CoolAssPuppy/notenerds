import Combine
import Foundation

enum NotionIntegrationState: Equatable, Sendable {
    case unavailable
    case disconnected
    case connecting
    case connected(workspaceName: String)
    case selectingDestination
    case syncing
    case preparingRestore
    case reviewingRestore
    case restoring
    case disconnecting
    case actionNeeded
}

@MainActor
protocol NotionConnectionManaging: AnyObject {
    func currentConnection() throws -> NotionStoredConnection?
    func connect() async throws -> NotionStoredConnection
    func refresh() async throws -> NotionStoredConnection
    func disconnect() async throws
}

extension NotionConnectionService: NotionConnectionManaging {}

protocol NotionDestinationProviding: Sendable {
    func searchPages(query: String?) async throws -> [NotionPageSummary]
    func createDatabase(parentPageID: String) async throws -> NotionDestination
    func createLibraryManifestPage(parentPageID: String) async throws -> NotionPageBinding
}

extension NotionAPIClient: NotionDestinationProviding {}

@MainActor
final class NotionIntegrationModel: ObservableObject {
    @Published private(set) var state: NotionIntegrationState
    @Published private(set) var pages: [NotionPageSummary] = []
    @Published private(set) var destination: NotionDestination?
    @Published private(set) var failureMessage: String?
    @Published private(set) var lastSyncSummary: String?
    @Published private(set) var restoreCandidates: [NotionRestoreCandidate] = []
    @Published private(set) var syncedNotebookIDs: Set<String> = []
    @Published var meetingChoices: [NotionMeetingNote] = []
    @Published var meetingLinkMessage: String?
    @Published var isMeetingLinkPermissionRequired = false

    private let isConfigured: Bool
    private let connectionManager: any NotionConnectionManaging
    private let destinationProviderFactory: (String) -> any NotionDestinationProviding
    private let registry: NotionSyncRegistry
    private let publisher: (any NotionLibraryPublishing)?
    private let restorer: (any NotionLibraryRestoring)?
    private let automaticSyncDelay: Duration
    let meetingLinkCoordinator: (any NotionMeetingLinkCoordinating)?
    let meetingPollInterval: Duration
    private var connection: NotionStoredConnection?
    private var destinationProvider: (any NotionDestinationProviding)?
    private var pendingAutomaticSync: LibraryState?
    private var automaticSyncInFlight: LibraryState?
    private var automaticSyncTask: Task<Void, Never>?
    private var automaticSyncGeneration = 0
#if DEBUG
    private var isUITestStateLocked = false
#endif
    var meetingLinkTask: Task<Void, Never>?
    var meetingNotebookID: NotebookID?
    var meetingLibrary: LibraryState?
    var dismissedMeetingIDs: Set<String> = []

    var workspaceName: String? {
        connection?.credentials.workspaceName
    }

    init(
        isConfigured: Bool,
        connectionManager: any NotionConnectionManaging,
        destinationProviderFactory: @escaping (String) -> any NotionDestinationProviding = {
            NotionAPIClient(accessToken: $0)
        },
        registry: NotionSyncRegistry,
        publisher: (any NotionLibraryPublishing)? = nil,
        restorer: (any NotionLibraryRestoring)? = nil,
        automaticSyncDelay: Duration = .seconds(2),
        meetingLinkCoordinator: (any NotionMeetingLinkCoordinating)? = nil,
        meetingPollInterval: Duration = .seconds(30)
    ) {
        self.isConfigured = isConfigured
        self.connectionManager = connectionManager
        self.destinationProviderFactory = destinationProviderFactory
        self.registry = registry
        self.publisher = publisher
        self.restorer = restorer
        self.automaticSyncDelay = automaticSyncDelay
        self.meetingLinkCoordinator = meetingLinkCoordinator
        self.meetingPollInterval = meetingPollInterval
        state = isConfigured ? .disconnected : .unavailable
    }

    func restore(library: LibraryState? = nil) async {
#if DEBUG
        if isUITestStateLocked { return }
#endif
        guard isConfigured else { return }
        do {
            guard let stored = try connectionManager.currentConnection() else {
                state = .disconnected
                return
            }
            try await applyConnection(stored)
            if let library {
                try await resumeQueuedSync(library)
                scheduleAutomaticSync(library)
            }
        } catch {
            showFailure("Your Notion connection could not be opened.")
        }
    }

    func retry(library: LibraryState) async {
        await restore()
        guard case .connected = state else { return }
        await sync(library)
    }

    func connect() async {
        guard isConfigured else {
            state = .unavailable
            return
        }
        state = .connecting
        failureMessage = nil
        do {
            let stored = try await connectionManager.connect()
            try await applyConnection(stored)
        } catch NotionOAuthError.callbackCancelled {
            state = .disconnected
        } catch {
            showFailure("Note Nerds could not connect to Notion.")
        }
    }

    func reloadPages(query: String? = nil) async {
        guard let destinationProvider else { return }
        do {
            pages = try await destinationProvider.searchPages(query: query)
        } catch {
            showFailure("Accessible Notion pages could not be retrieved.")
        }
    }

    func selectDestination(
        parentPage: NotionPageSummary,
        library: LibraryState
    ) async {
        guard let connection, let destinationProvider else { return }
        state = .selectingDestination
        failureMessage = nil
        do {
            let selected = try await destinationProvider.createDatabase(parentPageID: parentPage.id)
            let manifestPage = try await destinationProvider.createLibraryManifestPage(
                parentPageID: parentPage.id
            )
            try await registry.setDestination(
                workspaceID: connection.credentials.workspaceID,
                destination: selected,
                manifestPageID: manifestPage.pageID
            )
            destination = selected
            state = .connected(workspaceName: connection.credentials.workspaceName)
        } catch {
            showFailure("The Note Nerds database could not be created in Notion.")
            return
        }
        scheduleAutomaticSync(library)
        resumeMeetingLinks()
    }

    func disconnect() async {
        guard isConfigured else { return }
        state = .disconnecting
        closeNotebookMeetingLinks()
        failureMessage = nil
        do {
            try await registry.reset()
            try await connectionManager.disconnect()
            connection = nil
            destinationProvider = nil
            pages = []
            destination = nil
            restoreCandidates = []
            syncedNotebookIDs = []
            state = .disconnected
        } catch {
            showFailure("Notion could not be disconnected. Try again.")
        }
    }

    func sync(_ library: LibraryState, notebookID: NotebookID? = nil) async {
        await performSync(
            library,
            notebookID: notebookID,
            shouldReconcileRemotePages: true
        )
    }

    private func performSync(
        _ library: LibraryState,
        notebookID: NotebookID?,
        shouldReconcileRemotePages: Bool
    ) async {
        guard destination != nil, let publisher else { return }
        state = .syncing
        failureMessage = nil
        do {
            let report: NotionPublishReport
            if shouldReconcileRemotePages {
                report = try await publisher.reconcile(library, notebookID: notebookID)
            } else {
                report = try await publisher.publish(library, notebookID: notebookID)
            }
            lastSyncSummary = Self.syncSummary(report)
            try await refreshSyncedNotebookIDs()
            if let connection {
                state = .connected(workspaceName: connection.credentials.workspaceName)
            }
        } catch is CancellationError {
            if let connection {
                state = .connected(workspaceName: connection.credentials.workspaceName)
            }
        } catch let error as NotionAPIError where error.statusCode == 404 {
            showFailure("A Notion notebook page is missing. Tap Sync now to create a replacement.")
        } catch {
            showFailure(Self.syncFailureMessage(error))
        }
    }

    func scheduleAutomaticSync(_ library: LibraryState) {
#if DEBUG
        if isUITestStateLocked { return }
#endif
        scheduleAutomaticSync(library, delay: automaticSyncDelay)
    }

    private func scheduleAutomaticSync(_ library: LibraryState, delay: Duration) {
        guard destination != nil, publisher != nil else { return }
        pendingAutomaticSync = library
        guard automaticSyncTask == nil else { return }
        automaticSyncGeneration += 1
        let generation = automaticSyncGeneration
        automaticSyncTask = Task { [weak self] in
            await self?.runAutomaticSync(generation: generation, delay: delay)
        }
    }

    func pauseAutomaticSync() {
        if let automaticSyncInFlight {
            pendingAutomaticSync = automaticSyncInFlight
        }
        automaticSyncGeneration += 1
        automaticSyncTask?.cancel()
        automaticSyncTask = nil
        automaticSyncInFlight = nil
    }

    func resumeAutomaticSync() {
        guard let pendingAutomaticSync else { return }
        scheduleAutomaticSync(pendingAutomaticSync)
    }

    func isSynced(_ notebookID: NotebookID) -> Bool {
        syncedNotebookIDs.contains(notebookID.rawValue.uuidString.lowercased())
    }

    func pageURL(for notebookID: NotebookID) async -> URL? {
        guard let binding = try? await registry.snapshot().binding(
            notebookID: notebookID.rawValue.uuidString.lowercased()
        ) else { return nil }
        let compactID = binding.pageID.replacingOccurrences(of: "-", with: "")
        return URL(string: "https://www.notion.so/\(compactID)")
    }

    func prepareRestore(local: LibraryState) async -> [NotionRestoreCandidate] {
        guard destination != nil, let restorer else { return [] }
        state = .preparingRestore
        failureMessage = nil
        do {
            restoreCandidates = try await restorer.prepare(local: local)
            state = .reviewingRestore
            return restoreCandidates
        } catch {
            showFailure("Your Notion notebooks could not be prepared for restore.")
            return []
        }
    }

    func completeRestore(
        local: LibraryState,
        choices: [NotebookID: NotionRestoreChoice]
    ) -> LibraryState? {
        guard let restorer else { return nil }
        state = .restoring
        do {
            let restored = try restorer.complete(
                local: local,
                choices: choices
            )
            restoreCandidates = []
            if let connection {
                state = .connected(workspaceName: connection.credentials.workspaceName)
            }
            return restored
        } catch {
            showFailure("The selected notebooks could not be restored.")
            return nil
        }
    }

    private func applyConnection(_ stored: NotionStoredConnection) async throws {
        connection = stored
        destinationProvider = destinationProviderFactory(stored.credentials.accessToken)
        let savedState = try await registry.snapshot()
        destination = savedState.workspaceID == stored.credentials.workspaceID
            ? savedState.destination
            : nil
        syncedNotebookIDs = Set(savedState.bindings.map(\.notebookID))
        state = .connected(workspaceName: stored.credentials.workspaceName)
        await reloadPages()
    }

    private func resumeQueuedSync(_ library: LibraryState) async throws {
        let currentDate = Date()
        let queue = try await registry.snapshot().queue
        let retryable = queue.filter { item in
            item.attemptCount == 0 || item.nextAttemptAt != nil
        }
        guard !retryable.isEmpty else { return }
        let nextDate = retryable.compactMap(\.nextAttemptAt).min() ?? currentDate
        let wait = max(0, nextDate.timeIntervalSince(currentDate))
        scheduleAutomaticSync(library, delay: wait > 0 ? .seconds(wait) : automaticSyncDelay)
    }

    private func showFailure(_ message: String) {
        failureMessage = message
        state = .actionNeeded
    }

    private static func syncFailureMessage(_ error: Error) -> String {
        if let apiError = error as? NotionAPIError {
            return apiError.userFacingMessage ?? "Notion returned an unreadable response."
        }
        if let pageError = error as? NotionManagedPageError {
            return switch pageError {
            case .textTooLarge: "A notebook contains more text than Notion accepts."
            case .missingPreview: "A canvas preview could not be prepared for Notion."
            }
        }
        if error is DecodingError {
            return "Notion returned data that Note Nerds could not read."
        }
        if error is NotionSyncStateError {
            return "Saved Notion sync information could not be read. Disconnect Notion and reconnect."
        }
        if error is NotionOAuthError {
            return "The Notion connection is no longer valid. Disconnect Notion and reconnect."
        }
        return "Note Nerds could not prepare the Notion update. Disconnect Notion and reconnect."
    }

#if DEBUG
    func configureDestinationSelectionForUITesting() {
        let credentials = NotionOAuthCredentials(
            accessToken: "ui-test-access",
            refreshToken: "ui-test-refresh",
            workspaceID: "ui-test-workspace",
            workspaceName: "Personal",
            workspaceIcon: nil,
            botID: "ui-test-bot"
        )
        isUITestStateLocked = true
        connection = NotionStoredConnection(credentials: credentials, connectedAt: Date())
        destinationProvider = NotionDestinationSelectionUITestProvider()
        pages = [NotionPageSummary(
            id: "33333333-3333-3333-3333-333333333333",
            title: "Product",
            url: nil
        )]
        destination = nil
        state = .connected(workspaceName: credentials.workspaceName)
    }

    func configureForUITesting(
        state: NotionIntegrationState,
        destination: NotionDestination?,
        failureMessage: String? = nil
    ) {
        isUITestStateLocked = true
        self.state = state
        self.destination = destination
        self.failureMessage = failureMessage
    }
#endif

    private func takePendingAutomaticSync() -> LibraryState? {
        defer { pendingAutomaticSync = nil }
        return pendingAutomaticSync
    }

    private func runAutomaticSync(generation: Int, delay: Duration) async {
        var nextDelay = delay
        var retryLibrary: LibraryState?
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: nextDelay)
            } catch {
                return
            }
            guard automaticSyncGeneration == generation else { return }
            guard let library = takePendingAutomaticSync() ?? retryLibrary else { break }
            automaticSyncInFlight = library
            await performSync(
                library,
                notebookID: nil,
                shouldReconcileRemotePages: false
            )
            guard automaticSyncGeneration == generation else { return }
            automaticSyncInFlight = nil
            if pendingAutomaticSync != nil {
                retryLibrary = nil
                nextDelay = .zero
            } else if let retryDelay = await automaticRetryDelay() {
                retryLibrary = library
                nextDelay = retryDelay
            } else {
                retryLibrary = nil
                break
            }
        }
        guard automaticSyncGeneration == generation else { return }
        automaticSyncTask = nil
    }

    private func automaticRetryDelay() async -> Duration? {
        guard let state = try? await registry.snapshot(),
              let nextAttempt = state.queue.compactMap(\.nextAttemptAt).min() else {
            return nil
        }
        return .seconds(max(0, nextAttempt.timeIntervalSinceNow))
    }

    private func refreshSyncedNotebookIDs() async throws {
        syncedNotebookIDs = Set(try await registry.snapshot().bindings.map(\.notebookID))
    }

    private static func syncSummary(_ report: NotionPublishReport) -> String {
        if report.uploadedNotebookCount == 0, report.deletedNotebookCount == 0 {
            return "Notion is up to date."
        }
        if report.uploadedNotebookCount == 0 {
            let noun = report.deletedNotebookCount == 1 ? "notebook" : "notebooks"
            return "Moved \(report.deletedNotebookCount) \(noun) to Notion Trash."
        }
        let uploadedNoun = report.uploadedNotebookCount == 1 ? "notebook" : "notebooks"
        guard report.deletedNotebookCount > 0 else {
            return "Sent \(report.uploadedNotebookCount) \(uploadedNoun) to Notion."
        }
        let deletedNoun = report.deletedNotebookCount == 1 ? "notebook" : "notebooks"
        return "Sent \(report.uploadedNotebookCount) \(uploadedNoun) and moved "
            + "\(report.deletedNotebookCount) \(deletedNoun) to Notion Trash."
    }
}

#if DEBUG
private actor NotionDestinationSelectionUITestProvider: NotionDestinationProviding {
    func searchPages(query: String?) -> [NotionPageSummary] { [] }

    func createDatabase(parentPageID: String) async throws -> NotionDestination {
        try await Task.sleep(for: .seconds(3))
        return NotionDestination(
            parentPageID: parentPageID,
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            databaseName: "Note Nerds"
        )
    }

    func createLibraryManifestPage(parentPageID: String) -> NotionPageBinding {
        NotionPageBinding(
            pageID: "55555555-5555-5555-5555-555555555555",
            url: nil
        )
    }
}
#endif
