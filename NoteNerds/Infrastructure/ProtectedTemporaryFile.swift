import Foundation

enum ProtectedTemporaryFile {
    static func write(_ data: Data, pathExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(pathExtension)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
