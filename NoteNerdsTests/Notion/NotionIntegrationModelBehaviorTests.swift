import XCTest
@testable import NoteNerds

@MainActor
final class NotionIntegrationModelBehaviorTests: XCTestCase {
    func testConnectShowsWorkspaceAndLoadsAccessiblePages() async throws {
        let connection = storedConnection()
        let connectionManager = StubConnectionManager(current: nil, connected: connection)
        let destinationProvider = StubDestinationProvider()
        let registry = NotionSyncRegistry(store: IntegrationStateStore())
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: connectionManager,
            destinationProviderFactory: { _ in destinationProvider },
            registry: registry
        )

        await model.connect()

        XCTAssertEqual(model.state, .connected(workspaceName: "Strategic Nerds"))
        XCTAssertEqual(model.pages.map(\.title), ["Product", "Personal"])
        XCTAssertNil(model.failureMessage)
        XCTAssertEqual(connectionManager.connectCount, 1)
    }

    func testSelectingParentCreatesDestinationPersistsItAndPublishesCurrentLibrary() async throws {
        let connection = storedConnection()
        let connectionManager = StubConnectionManager(current: connection, connected: connection)
        let provider = StubDestinationProvider()
        let registry = NotionSyncRegistry(store: IntegrationStateStore())
        let publisher = StubLibraryPublisher(report: NotionPublishReport(
            uploadedNotebookCount: 1,
            skippedNotebookCount: 0,
            didUploadManifest: true
        ))
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: connectionManager,
            destinationProviderFactory: { _ in provider },
            registry: registry,
            publisher: publisher
        )
        await model.restore()
        let page = try XCTUnwrap(model.pages.first)
        let library = LibraryState(notebooks: [DomainFixtures.notebook()])

        await model.selectDestination(parentPage: page, library: library)
        let state = try await registry.snapshot()
        let expectedDestination = provider.destination
        let createdParentIDs = await provider.createdParentIDs

        XCTAssertEqual(model.destination, expectedDestination)
        XCTAssertEqual(model.state, .connected(workspaceName: "Strategic Nerds"))
        XCTAssertEqual(state.workspaceID, connection.credentials.workspaceID)
        XCTAssertEqual(state.destination, expectedDestination)
        XCTAssertEqual(state.manifestPageID, provider.manifestPage.pageID)
        XCTAssertEqual(createdParentIDs, [page.id, page.id])
        XCTAssertEqual(publisher.publishedLibraries, [library])
        XCTAssertEqual(model.lastSyncSummary, "Sent 1 notebook to Notion.")
    }

    func testDisconnectRevokesConnectionAndClearsVisibleWorkspaceData() async {
        let connection = storedConnection()
        let manager = StubConnectionManager(current: connection, connected: connection)
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: manager,
            destinationProviderFactory: { _ in StubDestinationProvider() },
            registry: NotionSyncRegistry(store: IntegrationStateStore())
        )
        await model.restore()

        await model.disconnect()

        XCTAssertEqual(model.state, .disconnected)
        XCTAssertEqual(model.pages, [])
        XCTAssertNil(model.destination)
        XCTAssertEqual(manager.disconnectCount, 1)
    }

    func testSyncNowPublishesTheCurrentLibraryAndReportsCompletion() async throws {
        let connection = storedConnection()
        let provider = StubDestinationProvider()
        let destination = provider.destination
        let publisher = StubLibraryPublisher(
            report: NotionPublishReport(
                uploadedNotebookCount: 2,
                skippedNotebookCount: 1,
                didUploadManifest: true
            )
        )
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: StubConnectionManager(current: connection, connected: connection),
            destinationProviderFactory: { _ in provider },
            registry: NotionSyncRegistry(store: IntegrationStateStore(state: NotionSyncState(
                workspaceID: connection.credentials.workspaceID,
                destination: destination
            ))),
            publisher: publisher
        )
        await model.restore()
        let library = LibraryState(notebooks: [DomainFixtures.notebook()])

        await model.sync(library)

        XCTAssertEqual(model.state, .connected(workspaceName: "Strategic Nerds"))
        XCTAssertEqual(model.lastSyncSummary, "Sent 2 notebooks to Notion.")
        XCTAssertEqual(publisher.publishedLibraries, [library])
    }

    func testMissingBuildConfigurationIsUnavailableAndDoesNotAttemptOAuth() async {
        let manager = StubConnectionManager(current: nil, connected: storedConnection())
        let model = NotionIntegrationModel(
            isConfigured: false,
            connectionManager: manager,
            destinationProviderFactory: { _ in StubDestinationProvider() },
            registry: NotionSyncRegistry(store: IntegrationStateStore())
        )

        await model.connect()

        XCTAssertEqual(model.state, .unavailable)
        XCTAssertEqual(manager.connectCount, 0)
    }

    func testPauseAfterRapidResumeCancelsTheCurrentAutomaticSync() async throws {
        let connection = storedConnection()
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let publisher = CancellableLibraryPublisher()
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: StubConnectionManager(current: connection, connected: connection),
            destinationProviderFactory: { _ in StubDestinationProvider() },
            registry: NotionSyncRegistry(store: IntegrationStateStore(state: NotionSyncState(
                workspaceID: connection.credentials.workspaceID,
                destination: destination
            ))),
            publisher: publisher,
            automaticSyncDelay: .milliseconds(10)
        )
        await model.restore()
        let library = LibraryState(notebooks: [DomainFixtures.notebook()])

        model.scheduleAutomaticSync(library)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(publisher.startedCount, 1)
        model.pauseAutomaticSync()
        model.resumeAutomaticSync()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(publisher.startedCount, 2)

        model.pauseAutomaticSync()
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(publisher.cancelledCount, 2)
    }

    func testRestoreResumesPersistedQueuedSyncForTheCurrentLibrary() async throws {
        let connection = storedConnection()
        let notebook = DomainFixtures.notebook()
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let queueItem = NotionSyncQueueItem(
            notebookID: notebook.id.rawValue.uuidString.lowercased(),
            enqueuedAt: DomainFixtures.fixedDate,
            attemptCount: 1,
            nextAttemptAt: Date(timeIntervalSince1970: 0),
            lastFailure: .serviceUnavailable
        )
        let registry = NotionSyncRegistry(store: IntegrationStateStore(state: NotionSyncState(
            workspaceID: connection.credentials.workspaceID,
            destination: destination,
            queue: [queueItem]
        )))
        let publisher = SuccessfulRegistryLibraryPublisher(
            registry: registry,
            notebookID: notebook.id
        )
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: StubConnectionManager(current: connection, connected: connection),
            destinationProviderFactory: { _ in StubDestinationProvider() },
            registry: registry,
            publisher: publisher,
            automaticSyncDelay: .milliseconds(1)
        )
        let library = LibraryState(notebooks: [notebook])

        await model.restore(library: library)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(publisher.publishedLibraries, [library])
        let snapshot = try await registry.snapshot()
        XCTAssertTrue(snapshot.queue.isEmpty)
    }

    func testRestoreReconcilesTheCurrentLibraryWhenDestinationHasNoQueue() async throws {
        let connection = storedConnection()
        let notebook = DomainFixtures.notebook()
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let publisher = StubLibraryPublisher(report: NotionPublishReport(
            uploadedNotebookCount: 1,
            skippedNotebookCount: 0,
            didUploadManifest: false
        ))
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: StubConnectionManager(current: connection, connected: connection),
            destinationProviderFactory: { _ in StubDestinationProvider() },
            registry: NotionSyncRegistry(store: IntegrationStateStore(state: NotionSyncState(
                workspaceID: connection.credentials.workspaceID,
                destination: destination
            ))),
            publisher: publisher,
            automaticSyncDelay: .milliseconds(1)
        )
        let library = LibraryState(notebooks: [notebook])

        await model.restore(library: library)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(publisher.publishedLibraries, [library])
    }

    func testAutomaticSyncRetriesDurableTransientFailureWithoutAnotherEdit() async throws {
        let connection = storedConnection()
        let notebook = DomainFixtures.notebook()
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let registry = NotionSyncRegistry(store: IntegrationStateStore(state: NotionSyncState(
            workspaceID: connection.credentials.workspaceID,
            destination: destination
        )))
        let publisher = TransientFailureLibraryPublisher(
            registry: registry,
            notebookID: notebook.id
        )
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: StubConnectionManager(current: connection, connected: connection),
            destinationProviderFactory: { _ in StubDestinationProvider() },
            registry: registry,
            publisher: publisher,
            automaticSyncDelay: .milliseconds(1)
        )
        let library = LibraryState(notebooks: [notebook])

        await model.restore(library: library)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(publisher.attemptCount, 2)
        let snapshot = try await registry.snapshot()
        XCTAssertTrue(snapshot.queue.isEmpty)
        XCTAssertEqual(model.state, .connected(workspaceName: "Strategic Nerds"))
    }

    private func storedConnection() -> NotionStoredConnection {
        NotionStoredConnection(
            credentials: NotionOAuthCredentials(
                accessToken: "access",
                refreshToken: "refresh",
                workspaceID: "workspace-id",
                workspaceName: "Strategic Nerds",
                workspaceIcon: nil,
                botID: "bot"
            ),
            connectedAt: DomainFixtures.fixedDate
        )
    }
}

