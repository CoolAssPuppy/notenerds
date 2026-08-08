import Foundation
import Security

enum NotionOAuth {
    private static let authorizeEndpoint = URL(string: "https://api.notion.com/v1/oauth/authorize")!

    static func authorizeURL(configuration: NotionOAuthConfiguration, state: String) throws -> URL {
        guard configuration.isConfigured else { throw NotionOAuthError.notConfigured }
        guard var components = URLComponents(
            url: authorizeEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw NotionOAuthError.invalidAuthorizationURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user"),
            URLQueryItem(name: "redirect_uri", value: NotionOAuthConfiguration.redirectURI),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else { throw NotionOAuthError.invalidAuthorizationURL }
        return url
    }

    static func randomState() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NotionOAuthError.randomGenerationFailed
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func stateMatches(_ received: String, expected: String) -> Bool {
        let left = Array(received.utf8)
        let right = Array(expected.utf8)
        var difference = left.count ^ right.count
        for index in 0..<max(left.count, right.count) {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }
        return difference == 0
    }
}
