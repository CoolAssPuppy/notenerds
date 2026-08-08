import Foundation

enum NotionLoopbackRequestParser {
    static let maximumRequestByteCount = 16_384

    static func parse(
        _ data: Data,
        expectedState: String,
        port: UInt16 = NotionOAuthConfiguration.loopbackPort
    ) throws -> NotionOAuthCallback {
        guard data.count <= maximumRequestByteCount else {
            throw NotionOAuthError.callbackTooLarge
        }
        guard let request = String(data: data, encoding: .utf8) else {
            throw NotionOAuthError.invalidCallback
        }
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw NotionOAuthError.invalidCallback }
        let fields = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count == 3,
              fields[0] == "GET",
              fields[2] == "HTTP/1.1" || fields[2] == "HTTP/1.0",
              validHost(in: lines, port: port) else {
            throw NotionOAuthError.invalidCallback
        }
        let target = String(fields[1])
        guard let components = URLComponents(string: "http://localhost\(target)"),
              components.path == "/oauth/notion" else {
            throw NotionOAuthError.invalidCallback
        }
        let query = try uniqueQuery(components.queryItems ?? [])
        guard let receivedState = query["state"],
              NotionOAuth.stateMatches(receivedState, expected: expectedState) else {
            throw NotionOAuthError.stateMismatch
        }
        if let code = query["code"], query["error"] == nil, !code.isEmpty {
            return .authorizationCode(code)
        }
        if let error = query["error"], query["code"] == nil, !error.isEmpty {
            return .denied(error: error, description: query["error_description"])
        }
        throw NotionOAuthError.missingAuthorizationCode
    }

    private static func validHost(in lines: [String], port: UInt16) -> Bool {
        let hostValues = lines.dropFirst().compactMap { line -> String? in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.caseInsensitiveCompare("Host") == .orderedSame else { return nil }
            return line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return hostValues == ["localhost:\(port)"]
    }

    private static func uniqueQuery(_ items: [URLQueryItem]) throws -> [String: String] {
        var values: [String: String] = [:]
        for item in items {
            guard values[item.name] == nil, let value = item.value else {
                throw NotionOAuthError.invalidCallback
            }
            values[item.name] = value
        }
        return values
    }
}