@MainActor
private final class StubLibraryPublisher: NotionLibraryPublishing {
    private let report: NotionPublishReport
    private(set) var publishedLibraries: [LibraryState] = []

    init(report: NotionPublishReport) { self.report = report }

    func publish(
        _ library: LibraryState,
        notebookID: NotebookID?
    ) async throws -> NotionPublishReport {
        publishedLibraries.append(library)
        return report
    }
}

@MainActor
private final class CancellableLibraryPublisher: NotionLibraryPublishing {
    private(set) var startedCount = 0
    private(set) var cancelledCount = 0

    func publish(
        _ library: LibraryState,
        notebookID: NotebookID?
    ) async throws -> NotionPublishReport {
        startedCount += 1
        do {
            try await Task.sleep(for: .seconds(1))
        } catch is CancellationError {
            cancelledCount += 1
            throw CancellationError()
        }
        return NotionPublishReport(
            uploadedNotebookCount: 0,
            skippedNotebookCount: library.notebooks.count,
            didUploadManifest: false
        )
    }
}

@MainActor
private final class TransientFailureLibraryPublisher: NotionLibraryPublishing {
    private let registry: NotionSyncRegistry
    private let notebookID: NotebookID
    private(set) var attemptCount = 0

    init(registry: NotionSyncRegistry, notebookID: NotebookID) {
        self.registry = registry
        self.notebookID = notebookID
    }

