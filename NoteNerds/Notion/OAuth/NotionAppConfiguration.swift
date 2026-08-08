import Foundation

enum NotionAppConfiguration {
    private static let clientIDKey = "NNNotionClientIDBase64"
    private static let clientSecretKey = "NNNotionClientSecretBase64"

    static var oauthConfiguration: NotionOAuthConfiguration {
        oauthConfiguration(from: Bundle.main.infoDictionary ?? [:])
    }

    static func oauthConfiguration(from values: [String: Any]) -> NotionOAuthConfiguration {
        NotionOAuthConfiguration(
            clientID: decode(values[clientIDKey] as? String),
            clientSecret: decode(values[clientSecretKey] as? String)
        )
    }

    private static func decode(_ encoded: String?) -> String {
        guard var encoded, !encoded.isEmpty else { return "" }
        encoded = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }
}
