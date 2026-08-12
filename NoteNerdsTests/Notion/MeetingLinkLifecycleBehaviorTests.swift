import XCTest
@testable import NoteNerds

@MainActor
final class MeetingLinkLifecycleBehaviorTests: XCTestCase {
    func testOpeningNotebookChecksTheActiveMeetingWithoutPublishing() async throws {
        let fixture = await makeFixture(results: [.linked(meetingTitle: "Weekly planning")])

        fixture.model.openNotebook(fixture.first.id, library: fixture.library)
        await fixture.meetingLinks.waitForCheckCount(1)
        let checkedIDs = await fixture.meetingLinks.checkedNotebookIDs

        XCTAssertTrue(fixture.publisher.selectedNotebookIDs.isEmpty)
        XCTAssertEqual(checkedIDs, [fixture.first.id.rawValue.uuidString.lowercased()])
        XCTAssertEqual(
            fixture.model.meetingLinkMessage,
            "Linked to the active Notion meeting note."
        )
    }

    func testSeveralMeetingsShowChoicesAndClosingNotebookStopsPolling() async throws {
        let meetings = [
            meeting(id: "11111111-1111-1111-1111-111111111111", title: "One"),
            meeting(id: "22222222-2222-2222-2222-222222222222", title: "Two")
        ]
        let fixture = await makeFixture(
            results: [.needsSelection(meetings)],
            interval: .milliseconds(20)
        )

        fixture.model.openNotebook(fixture.first.id, library: fixture.library)
        await fixture.meetingLinks.waitForCheckCount(1)
        XCTAssertEqual(fixture.model.meetingChoices, meetings)
        fixture.model.closeNotebookMeetingLinks()
        try await Task.sleep(for: .milliseconds(50))
        let checkCount = await fixture.meetingLinks.checkedNotebookIDs.count

        XCTAssertTrue(fixture.model.meetingChoices.isEmpty)
        XCTAssertEqual(checkCount, 1)
    }

    func testSwitchingNotebooksCancelsTheOldCheckAndStartsTheNewNotebook() async throws {
        let fixture = await makeFixture(results: [.noActiveMeeting, .noActiveMeeting])

        fixture.model.openNotebook(fixture.first.id, library: fixture.library)
        await fixture.meetingLinks.waitForCheckCount(1)
        fixture.model.openNotebook(fixture.second.id, library: fixture.library)
        try await Task.sleep(for: .milliseconds(30))
        let checkedIDs = await fixture.meetingLinks.checkedNotebookIDs

        XCTAssertEqual(checkedIDs, [
            fixture.first.id.rawValue.uuidString.lowercased(),
            fixture.second.id.rawValue.uuidString.lowercased()
        ])
    }

    private func makeFixture(
        results: [NotionMeetingLinkResult],
        interval: Duration = .seconds(30)
    ) async -> LifecycleFixture {
        let first = DomainFixtures.notebook()
        let second = DomainFixtures.notebook(
            id: NotebookID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
            title: "Second"
        )
        let connection = storedConnection()
        let destination = NotionDestination(
            databaseID: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            dataSourceID: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        )
        let publisher = LifecyclePublisher()
        let meetingLinks = LifecycleMeetingCoordinator(results: results)
        let model = NotionIntegrationModel(
            isConfigured: true,
            connectionManager: LifecycleConnectionManager(connection: connection),
            destinationProviderFactory: { _ in LifecycleDestinationProvider() },
            registry: NotionSyncRegistry(store: LifecycleStateStore(state: NotionSyncState(
                workspaceID: connection.credentials.workspaceID,
                destination: destination
            ))),
            publisher: publisher,
            meetingLinkCoordinator: meetingLinks,
            meetingPollInterval: interval
        )
        await model.restore()
        return LifecycleFixture(
            model: model,
            publisher: publisher,
            meetingLinks: meetingLinks,
            library: LibraryState(notebooks: [first, second]),
            first: first,
            second: second
        )
    }

    private func meeting(id: String, title: String) -> NotionMeetingNote {
        NotionMeetingNote(
            id: id,
            parentBlockID: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
            title: title,
            status: .transcriptionInProgress,
            lastEditedAt: DomainFixtures.fixedDate,
            recordingStartedAt: DomainFixtures.fixedDate
        )
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

private struct LifecycleFixture {
    let model: NotionIntegrationModel
    let publisher: LifecyclePublisher
    let meetingLinks: LifecycleMeetingCoordinator
    let library: LibraryState
    let first: Notebook
    let second: Notebook
}

@MainActor
private final class LifecyclePublisher: NotionLibraryPublishing {
    private(set) var selectedNotebookIDs: [NotebookID?] = []

    func publish(_ library: LibraryState, notebookID: NotebookID?) -> NotionPublishReport {
        selectedNotebookIDs.append(notebookID)
        return NotionPublishReport(
            uploadedNotebookCount: 1,
            skippedNotebookCount: 0,
            didUploadManifest: false
        )
    }
}

private actor LifecycleMeetingCoordinator: NotionMeetingLinkCoordinating {
    private var results: [NotionMeetingLinkResult]
    private(set) var checkedNotebookIDs: [String] = []

    init(results: [NotionMeetingLinkResult]) { self.results = results }

    func check(notebookID: String) -> NotionMeetingLinkResult {
        checkedNotebookIDs.append(notebookID)
        return results.isEmpty ? .noActiveMeeting : results.removeFirst()
    }

    func link(meetingID: String, notebookID: String) -> NotionMeetingLinkResult {
        .linked(meetingTitle: "Selected meeting")
    }

    func removeLinks(notebookID: String) {}

    func waitForCheckCount(_ count: Int) async {
        while checkedNotebookIDs.count < count { await Task.yield() }
    }
}

@MainActor
private final class LifecycleConnectionManager: NotionConnectionManaging {
    private let connection: NotionStoredConnection

    init(connection: NotionStoredConnection) { self.connection = connection }

    func currentConnection() -> NotionStoredConnection? { connection }
    func connect() -> NotionStoredConnection { connection }
    func refresh() -> NotionStoredConnection { connection }
    func disconnect() {}
}

private actor LifecycleDestinationProvider: NotionDestinationProviding {
    func searchPages(query: String?) -> [NotionPageSummary] { [] }
    func createDatabase(parentPageID: String) throws -> NotionDestination {
        throw NotionAPIError.invalidResponse
    }
    func createLibraryManifestPage(parentPageID: String) throws -> NotionPageBinding {
        throw NotionAPIError.invalidResponse
    }
}

private actor LifecycleStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?

    init(state: NotionSyncState?) { self.state = state }

    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}
