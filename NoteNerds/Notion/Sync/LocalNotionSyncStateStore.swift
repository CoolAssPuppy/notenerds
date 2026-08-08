import Foundation

actor LocalNotionSyncStateStore: NotionSyncStateStoring {
    private static let maximumByteCount: Int64 = 10 * 1_024 * 1_024
    private static let maximumRecordCount = 10_000

    private let fileURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        fileURL = directoryURL.appending(path: "notion-sync-state.plist")
        self.fileManager = fileManager
    }

    func load() throws -> NotionSyncState? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.int64Value <= Self.maximumByteCount else {
            throw NotionSyncStateError.fileTooLarge
        }
        let state = try PropertyListDecoder().decode(
            NotionSyncState.self,
            from: Data(contentsOf: fileURL, options: .mappedIfSafe)
        )
        try Self.validate(state)
        return state
    }

    func save(_ state: NotionSyncState) throws {
        try Self.validate(state)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(state)
        guard data.count <= Self.maximumByteCount else {
            throw NotionSyncStateError.fileTooLarge
        }
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static func validate(_ state: NotionSyncState) throws {
        guard state.schemaVersion == NotionSyncState.currentSchemaVersion else {
            throw NotionSyncStateError.unsupportedSchema
        }
        guard state.bindings.count <= maximumRecordCount,
              state.queue.count <= maximumRecordCount,
              Set(state.bindings.map(\.notebookID)).count == state.bindings.count,
              Set(state.queue.map(\.notebookID)).count == state.queue.count else {
            throw NotionSyncStateError.invalidState
        }
    }
}
