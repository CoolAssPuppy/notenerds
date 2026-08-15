import Foundation

protocol LibraryRepository: Sendable {
    func load() async throws -> LibraryState
    func save(_ library: LibraryState) async throws
    func loadAsset(id: AssetID, contentType: String) async throws -> DocumentAsset?
}

extension LibraryRepository {
    func loadAsset(id: AssetID, contentType: String) async throws -> DocumentAsset? { nil }
}

actor LocalLibraryRepository: LibraryRepository {
    static let maximumLibraryByteCount = 64 * 1_024 * 1_024

    private let fileURL: URL
    private var assetsURL: URL {
        fileURL.deletingLastPathComponent().appending(path: "Assets", directoryHint: .isDirectory)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async throws -> LibraryState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let encodedLibrary = try BoundedFileReader(
            maximumByteCount: Self.maximumLibraryByteCount
        ).readIfPresent(from: fileURL) else {
            return LibraryState()
        }
        var library = try decoder.decode(LibraryState.self, from: encodedLibrary)
        for asset in library.assets where !asset.data.isEmpty {
            try saveAssetIfNeeded(asset)
            library.storeAsset(DocumentAsset(id: asset.id, data: Data(), contentType: asset.contentType))
        }
        return library
    }

    func save(_ library: LibraryState) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        for asset in library.assets {
            try saveAssetIfNeeded(asset)
        }
        try encoder.encode(library.replacingAssetDataWithPlaceholders()).write(
            to: fileURL,
            options: [.atomic, .completeFileProtection]
        )
    }

    func loadAsset(id: AssetID, contentType: String) async throws -> DocumentAsset? {
        let url = assetFileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return DocumentAsset(
            id: id,
            data: try BoundedFileReader().read(from: url),
            contentType: contentType
        )
    }

    private func saveAssetIfNeeded(_ asset: DocumentAsset) throws {
        guard !asset.data.isEmpty else { return }
        let url = assetFileURL(for: asset.id)
        if fileManagerContains(asset.data, at: url) { return }
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try asset.data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func fileManagerContains(_ expectedData: Data, at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              values.fileSize == expectedData.count,
              let storedData = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return false
        }
        return storedData == expectedData
    }

    private func assetFileURL(for id: AssetID) -> URL {
        assetsURL.appending(path: id.rawValue.uuidString)
    }
}
