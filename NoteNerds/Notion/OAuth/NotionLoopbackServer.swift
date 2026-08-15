import Foundation
import Network

protocol NotionLoopbackServing: Sendable {
    func start(port: UInt16, expectedState: String) async throws -> UInt16
    func waitForCallback(timeout: Duration) async throws -> NotionOAuthCallback
    func cancel()
}

final class NotionLoopbackServer: NotionLoopbackServing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.strategicnerds.notenerds.notion-oauth")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<NotionOAuthCallback, Error>?
    private var pendingResult: Result<NotionOAuthCallback, Error>?
    private var completionResult: Result<NotionOAuthCallback, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var expectedState = ""
    private var activePort: UInt16 = 0
    private var hasAcceptedConnection = false
    private var isFinished = false

    func start(port: UInt16, expectedState: String) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.listener == nil, !expectedState.isEmpty else {
                    continuation.resume(throwing: NotionOAuthError.cannotStartListener)
                    return
                }
                self.startContinuation = continuation
                self.expectedState = expectedState
                self.startListener(port: port)
            }
        }
    }

    func waitForCallback(timeout: Duration) async throws -> NotionOAuthCallback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let result = self.pendingResult {
                        self.pendingResult = nil
                        continuation.resume(with: result)
                        return
                    }
                    guard self.listener != nil, self.callbackContinuation == nil else {
                        continuation.resume(throwing: NotionOAuthError.cannotStartListener)
                        return
                    }
                    self.callbackContinuation = continuation
                    self.timeoutTask = Task { [weak self] in
                        try? await Task.sleep(for: timeout)
                        guard !Task.isCancelled else { return }
                        self?.finishFromAnyQueue(.failure(NotionOAuthError.callbackTimedOut))
                    }
                }
            }
        } onCancel: {
            finishFromAnyQueue(.failure(NotionOAuthError.callbackCancelled))
        }
    }

    func cancel() {
        finishFromAnyQueue(.failure(NotionOAuthError.callbackCancelled))
    }

    private func startListener(port: UInt16) {
        let requestedPort: NWEndpoint.Port = port == 0 ? .any : NWEndpoint.Port(rawValue: port) ?? .any
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: requestedPort
            )
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.handle(state)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            finish(.failure(NotionOAuthError.cannotStartListener))
        }
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else {
                finish(.failure(NotionOAuthError.cannotStartListener))
                return
            }
            activePort = port
            startContinuation?.resume(returning: port)
            startContinuation = nil
        case .failed:
            listener = nil
            finish(.failure(NotionOAuthError.cannotStartListener))
        case .cancelled:
            listener = nil
            if !isFinished {
                isFinished = true
                completionResult = .failure(NotionOAuthError.callbackCancelled)
            }
            completeShutdown()
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !hasAcceptedConnection, !isFinished else {
            connection.cancel()
            return
        }
        self.connection = connection
        connection.start(queue: queue)
        receive(from: connection, accumulated: Data())
    }

    private func receive(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var request = accumulated
            if let data { request.append(data) }
            if request.count > NotionLoopbackRequestParser.maximumRequestByteCount {
                self.reject(connection)
                return
            }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.process(request, connection: connection)
                return
            }
            if error != nil || isComplete {
                self.reject(connection)
                return
            }
            self.receive(from: connection, accumulated: request)
        }
    }

    private func process(_ request: Data, connection: NWConnection) {
        do {
            let callback = try NotionLoopbackRequestParser.parse(
                request,
                expectedState: expectedState,
                port: activePort
            )
            hasAcceptedConnection = true
            respond(to: connection, status: 200, body: Self.successHTML) {
                self.finish(.success(callback))
            }
        } catch {
            reject(connection)
        }
    }

    private func reject(_ connection: NWConnection) {
        respond(to: connection, status: 400, body: Self.failureHTML)
    }

    private func respond(
        to connection: NWConnection,
        status: Int,
        body: String,
        completion: (@Sendable () -> Void)? = nil
    ) {
        let reason = status == 200 ? "OK" : "Bad Request"
        let response = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Cache-Control: no-store\r
        Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r
        X-Content-Type-Options: nosniff\r
        Referrer-Policy: no-referrer\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.connection = nil
            completion?()
        })
    }

    private func finishFromAnyQueue(_ result: Result<NotionOAuthCallback, Error>) {
        queue.async { self.finish(result) }
    }

    private func finish(_ result: Result<NotionOAuthCallback, Error>) {
        guard !isFinished else { return }
        isFinished = true
        completionResult = result
        timeoutTask?.cancel()
        timeoutTask = nil
        connection?.cancel()
        connection = nil
        if let listener {
            listener.cancel()
            return
        }
        completeShutdown()
    }

    private func completeShutdown() {
        guard let result = completionResult else { return }
        completionResult = nil
        if let continuation = startContinuation {
            startContinuation = nil
            continuation.resume(throwing: result.failure ?? NotionOAuthError.cannotStartListener)
        }
        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(with: result)
        } else {
            pendingResult = result
        }
    }

    private static let successHTML = """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
    <title>Note Nerds</title><style>body{font:17px -apple-system;padding:48px;text-align:center;color:#1d1d1f}</style>
    </head><body><h1>Connected</h1><p>Return to Note Nerds to finish setup.</p></body></html>
    """

    private static let failureHTML = """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
    <title>Note Nerds</title><style>body{font:17px -apple-system;padding:48px;text-align:center;color:#1d1d1f}</style>
    </head><body><h1>Unable to connect</h1><p>Return to Note Nerds and try again.</p></body></html>
    """
}

private extension Result {
    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
