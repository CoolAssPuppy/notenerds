import Foundation

enum NotionOAuthRequestFactory {
    private static let tokenEndpoint = URL(string: "https://api.notion.com/v1/oauth/token")!
    private static let revokeEndpoint = URL(string: "https://api.notion.com/v1/oauth/revoke")!
    private static let notionVersion = "2026-03-11"

    static func exchange(
        code: String,
        configuration: NotionOAuthConfiguration
    ) throws -> URLRequest {
        try request(
            url: tokenEndpoint,
            body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": NotionOAuthConfiguration.redirectURI
            ],
            configuration: configuration
        )
    }

    static func refresh(
        token: String,
        configuration: NotionOAuthConfiguration
    ) throws -> URLRequest {
        try request(
            url: tokenEndpoint,
            body: ["grant_type": "refresh_token", "refresh_token": token],
            configuration: configuration
        )
    }

    static func revoke(
        token: String,
        configuration: NotionOAuthConfiguration
    ) throws -> URLRequest {
        try request(
            url: revokeEndpoint,
            body: ["token": token],
            configuration: configuration
        )
    }

    private static func request(
        url: URL,
        body: [String: String],
        configuration: NotionOAuthConfiguration
    ) throws -> URLRequest {
        guard configuration.isConfigured else { throw NotionOAuthError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let credentials = Data("\(configuration.clientID):\(configuration.clientSecret)".utf8)
            .base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(body)
        return request
    }
}
