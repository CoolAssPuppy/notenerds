import Foundation

actor LocalLibraryRepository {
    private let fileURL: URL
    private var assetsURL: URL {
        fileURL.deletingLastPathComponent().appending(path: "Assets", directoryHint: .isDirectory)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> LibraryState {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else { return LibraryState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var library = try decoder.decode(LibraryState.self, from: Data(contentsOf: fileURL))
        for asset in library.assets {
            let assetURL = assetFileURL(for: asset.id)
            if FileManager.default.fileExists(atPath: assetURL.path) {
                library.storeAsset(DocumentAsset(
                    id: asset.id,
                    data: try BoundedFileReader().read(from: assetURL),
                    contentType: asset.contentType
                ))
            } else if !asset.data.isEmpty {
                try saveAssetIfNeeded(asset)
            }
        }
        return library
    }

    func save(_ library: LibraryState) throws {
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

    private func saveAssetIfNeeded(_ asset: DocumentAsset) throws {
        let url = assetFileURL(for: asset.id)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        try asset.data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func assetFileURL(for id: AssetID) -> URL {
        assetsURL.appending(path: id.rawValue.uuidString)
    }
}
