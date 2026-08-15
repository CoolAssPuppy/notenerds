import XCTest
@testable import NoteNerds

final class NotionAuthenticatedAPIBehaviorTests: XCTestCase {
    func testUnauthorizedRequestRefreshesOnceAndReplaysWithRotatedAccessToken() async throws {
        let store = AuthCredentialStore(connection: connection(access: "expired"))
        let recorder = TokenRecorder()
        let refresh = RefreshRecorder(store: store, result: connection(access: "rotated"))
        let api = NotionRefreshingAPI(
            credentialStore: store,
            refresh: { try await refresh.run() },
            apiFactory: { token in TokenAwareSyncAPI(token: token, recorder: recorder) }
        )

        let uploadID = try await api.uploadFile(
            data: Data("file".utf8),
            filename: "file.pdf",
            contentType: "application/pdf"
        )
        let tokens = await recorder.tokens
        let refreshCount = await refresh.count

        XCTAssertEqual(uploadID, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(tokens, ["expired", "rotated"])
        XCTAssertEqual(refreshCount, 1)
    }

    func testSecondUnauthorizedResponseDoesNotStartAnotherRefresh() async throws {
        let store = AuthCredentialStore(connection: connection(access: "expired"))
        let recorder = TokenRecorder(alwaysUnauthorized: true)
        let refresh = RefreshRecorder(store: store, result: connection(access: "rotated"))
        let api = NotionRefreshingAPI(
            credentialStore: store,
            refresh: { try await refresh.run() },
            apiFactory: { token in TokenAwareSyncAPI(token: token, recorder: recorder) }
        )

        do {
            _ = try await api.uploadFile(
                data: Data("file".utf8),
                filename: "file.pdf",
                contentType: "application/pdf"
            )
            XCTFail("Expected the replay to remain unauthorized")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, .httpStatus(401))
        }
        let tokens = await recorder.tokens
        let refreshCount = await refresh.count
        XCTAssertEqual(tokens, ["expired", "rotated"])
        XCTAssertEqual(refreshCount, 1)
    }

    func testParallelUnauthorizedRequestsShareOneRefresh() async throws {
        let store = AuthCredentialStore(connection: connection(access: "expired"))
        let recorder = TokenRecorder()
        let refresh = RefreshRecorder(
            store: store,
            result: connection(access: "rotated"),
            delayNanoseconds: 40_000_000
        )
        let api = NotionRefreshingAPI(
            credentialStore: store,
            refresh: { try await refresh.run() },
            apiFactory: { token in TokenAwareSyncAPI(token: token, recorder: recorder) }
        )

        async let first = api.uploadFile(
            data: Data("one".utf8),
            filename: "one.pdf",
            contentType: "application/pdf"
        )
        async let second = api.uploadFile(
            data: Data("two".utf8),
            filename: "two.pdf",
            contentType: "application/pdf"
        )
        let identifiers = try await [first, second]
        let refreshCount = await refresh.count

        XCTAssertEqual(Set(identifiers), ["11111111-1111-1111-1111-111111111111"])
        XCTAssertEqual(refreshCount, 1)
    }

    func testMeetingQueryUsesTheSameTokenRefreshPath() async throws {
        let store = AuthCredentialStore(connection: connection(access: "expired"))
        let recorder = TokenRecorder()
        let refresh = RefreshRecorder(store: store, result: connection(access: "rotated"))
        let api = NotionRefreshingAPI(
            credentialStore: store,
            refresh: { try await refresh.run() },
            apiFactory: { token in TokenAwareSyncAPI(token: token, recorder: recorder) }
        )

        _ = try await api.queryMeetingNotes()
        let tokens = await recorder.tokens

        XCTAssertEqual(tokens, ["expired", "rotated"])
    }

    private func connection(access: String) -> NotionStoredConnection {
        NotionStoredConnection(
            credentials: NotionOAuthCredentials(
                accessToken: access,
                refreshToken: "refresh-\(access)",
                workspaceID: "workspace",
                workspaceName: "Workspace",
                workspaceIcon: nil,
                botID: "bot"
            ),
            connectedAt: DomainFixtures.fixedDate
        )
    }
}

private final class AuthCredentialStore: NotionCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NotionStoredConnection?

    init(connection: NotionStoredConnection?) {
        self.connection = connection
    }

    func load() throws -> NotionStoredConnection? {
        lock.withLock { connection }
    }

    func save(_ connection: NotionStoredConnection) throws {
        lock.withLock { self.connection = connection }
    }

    func delete() throws {
        lock.withLock { connection = nil }
    }
}

private actor RefreshRecorder {
    private let store: AuthCredentialStore
    private let result: NotionStoredConnection
    private let delayNanoseconds: UInt64
    private(set) var count = 0

    init(
        store: AuthCredentialStore,
        result: NotionStoredConnection,
        delayNanoseconds: UInt64 = 0
    ) {
        self.store = store
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func run() async throws -> NotionStoredConnection {
        count += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        try store.save(result)
        return result
    }
}

private actor TokenRecorder {
    private(set) var tokens: [String] = []
    let alwaysUnauthorized: Bool

    init(alwaysUnauthorized: Bool = false) {
        self.alwaysUnauthorized = alwaysUnauthorized
    }

    func record(_ token: String) throws {
        tokens.append(token)
        if alwaysUnauthorized || token == "expired" {
            throw NotionAPIError.httpStatus(401)
        }
    }
}

private struct TokenAwareSyncAPI: NotionSyncAPI, NotionMeetingLinkAPI {
    let token: String
    let recorder: TokenRecorder

    func uploadFile(data: Data, filename: String, contentType: String) async throws -> String {
        try await recorder.record(token)
        return "11111111-1111-1111-1111-111111111111"
    }

    func findNotebookPage(dataSourceID: String, notebookID: String) async throws -> NotionPageBinding? {
        try await recorder.record(token)
        return nil
    }

    func createNotebookPage(
        dataSourceID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) async throws -> NotionPageBinding {
        try await recorder.record(token)
        return NotionPageBinding(pageID: "22222222-2222-2222-2222-222222222222", url: nil)
    }

    func updateNotebookPage(
        pageID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) async throws -> NotionPageBinding {
        try await recorder.record(token)
        return NotionPageBinding(pageID: pageID, url: nil)
    }

    func trashNotebookPage(pageID: String) async throws {
        try await recorder.record(token)
    }

    func findManagedRootBlock(pageID: String, notebookID: String) async throws -> String? {
        try await recorder.record(token)
        return nil
    }

    func replaceManagedPage(
        pageID: String,
        oldRootID: String?,
        plan: NotionManagedPagePlan
    ) async throws -> String {
        try await recorder.record(token)
        return "33333333-3333-3333-3333-333333333333"
    }

    func queryMeetingNotes() async throws -> [NotionMeetingNote] {
        try await recorder.record(token)
        return []
    }

    func listNotebookLinks(parentBlockID: String) async throws -> [NotionNotebookLinkBlock] {
        try await recorder.record(token)
        return []
    }

    func insertNotebookLink(
        parentBlockID: String,
        afterBlockID: String,
        notebookPageID: String
    ) async throws -> String {
        try await recorder.record(token)
        return "44444444-4444-4444-4444-444444444444"
    }

    func trashMeetingLink(blockID: String) async throws {
        try await recorder.record(token)
    }
}
