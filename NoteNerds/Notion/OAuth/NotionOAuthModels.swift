import Foundation

struct NotionOAuthConfiguration: Equatable, Sendable {
    static let redirectURI = "http://localhost:53117/oauth/notion"
    static let loopbackPort: UInt16 = 53_117

    let clientID: String
    let clientSecret: String

    var isConfigured: Bool {
        [clientID, clientSecret].allSatisfy { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
                && !trimmed.hasPrefix("REPLACE_WITH_")
                && !trimmed.hasPrefix("$(")
        }
    }
}

enum NotionOAuthError: Error, Equatable, Sendable {
    case notConfigured
    case randomGenerationFailed
    case invalidAuthorizationURL
    case cannotOpenBrowser
    case callbackTooLarge
    case cannotStartListener
    case callbackTimedOut
    case callbackCancelled
    case invalidCallback
    case stateMismatch
    case missingAuthorizationCode
    case invalidTokenResponse
    case noConnection
    case httpStatus(Int)
}

enum NotionOAuthCallback: Equatable, Sendable {
    case authorizationCode(String)
    case denied(error: String, description: String?)
}

struct NotionOAuthCredentials: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let workspaceID: String
    let workspaceName: String
    let workspaceIcon: String?
    let botID: String
}

struct NotionStoredConnection: Codable, Equatable, Sendable {
    let credentials: NotionOAuthCredentials
    let connectedAt: Date
}

private struct NotionOAuthTokenPayload: Decodable {
    let accessToken: String
    let refreshToken: String
    let workspaceID: String
    let workspaceName: String?
    let workspaceIcon: String?
    let botID: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
        case workspaceIcon = "workspace_icon"
        case botID = "bot_id"
    }
}

enum NotionOAuthTokenResponse {
    static func decode(_ data: Data) throws -> NotionOAuthCredentials {
        let response = try JSONDecoder().decode(NotionOAuthTokenPayload.self, from: data)
        guard !response.accessToken.isEmpty,
              !response.refreshToken.isEmpty,
              !response.workspaceID.isEmpty else {
            throw NotionOAuthError.invalidTokenResponse
        }
        return NotionOAuthCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            workspaceID: response.workspaceID,
            workspaceName: response.workspaceName ?? "Notion workspace",
            workspaceIcon: response.workspaceIcon,
            botID: response.botID ?? ""
        )
    }
}
