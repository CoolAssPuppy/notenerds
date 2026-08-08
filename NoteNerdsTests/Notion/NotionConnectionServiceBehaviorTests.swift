import XCTest
@testable import NoteNerds

final class NotionConnectionServiceBehaviorTests: XCTestCase {
    @MainActor
    func testConnectStartsListenerBeforeBrowserAndSavesTokensAfterExchange() async throws {
        let loopback = StubLoopbackServer(result: .success(.authorizationCode("auth-code")))
        let browser = StubNotionBrowser(loopback: loopback, result: true)
        let store = RecordingCredentialStore()
        let transport = OAuthTransport(responses: [
            .json(200, tokenResponse(access: "access-1", refresh: "refresh-1"))
        ])
        let service = NotionConnectionService(
            configuration: configuration,
            credentialStore: store,
            transport: transport,
            browser: browser,
            loopbackFactory: { loopback },
            now: { Date(timeIntervalSince1970: 1_234) }
        )

        let connection = try await service.connect()
        let requests = await transport.allRequests()

        XCTAssertTrue(loopback.wasStartedBeforeBrowser)
        XCTAssertEqual(loopback.requestedPort, 53_117)
        XCTAssertEqual(connection.credentials.accessToken, "access-1")
        XCTAssertEqual(connection.credentials.refreshToken, "refresh-1")
        XCTAssertEqual(connection.connectedAt, Date(timeIntervalSince1970: 1_234))
        XCTAssertEqual(try store.load(), connection)
        XCTAssertEqual(browser.dismissCallCount, 1)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/v1/oauth/token")
        XCTAssertEqual(try jsonBody(requests[0])["code"] as? String, "auth-code")
        let authorizationURL = try XCTUnwrap(browser.openedURL)
        XCTAssertEqual(queryItems(authorizationURL)["redirect_uri"], NotionOAuthConfiguration.redirectURI)
        XCTAssertEqual(queryItems(authorizationURL)["state"], loopback.expectedState)
    }

    @MainActor
    func testDeniedOrUnopenableAuthorizationNeverCallsTokenEndpoint() async {
        for setup in [
            (
                StubLoopbackServer(result: .success(.denied(error: "access_denied", description: nil))),
                true,
                NotionOAuthError.callbackCancelled
            ),
            (
                StubLoopbackServer(result: .success(.authorizationCode("unused"))),
                false,
                NotionOAuthError.cannotOpenBrowser
            )
        ] {
            let transport = OAuthTransport(responses: [])
            let service = NotionConnectionService(
                configuration: configuration,
                credentialStore: RecordingCredentialStore(),
                transport: transport,
                browser: StubNotionBrowser(loopback: setup.0, result: setup.1),
                loopbackFactory: { setup.0 }
            )
            do {
                _ = try await service.connect()
                XCTFail("Expected connection to stop")
            } catch {
                XCTAssertEqual(error as? NotionOAuthError, setup.2)
            }
            let requests = await transport.allRequests()
            XCTAssertTrue(requests.isEmpty)
        }
    }

    @MainActor
    func testRefreshRotatesBothTokensAtomicallyAndPreservesConnectionDate() async throws {
        let original = storedConnection(access: "old-access", refresh: "old-refresh")
        let store = RecordingCredentialStore(connection: original)
        let transport = OAuthTransport(responses: [
            .json(200, tokenResponse(access: "new-access", refresh: "new-refresh"))
        ])
        let service = NotionConnectionService(
            configuration: configuration,
            credentialStore: store,
            transport: transport,
            browser: StubNotionBrowser(loopback: StubLoopbackServer(), result: true)
        )

        let refreshed = try await service.refresh()
        let requests = await transport.allRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(refreshed.credentials.accessToken, "new-access")
        XCTAssertEqual(refreshed.credentials.refreshToken, "new-refresh")
        XCTAssertEqual(refreshed.connectedAt, original.connectedAt)
        XCTAssertEqual(try store.load(), refreshed)
        XCTAssertEqual(try jsonBody(request)["refresh_token"] as? String, "old-refresh")
    }

