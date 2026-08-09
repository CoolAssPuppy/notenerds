import Foundation

actor LocalSyncStateStore: SyncStateStore {
    private static let maximumByteCount = 1_024 * 1_024 * 1_024

    private let fileURL: URL
    private let legacyFileURL: URL
    private let readData: @Sendable (URL) throws -> Data

    init(
        directoryURL: URL,
        readData: @escaping @Sendable (URL) throws -> Data = {
            try BoundedFileReader(maximumByteCount: LocalSyncStateStore.maximumByteCount).read(from: $0)
        }
    ) {
        fileURL = directoryURL.appending(path: "sync-state.plist")
        legacyFileURL = directoryURL.appending(path: "sync-state.json")
        self.readData = readData
    }

    func load() throws -> SyncEngineSnapshot? {
        if let data = try dataIfPresent(at: fileURL) {
            return try PropertyListDecoder().decode(SyncEngineSnapshot.self, from: data)
        }
        guard let legacyData = try dataIfPresent(at: legacyFileURL) else { return nil }
        return try JSONDecoder().decode(SyncEngineSnapshot.self, from: legacyData)
    }

    func save(_ snapshot: SyncEngineSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtection])
        do {
            try FileManager.default.removeItem(at: legacyFileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    private func dataIfPresent(at url: URL) throws -> Data? {
        do {
            return try readData(url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
