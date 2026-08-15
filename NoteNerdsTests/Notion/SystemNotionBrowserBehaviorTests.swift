import AuthenticationServices
import XCTest
@testable import NoteNerds

final class SystemNotionBrowserBehaviorTests: XCTestCase {
    @MainActor
    func testAuthorizationUsesAnEphemeralSystemAuthenticationSession() async throws {
        let session = RecordingWebAuthenticationSession()
        var receivedURL: URL?
        var receivedScheme: String?
        let browser = SystemNotionBrowser { url, scheme, _ in
            receivedURL = url
            receivedScheme = scheme
            return session
        }
        let url = try XCTUnwrap(URL(string: "https://api.notion.com/v1/oauth/authorize?client_id=test"))

        let didStart = await browser.open(url, onCancel: {})

        XCTAssertTrue(didStart)
        XCTAssertEqual(receivedURL, url)
        XCTAssertNil(receivedScheme)
        XCTAssertTrue(session.prefersEphemeralWebBrowserSession)
        XCTAssertTrue(session.presentationContextProvider === browser)
        XCTAssertEqual(session.startCallCount, 1)
    }

    @MainActor
    func testCancellationStopsTheConnectionAttemptAndSuccessfulCallbackDismissesTheSheet() async throws {
        let session = RecordingWebAuthenticationSession()
        var completion: ASWebAuthenticationSession.CompletionHandler?
        var cancellationCount = 0
        let browser = SystemNotionBrowser { _, _, handler in
            completion = handler
            return session
        }
        let url = try XCTUnwrap(URL(string: "https://api.notion.com/v1/oauth/authorize"))
        _ = await browser.open(url) { cancellationCount += 1 }

        completion?(nil, NSError(domain: ASWebAuthenticationSessionErrorDomain, code: 1))
        await Task.yield()

        XCTAssertEqual(cancellationCount, 1)
        browser.dismiss()
        XCTAssertEqual(session.cancelCallCount, 1)
    }

    @MainActor
    func testAuthorizationDoesNotStartWithoutAPresentationScene() async throws {
        let session = RecordingWebAuthenticationSession()
        let browser = SystemNotionBrowser(
            sessionFactory: { _, _, _ in session },
            presentationAnchorProvider: { nil }
        )
        let url = try XCTUnwrap(URL(string: "https://api.notion.com/v1/oauth/authorize"))

        let didStart = await browser.open(url, onCancel: {})

        XCTAssertFalse(didStart)
        XCTAssertEqual(session.startCallCount, 0)
        XCTAssertNil(session.presentationContextProvider)
    }
}

@MainActor
private final class RecordingWebAuthenticationSession: NotionWebAuthenticationSession {
    var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)?
    var prefersEphemeralWebBrowserSession = true
    private(set) var startCallCount = 0
    private(set) var cancelCallCount = 0

    func start() -> Bool {
        startCallCount += 1
        return true
    }

    func cancel() {
        cancelCallCount += 1
    }
}
