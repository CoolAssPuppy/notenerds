import XCTest
@testable import NoteNerds

@MainActor
final class NotionConnectionResetBehaviorTests: XCTestCase {
    func testDisconnectRemovesCredentialsAndAllSavedNotionState() async throws {
        let connection = resetConnection()
        let notebookID = UUID().uuidString.lowercased()
        let destination = resetDestination()
        let store = ResetNotionStateStore(state: NotionSyncState(
            workspaceID: connection.credentials.workspaceID,
            destination: destination,
            manifestPageID: UUID().uuidString,
            manifestRootBlockID: UUID().uuidString,
            manifestContentHash: String(repeating: "a", count: 64),
            bindings: [NotionNotebookBinding(
                notebookID: notebookID,
                pageID: UUID().uuidString,
                managedRootBlockID: UUID().uuidString,
                contentHash: String(repeating: "b", count: 64),
                syncedAt: DomainFixtures.fixedDate,
                notionLastEditedAt: nil
            )],
            queue: [NotionSyncQueueItem(
                notebookID: notebookID,
                enqueuedAt: DomainFixtures.fixedDate,
                attemptCount: 1,
                nextAttemptAt: nil,
                lastFailure: .validation
            )],
            meetingLinks: [NotionMeetingNotebookLink(
                meetingBlockID: UUID().uuidString,
                notebookID: notebookID,
                notebookPageID: UUID().uuidString,
                linkBlockID: UUID().uuidString,
                createdAt: DomainFixtures.fixedDate,
                wasRemovedByUser: false
            )]
        ))
        let registry = NotionSyncRegistry(store: store)
        let manager = ResetConnectionManager(connection: connection)
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: manager,
            destinationProviderFactory: { _ in ResetDestinationProvider() },
            registry: registry
        )
        await model.restore()

        await model.disconnect()
        let savedState = try await registry.snapshot()

        XCTAssertEqual(model.state, .disconnected)
        XCTAssertFalse(manager.hasConnection)
        XCTAssertEqual(savedState, NotionSyncState())
    }

    func testPreparationFailureExplainsWhyNotionSyncStopped() async {
        let connection = resetConnection()
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: ResetConnectionManager(connection: connection),
            destinationProviderFactory: { _ in ResetDestinationProvider() },
            registry: NotionSyncRegistry(store: ResetNotionStateStore(state: NotionSyncState(
                workspaceID: connection.credentials.workspaceID,
                destination: resetDestination()
            ))),
            publisher: FailingResetPublisher()
        )
        await model.restore()

        await model.sync(LibraryState(notebooks: [DomainFixtures.notebook()]))

        XCTAssertEqual(model.state, .actionNeeded)
        XCTAssertEqual(
            model.failureMessage,
            "A notebook contains more text than Notion accepts."
        )
    }

    private func resetConnection() -> NotionStoredConnection {
        NotionStoredConnection(
            credentials: NotionOAuthCredentials(
                accessToken: "access",
                refreshToken: "refresh",
                workspaceID: "personal-workspace",
                workspaceName: "Personal",
                workspaceIcon: nil,
                botID: "bot"
            ),
            connectedAt: DomainFixtures.fixedDate
        )
    }

    private func resetDestination() -> NotionDestination {
        NotionDestination(databaseID: UUID().uuidString, dataSourceID: UUID().uuidString)
    }
}

@MainActor
private final class ResetConnectionManager: NotionConnectionManaging {
    private var connection: NotionStoredConnection?

    init(connection: NotionStoredConnection) {
        self.connection = connection
    }

    var hasConnection: Bool { connection != nil }

    func currentConnection() -> NotionStoredConnection? { connection }
    func connect() async throws -> NotionStoredConnection { try XCTUnwrap(connection) }
    func refresh() async throws -> NotionStoredConnection { try XCTUnwrap(connection) }
    func disconnect() { connection = nil }
}

private actor ResetDestinationProvider: NotionDestinationProviding {
    func searchPages(query: String?) -> [NotionPageSummary] { [] }
    func createDatabase(parentPageID: String) -> NotionDestination { resetDestination() }
    func createLibraryManifestPage(parentPageID: String) -> NotionPageBinding {
        NotionPageBinding(pageID: UUID().uuidString, url: nil)
    }
}

@MainActor
private final class FailingResetPublisher: NotionLibraryPublishing {
    func publish(
        _ library: LibraryState,
        notebookID: NotebookID?
    ) async throws -> NotionPublishReport {
        throw NotionManagedPageError.textTooLarge
    }
}

private actor ResetNotionStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?

    init(state: NotionSyncState?) {
        self.state = state
    }

    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}

private func resetDestination() -> NotionDestination {
    NotionDestination(databaseID: UUID().uuidString, dataSourceID: UUID().uuidString)
}