    func publish(
        _ library: LibraryState,
        notebookID selectedNotebookID: NotebookID?
    ) async throws -> NotionPublishReport {
        attemptCount += 1
        let identifier = notebookID.rawValue.uuidString.lowercased()
        if attemptCount == 1 {
            try await registry.enqueue(notebookID: identifier)
            try await registry.recordFailure(
                notebookID: identifier,
                failure: .serviceUnavailable,
                retryAt: Date()
            )
            throw NotionAPIError.httpStatus(503)
        }
        try await registry.recordSuccess(NotionNotebookBinding(
            notebookID: identifier,
            pageID: "33333333-3333-3333-3333-333333333333",
            managedRootBlockID: "44444444-4444-4444-4444-444444444444",
            contentHash: String(repeating: "a", count: 64),
            syncedAt: Date(),
            notionLastEditedAt: nil
        ))
        return NotionPublishReport(
            uploadedNotebookCount: 1,
            skippedNotebookCount: 0,
            didUploadManifest: false
        )
    }
}

@MainActor
private final class SuccessfulRegistryLibraryPublisher: NotionLibraryPublishing {
    private let registry: NotionSyncRegistry
    private let notebookID: NotebookID
    private(set) var publishedLibraries: [LibraryState] = []

    init(registry: NotionSyncRegistry, notebookID: NotebookID) {
        self.registry = registry
        self.notebookID = notebookID
    }

    func publish(
        _ library: LibraryState,
        notebookID selectedNotebookID: NotebookID?
    ) async throws -> NotionPublishReport {
        publishedLibraries.append(library)
        try await registry.recordSuccess(NotionNotebookBinding(
            notebookID: notebookID.rawValue.uuidString.lowercased(),
            pageID: "33333333-3333-3333-3333-333333333333",
            managedRootBlockID: nil,
            contentHash: String(repeating: "a", count: 64),
            syncedAt: Date(),
            notionLastEditedAt: nil
        ))
        return NotionPublishReport(
            uploadedNotebookCount: 1,
            skippedNotebookCount: 0,
            didUploadManifest: false
        )
    }
}

@MainActor
private final class StubConnectionManager: NotionConnectionManaging {
    private var current: NotionStoredConnection?
    private let connected: NotionStoredConnection
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0

    init(current: NotionStoredConnection?, connected: NotionStoredConnection) {
        self.current = current
        self.connected = connected
    }

    func currentConnection() throws -> NotionStoredConnection? { current }

    func connect() async throws -> NotionStoredConnection {
        connectCount += 1
        current = connected
        return connected
    }

    func refresh() async throws -> NotionStoredConnection { connected }

    func disconnect() async throws {
        disconnectCount += 1
        current = nil
    }
}

private actor StubDestinationProvider: NotionDestinationProviding {
    let destination = NotionDestination(
        databaseID: "11111111-1111-1111-1111-111111111111",
        dataSourceID: "22222222-2222-2222-2222-222222222222"
    )
    private(set) var createdParentIDs: [String] = []
    let manifestPage = NotionPageBinding(
        pageID: "55555555-5555-5555-5555-555555555555",
        url: nil
    )

    func searchPages(query: String?) -> [NotionPageSummary] {
        [
            NotionPageSummary(
                id: "33333333-3333-3333-3333-333333333333",
                title: "Product",
                url: nil
            ),
            NotionPageSummary(
                id: "44444444-4444-4444-4444-444444444444",
                title: "Personal",
                url: nil
            )
        ]
    }

    func createDatabase(parentPageID: String) -> NotionDestination {
        createdParentIDs.append(parentPageID)
        return destination
    }

    func createLibraryManifestPage(parentPageID: String) -> NotionPageBinding {
        createdParentIDs.append(parentPageID)
        return manifestPage
    }
}

private actor IntegrationStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?

    init(state: NotionSyncState? = nil) {
        self.state = state
    }

    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}
