import XCTest
@testable import NoteNerds

final class NotionOAuthBehaviorTests: XCTestCase {
    func testAuthorizationURLMatchesTheRegisteredSyncBarStyleRedirect() throws {
        let configuration = NotionOAuthConfiguration(clientID: "client-id", clientSecret: "client-secret")

        let url = try NotionOAuth.authorizeURL(configuration: configuration, state: "state-value")
        let query = queryItems(url)

        XCTAssertEqual(url.absoluteString.components(separatedBy: "?").first,
                       "https://api.notion.com/v1/oauth/authorize")
        XCTAssertEqual(query["client_id"], "client-id")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["owner"], "user")
        XCTAssertEqual(query["redirect_uri"], "http://localhost:53117/oauth/notion")
        XCTAssertEqual(query["state"], "state-value")
    }

    func testOAuthConfigurationRejectsMissingPlaceholderAndUnexpandedValues() {
        XCTAssertFalse(NotionOAuthConfiguration(clientID: "", clientSecret: "value").isConfigured)
        XCTAssertFalse(
            NotionOAuthConfiguration(
                clientID: "REPLACE_WITH_NOTION_CLIENT_ID",
                clientSecret: "value"
            ).isConfigured
        )
        XCTAssertFalse(
            NotionOAuthConfiguration(clientID: "value", clientSecret: "$(NOTION_CLIENT_SECRET)").isConfigured
        )
        XCTAssertTrue(
            NotionOAuthConfiguration(clientID: "client-id", clientSecret: "client-secret").isConfigured
        )
    }

    func testAppConfigurationReadsOnlyTheDedicatedInfoKeys() {
        let configured = NotionAppConfiguration.oauthConfiguration(from: [
            "NNNotionClientIDBase64": Data("client-id".utf8).base64EncodedString(),
            "NNNotionClientSecretBase64": Data("client-secret".utf8).base64EncodedString(),
            "Unrelated": "ignored"
        ])
        let missing = NotionAppConfiguration.oauthConfiguration(from: [:])

        XCTAssertEqual(
            configured,
            NotionOAuthConfiguration(clientID: "client-id", clientSecret: "client-secret")
        )
        XCTAssertFalse(missing.isConfigured)
    }

    func testRandomStateIsUniqueURLSafeAndContainsAtLeast256Bits() throws {
        let first = try NotionOAuth.randomState()
        let second = try NotionOAuth.randomState()

        XCTAssertNotEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.count, 43)
        XCTAssertNil(first.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testCallbackAcceptsOnlyTheExpectedLoopbackRequestAndState() throws {
        let request = callbackRequest(target: "/oauth/notion?code=abc123&state=expected")

        XCTAssertEqual(
            try NotionLoopbackRequestParser.parse(request, expectedState: "expected"),
            .authorizationCode("abc123")
        )
    }

    func testCallbackMapsNotionCancellationWithoutReturningAcode() throws {
        let request = callbackRequest(
            target: "/oauth/notion?error=access_denied&error_description=Cancelled&state=expected"
        )

        XCTAssertEqual(
            try NotionLoopbackRequestParser.parse(request, expectedState: "expected"),
            .denied(error: "access_denied", description: "Cancelled")
        )
    }

    func testCallbackRejectsWrongStateMethodPathHostDuplicatesAndOversizedInput() {
        let cases: [(Data, NotionOAuthError)] = [
            (callbackRequest(target: "/oauth/notion?code=abc&state=wrong"), .stateMismatch),
            (callbackRequest(method: "POST", target: "/oauth/notion?code=abc&state=expected"), .invalidCallback),
            (callbackRequest(target: "/wrong?code=abc&state=expected"), .invalidCallback),
            (
                callbackRequest(
                    target: "/oauth/notion?code=abc&state=expected",
                    host: "evil.example"
                ),
                .invalidCallback
            ),
            (
                callbackRequest(target: "/oauth/notion?code=one&code=two&state=expected"),
                .invalidCallback
            ),
            (Data(repeating: 65, count: 16_385), .callbackTooLarge)
        ]

        for (request, expectedError) in cases {
            XCTAssertThrowsError(
                try NotionLoopbackRequestParser.parse(request, expectedState: "expected")
            ) { error in
                XCTAssertEqual(error as? NotionOAuthError, expectedError)
            }
        }
    }

    func testTokenExchangeRefreshAndRevokeRequestsUseCurrentNotionContract() throws {
        let configuration = NotionOAuthConfiguration(clientID: "client-id", clientSecret: "client-secret")
        let exchange = try NotionOAuthRequestFactory.exchange(code: "auth-code", configuration: configuration)
        let refresh = try NotionOAuthRequestFactory.refresh(token: "refresh-token", configuration: configuration)
        let revoke = try NotionOAuthRequestFactory.revoke(token: "access-token", configuration: configuration)

        assertCommonTokenRequest(exchange, path: "/v1/oauth/token")
        XCTAssertEqual(try jsonBody(exchange)["grant_type"] as? String, "authorization_code")
        XCTAssertEqual(try jsonBody(exchange)["code"] as? String, "auth-code")
        XCTAssertEqual(
            try jsonBody(exchange)["redirect_uri"] as? String,
            "http://localhost:53117/oauth/notion"
        )
        assertCommonTokenRequest(refresh, path: "/v1/oauth/token")
        XCTAssertEqual(try jsonBody(refresh)["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(try jsonBody(refresh)["refresh_token"] as? String, "refresh-token")
        assertCommonTokenRequest(revoke, path: "/v1/oauth/revoke")
        XCTAssertEqual(try jsonBody(revoke)["token"] as? String, "access-token")
    }

    func testTokenResponseRequiresBothRotatingTokensAndWorkspaceIdentity() throws {
        let valid = Data(#"""
        {
            "access_token":"access",
            "refresh_token":"refresh",
            "workspace_id":"workspace",
            "workspace_name":"Strategic Nerds",
            "workspace_icon":null,
            "bot_id":"bot"
        }
        """#.utf8)
        let credentials = try NotionOAuthTokenResponse.decode(valid)

        XCTAssertEqual(credentials.accessToken, "access")
        XCTAssertEqual(credentials.refreshToken, "refresh")
        XCTAssertEqual(credentials.workspaceID, "workspace")
        XCTAssertEqual(credentials.workspaceName, "Strategic Nerds")
        XCTAssertEqual(credentials.botID, "bot")

        let missingRefresh = Data(#"""
        {
            "access_token":"access",
            "workspace_id":"workspace",
            "workspace_name":"Workspace",
            "bot_id":"bot"
        }
        """#.utf8)
        XCTAssertThrowsError(try NotionOAuthTokenResponse.decode(missingRefresh))
    }

    func testLoopbackServerAcceptsOneRealLocalCallbackAfterItIsReady() async throws {
        let server = NotionLoopbackServer()
        let port = try await server.start(port: 0, expectedState: "expected")
        let callbackTask = Task { try await server.waitForCallback(timeout: .seconds(2)) }
        let url = try XCTUnwrap(
            URL(string: "http://localhost:\(port)/oauth/notion?code=live-code&state=expected")
        )

        let (body, response) = try await URLSession.shared.data(from: url)
        let callback = try await callbackTask.value

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(
            (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Security-Policy"),
            "default-src 'none'; style-src 'unsafe-inline'"
        )
        let responseBody = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(responseBody.contains("Return to Note Nerds"))
        XCTAssertEqual(callback, .authorizationCode("live-code"))
    }

    func testLoopbackServerTimesOutAndReleasesItsPort() async throws {
        let server = NotionLoopbackServer()
        let port = try await server.start(port: 0, expectedState: "expected")

        do {
            _ = try await server.waitForCallback(timeout: .milliseconds(50))
            XCTFail("Expected the callback to time out")
        } catch {
            XCTAssertEqual(error as? NotionOAuthError, .callbackTimedOut)
        }

        let replacement = NotionLoopbackServer()
        let reusedPort = try await replacement.start(port: port, expectedState: "another")
        XCTAssertEqual(reusedPort, port)
        replacement.cancel()
    }

    private func callbackRequest(
        method: String = "GET",
        target: String,
        host: String = "localhost:53117"
    ) -> Data {
        Data("\(method) \(target) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n".utf8)
    }

    private func queryItems(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .compactMap { item in item.value.map { (item.name, $0) } })
    }

    private func assertCommonTokenRequest(_ request: URLRequest, path: String) {
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.notion.com")
        XCTAssertEqual(request.url?.path, path)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2026-03-11")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Basic \(Data("client-id:client-secret".utf8).base64EncodedString())"
        )
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}
