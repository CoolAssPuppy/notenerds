import Foundation

enum NotionDownloadHost {
    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        guard !isIPAddress(host) else { return false }
        return isNotionHost(host)
    }

    private static func isNotionHost(_ host: String) -> Bool {
        host == "notion.so"
            || host.hasSuffix(".notion.so")
            || host == "notion-static.com"
            || host.hasSuffix(".notion-static.com")
            || (host.hasPrefix("prod-files-secure.") && host.hasSuffix(".amazonaws.com"))
    }

    private static func isIPAddress(_ host: String) -> Bool {
        host.contains(":")
            || host.split(separator: ".").count == 4
            && host.allSatisfy({ $0.isNumber || $0 == "." })
    }
}