    @MainActor
    func testFailedRefreshLeavesExistingTokensUntouched() async throws {
        let original = storedConnection(access: "old-access", refresh: "old-refresh")
        let store = RecordingCredentialStore(connection: original)
        let transport = OAuthTransport(responses: [.json(401, #"{"object":"error"}"#)])
        let service = NotionConnectionService(
            configuration: configuration,
            credentialStore: store,
            transport: transport,
            browser: StubNotionBrowser(loopback: StubLoopbackServer(), result: true)
        )

        do {
            _ = try await service.refresh()
            XCTFail("Expected refresh to fail")
        } catch {
            XCTAssertEqual(error as? NotionOAuthError, .httpStatus(401))
        }
        XCTAssertEqual(try store.load(), original)
    }

    @MainActor
    func testDisconnectRevokesBeforeDeletingDeviceCredentials() async throws {
        let original = storedConnection(access: "active-access", refresh: "active-refresh")
        let store = RecordingCredentialStore(connection: original)
        let transport = OAuthTransport(responses: [.json(200, #"{}"#)])
        let service = NotionConnectionService(
            configuration: configuration,
            credentialStore: store,
            transport: transport,
            browser: StubNotionBrowser(loopback: StubLoopbackServer(), result: true)
        )

        try await service.disconnect()
        let requests = await transport.allRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(request.url?.path, "/v1/oauth/revoke")
        XCTAssertEqual(try jsonBody(request)["token"] as? String, "active-access")
        XCTAssertEqual(store.events, ["load", "delete"])
        XCTAssertNil(try store.load())
    }

    @MainActor
    func testDisconnectDeletesDeviceCredentialsWhenNotionCannotBeReached() async throws {
        let original = storedConnection(access: "active-access", refresh: "active-refresh")
        let store = RecordingCredentialStore(connection: original)
        let transport = OAuthTransport(responses: [.failure(URLError(.notConnectedToInternet))])
        let service = NotionConnectionService(
            configuration: configuration,
            credentialStore: store,
            transport: transport,
            browser: StubNotionBrowser(loopback: StubLoopbackServer(), result: true)
        )

        try await service.disconnect()

        XCTAssertNil(try store.load())
    }

    private var configuration: NotionOAuthConfiguration {
        NotionOAuthConfiguration(clientID: "client-id", clientSecret: "client-secret")
    }

    private func storedConnection(access: String, refresh: String) -> NotionStoredConnection {
        NotionStoredConnection(
            credentials: credentials(access: access, refresh: refresh),
            connectedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func credentials(access: String, refresh: String) -> NotionOAuthCredentials {
        NotionOAuthCredentials(
            accessToken: access,
            refreshToken: refresh,
            workspaceID: "workspace-id",
            workspaceName: "Strategic Nerds",
            workspaceIcon: nil,
            botID: "bot-id"
        )
    }

    private func tokenResponse(access: String, refresh: String) -> String {
        // swiftlint:disable:next line_length
        #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","workspace_id":"workspace-id","workspace_name":"Strategic Nerds","workspace_icon":null,"bot_id":"bot-id"}"#
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func queryItems(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .compactMap { item in item.value.map { (item.name, $0) } })
    }
}

private final class StubLoopbackServer: NotionLoopbackServing, @unchecked Sendable {
    private let result: Result<NotionOAuthCallback, Error>
    private let lock = NSLock()
    private(set) var requestedPort: UInt16?
    private(set) var expectedState: String?
    private(set) var wasStartedBeforeBrowser = false

    init(result: Result<NotionOAuthCallback, Error> = .failure(NotionOAuthError.callbackCancelled)) {
        self.result = result
    }

    func start(port: UInt16, expectedState: String) async throws -> UInt16 {
        lock.withLock {
            requestedPort = port
            self.expectedState = expectedState
        }
        return port
    }

    func waitForCallback(timeout: Duration) async throws -> NotionOAuthCallback {
        try result.get()
    }

    func cancel() {}

    func markBrowserOpened() {
        lock.withLock { wasStartedBeforeBrowser = requestedPort != nil }
    }
}

@MainActor
private final class StubNotionBrowser: NotionBrowserOpening {
    private let loopback: StubLoopbackServer
    private let result: Bool
    private(set) var openedURL: URL?
    private(set) var dismissCallCount = 0

    init(loopback: StubLoopbackServer, result: Bool) {
        self.loopback = loopback
        self.result = result
    }

    func open(_ url: URL, onCancel: @escaping @MainActor () -> Void) async -> Bool {
        openedURL = url
        loopback.markBrowserOpened()
        return result
    }

    func dismiss() {
        dismissCallCount += 1
    }
}

private final class RecordingCredentialStore: NotionCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NotionStoredConnection?
    private(set) var events: [String] = []

    init(connection: NotionStoredConnection? = nil) {
        self.connection = connection
    }

    func load() throws -> NotionStoredConnection? {
        lock.withLock {
            events.append("load")
            return connection
        }
    }

    func save(_ connection: NotionStoredConnection) throws {
        lock.withLock {
            events.append("save")
            self.connection = connection
        }
    }

    func delete() throws {
        lock.withLock {
            events.append("delete")
            connection = nil
        }
    }
}

private actor OAuthTransport: NotionHTTPTransport {
    struct Response: Sendable {
        let status: Int
        let body: Data
        let error: (any Error & Sendable)?

        static func json(_ status: Int, _ body: String) -> Response {
            Response(status: status, body: Data(body.utf8), error: nil)
        }

        static func failure(_ error: any Error & Sendable) -> Response {
            Response(status: 0, body: Data(), error: error)
        }
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        if let error = response.error { throw error }
        return (
            response.body,
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
    }

    func allRequests() -> [URLRequest] {
        requests
    }
}
