import AuthenticationServices
import Foundation
import UIKit

@MainActor
protocol NotionBrowserOpening: AnyObject {
    func open(_ url: URL, onCancel: @escaping @MainActor () -> Void) async -> Bool
    func dismiss()
}

@MainActor
protocol NotionWebAuthenticationSession: AnyObject {
    var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)? { get set }
    var prefersEphemeralWebBrowserSession: Bool { get set }

    func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession: NotionWebAuthenticationSession {}

@MainActor
final class SystemNotionBrowser: NSObject, NotionBrowserOpening, ASWebAuthenticationPresentationContextProviding {
    typealias SessionFactory = (
        URL,
        String?,
        @escaping ASWebAuthenticationSession.CompletionHandler
    ) -> any NotionWebAuthenticationSession

    private let sessionFactory: SessionFactory
    private var session: (any NotionWebAuthenticationSession)?
    private var cancellationHandler: (@MainActor () -> Void)?

    init(
        sessionFactory: @escaping SessionFactory = { url, scheme, completion in
            ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme,
                completionHandler: completion
            )
        }
    ) {
        self.sessionFactory = sessionFactory
    }

    func open(_ url: URL, onCancel: @escaping @MainActor () -> Void) async -> Bool {
        dismiss()
        cancellationHandler = onCancel
        let session = sessionFactory(url, nil) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isCancellation(error) else { return }
                self.cancellationHandler?()
                self.cancellationHandler = nil
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        return session.start()
    }

    func dismiss() {
        cancellationHandler = nil
        session?.cancel()
        session = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        if let scene = scenes.first {
            return ASPresentationAnchor(windowScene: scene)
        }
        return ASPresentationAnchor(frame: .zero)
    }

    private func isCancellation(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == ASWebAuthenticationSessionErrorDomain
            && error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
}

@MainActor
final class NotionConnectionService {
    private let configuration: NotionOAuthConfiguration
    private let credentialStore: any NotionCredentialStore
    private let transport: any NotionHTTPTransport
    private let browser: any NotionBrowserOpening
    private let loopbackFactory: @Sendable () -> any NotionLoopbackServing
    private let now: @Sendable () -> Date

    init(
        configuration: NotionOAuthConfiguration,
        credentialStore: any NotionCredentialStore,
        transport: any NotionHTTPTransport = URLSessionNotionTransport(),
        browser: any NotionBrowserOpening = SystemNotionBrowser(),
        loopbackFactory: @escaping @Sendable () -> any NotionLoopbackServing = {
            NotionLoopbackServer()
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.transport = transport
        self.browser = browser
        self.loopbackFactory = loopbackFactory
        self.now = now
    }

    func currentConnection() throws -> NotionStoredConnection? {
        try credentialStore.load()
    }

    func connect() async throws -> NotionStoredConnection {
        guard configuration.isConfigured else { throw NotionOAuthError.notConfigured }
        let state = try NotionOAuth.randomState()
        let loopback = loopbackFactory()
        return try await withTaskCancellationHandler {
            let port = try await loopback.start(
                port: NotionOAuthConfiguration.loopbackPort,
                expectedState: state
            )
            guard port == NotionOAuthConfiguration.loopbackPort else {
                loopback.cancel()
                throw NotionOAuthError.cannotStartListener
            }
            let url = try NotionOAuth.authorizeURL(configuration: configuration, state: state)
            defer { browser.dismiss() }
            guard await browser.open(url, onCancel: { loopback.cancel() }) else {
                loopback.cancel()
                throw NotionOAuthError.cannotOpenBrowser
            }
            let callback = try await loopback.waitForCallback(timeout: .seconds(300))
            guard case let .authorizationCode(code) = callback else {
                throw NotionOAuthError.callbackCancelled
            }
            let request = try NotionOAuthRequestFactory.exchange(
                code: code,
                configuration: configuration
            )
            let credentials = try await tokenRequest(request)
            let connection = NotionStoredConnection(credentials: credentials, connectedAt: now())
            try credentialStore.save(connection)
            return connection
        } onCancel: {
            loopback.cancel()
        }
    }

    func refresh() async throws -> NotionStoredConnection {
        guard let current = try credentialStore.load() else {
            throw NotionOAuthError.noConnection
        }
        let request = try NotionOAuthRequestFactory.refresh(
            token: current.credentials.refreshToken,
            configuration: configuration
        )
        let credentials = try await tokenRequest(request)
        let refreshed = NotionStoredConnection(
            credentials: credentials,
            connectedAt: current.connectedAt
        )
        try credentialStore.save(refreshed)
        return refreshed
    }

    func disconnect() async throws {
        guard let current = try credentialStore.load() else { return }
        do {
            let request = try NotionOAuthRequestFactory.revoke(
                token: current.credentials.accessToken,
                configuration: configuration
            )
            _ = try await transport.data(for: request)
        } catch {
            // Local disconnect must remain available while Notion is unreachable.
        }
        try credentialStore.delete()
    }

    private func tokenRequest(_ request: URLRequest) async throws -> NotionOAuthCredentials {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw NotionOAuthError.httpStatus(response.statusCode)
        }
        do {
            return try NotionOAuthTokenResponse.decode(data)
        } catch let error as NotionOAuthError {
            throw error
        } catch {
            throw NotionOAuthError.invalidTokenResponse
        }
    }
}
