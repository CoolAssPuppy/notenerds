import Foundation

actor LocalSyncStateStore: SyncStateStore {
    private let fileURL: URL
    private let legacyFileURL: URL

    init(directoryURL: URL) {
        fileURL = directoryURL.appending(path: "sync-state.plist")
        legacyFileURL = directoryURL.appending(path: "sync-state.json")
    }

    func load() throws -> SyncEngineSnapshot? {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try PropertyListDecoder().decode(SyncEngineSnapshot.self, from: Data(contentsOf: fileURL))
        }
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else { return nil }
        return try JSONDecoder().decode(SyncEngineSnapshot.self, from: Data(contentsOf: legacyFileURL))
    }

    func save(_ snapshot: SyncEngineSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtection])
        if FileManager.default.fileExists(atPath: legacyFileURL.path) {
            try FileManager.default.removeItem(at: legacyFileURL)
        }
    }
}
