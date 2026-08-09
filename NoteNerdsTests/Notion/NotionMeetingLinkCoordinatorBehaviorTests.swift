import XCTest
@testable import NoteNerds

final class MeetingLinkCoordinatorBehaviorTests: XCTestCase {
    func testOneActiveMeetingLinksOnceAndRepeatedChecksDoNotDuplicateIt() async throws {
        let fixture = makeFixture()

        let first = try await fixture.coordinator.check(notebookID: fixture.notebookID)
        let second = try await fixture.coordinator.check(notebookID: fixture.notebookID)
        let insertCount = await fixture.api.insertCount

        XCTAssertEqual(first, .linked(meetingTitle: "Weekly planning"))
        XCTAssertEqual(second, .alreadyLinked)
        XCTAssertEqual(insertCount, 1)
    }

    func testSeveralActiveMeetingsRequireSelection() async throws {
        let fixture = makeFixture(meetings: [
            meeting(id: "11111111-1111-1111-1111-111111111111", title: "One"),
            meeting(id: "22222222-2222-2222-2222-222222222222", title: "Two")
        ])

        let result = try await fixture.coordinator.check(notebookID: fixture.notebookID)
        let insertCount = await fixture.api.insertCount

        XCTAssertEqual(result, .needsSelection(fixture.api.meetings))
        XCTAssertEqual(insertCount, 0)
    }

    func testDeletedRemoteLinkIsRememberedAndNeverRecreated() async throws {
        let fixture = makeFixture()
        _ = try await fixture.coordinator.check(notebookID: fixture.notebookID)
        await fixture.api.removeAllLinks()

        let result = try await fixture.coordinator.check(notebookID: fixture.notebookID)
        let state = try await fixture.registry.snapshot()
        let insertCount = await fixture.api.insertCount

        XCTAssertEqual(result, .removedByUser)
        XCTAssertEqual(insertCount, 1)
        XCTAssertTrue(try XCTUnwrap(state.meetingLinks.first).wasRemovedByUser)
    }

    func testAccessDeniedBecomesPermissionRequired() async throws {
        let fixture = makeFixture(error: .httpStatus(403))

        let result = try await fixture.coordinator.check(notebookID: fixture.notebookID)

        XCTAssertEqual(result, .permissionRequired)
    }

    func testPermanentNotebookDeletionTrashesEverySavedMeetingLink() async throws {
        let fixture = makeFixture()
        _ = try await fixture.coordinator.check(notebookID: fixture.notebookID)

        try await fixture.coordinator.removeLinks(notebookID: fixture.notebookID)
        let state = try await fixture.registry.snapshot()
        let trashedIDs = await fixture.api.trashedIDs

        XCTAssertEqual(trashedIDs, ["EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"])
        XCTAssertTrue(state.meetingLinks.isEmpty)
    }

    private func makeFixture(
        meetings: [NotionMeetingNote]? = nil,
        error: NotionAPIError? = nil
    ) -> Fixture {
        let notebookID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let registry = NotionSyncRegistry(store: MeetingStateStore(state: NotionSyncState(bindings: [
            NotionNotebookBinding(
                notebookID: notebookID,
                pageID: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
                managedRootBlockID: nil,
                contentHash: String(repeating: "a", count: 64),
                syncedAt: Date(timeIntervalSince1970: 1),
                notionLastEditedAt: nil
            )
        ])))
        let api = MeetingAPIStub(meetings: meetings ?? [meeting()], error: error)
        return Fixture(
            notebookID: notebookID,
            api: api,
            registry: registry,
            coordinator: NotionMeetingLinkCoordinator(api: api, registry: registry)
        )
    }

    private func meeting(
        id: String = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
        title: String = "Weekly planning"
    ) -> NotionMeetingNote {
        NotionMeetingNote(
            id: id,
            parentBlockID: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
            title: title,
            status: .transcriptionInProgress,
            lastEditedAt: Date(timeIntervalSince1970: 10),
            recordingStartedAt: Date(timeIntervalSince1970: 5)
        )
    }
}

private struct Fixture {
    let notebookID: String
    let api: MeetingAPIStub
    let registry: NotionSyncRegistry
    let coordinator: NotionMeetingLinkCoordinator
}

private actor MeetingAPIStub: NotionMeetingLinkAPI {
    let meetings: [NotionMeetingNote]
    private let error: NotionAPIError?
    private(set) var links: [NotionNotebookLinkBlock] = []
    private(set) var insertCount = 0
    private(set) var trashedIDs: [String] = []

    init(meetings: [NotionMeetingNote], error: NotionAPIError?) {
        self.meetings = meetings
        self.error = error
    }

    func queryMeetingNotes() throws -> [NotionMeetingNote] {
        if let error { throw error }
        return meetings
    }

    func listNotebookLinks(parentBlockID: String) -> [NotionNotebookLinkBlock] { links }

    func insertNotebookLink(
        parentBlockID: String,
        afterBlockID: String,
        notebookPageID: String
    ) -> String {
        insertCount += 1
        let id = "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"
        links.append(NotionNotebookLinkBlock(id: id, pageID: notebookPageID))
        return id
    }

    func trashMeetingLink(blockID: String) { trashedIDs.append(blockID) }

    func removeAllLinks() { links = [] }
}

private actor MeetingStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?

    init(state: NotionSyncState?) { self.state = state }

    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}
