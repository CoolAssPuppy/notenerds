import Foundation

enum NativeArchiveError: Error, Equatable {
    case destinationExists
    case missingAsset(AssetID)
    case unsafeAssetPath
}

struct NativeArchiveContents: Equatable, Sendable {
    let package: NativeNotebookPackage
    let assets: [DocumentAsset]
}

struct NativeNotebookArchive {
    private static let maximumTotalAssetByteCount = 1_024 * 1_024 * 1_024
    private struct AssetManifestEntry: Codable {
        let id: AssetID
        let contentType: String
        let filename: String
    }

    private struct Manifest: Codable {
        let assets: [AssetManifestEntry]
    }

    private let fileManager: FileManager
    private let serializer: NativeDocumentSerializer

    init(
        fileManager: FileManager = .default,
        serializer: NativeDocumentSerializer = NativeDocumentSerializer()
    ) {
        self.fileManager = fileManager
        self.serializer = serializer
    }

    func write(package: NativeNotebookPackage, assets: [DocumentAsset], to url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { throw NativeArchiveError.destinationExists }
        let assetsURL = url.appending(path: "Assets", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let entries = assets
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
            .map { asset in
                AssetManifestEntry(
                    id: asset.id,
                    contentType: asset.contentType,
                    filename: asset.id.rawValue.uuidString
                )
            }
        try serializer.encode(package).write(to: url.appending(path: "Document.json"), options: .atomic)
        try encodedManifest(Manifest(assets: entries)).write(
            to: url.appending(path: "Manifest.json"),
            options: .atomic
        )
        for (asset, entry) in zip(assets.sorted(by: assetOrder), entries) {
            try asset.data.write(to: assetsURL.appending(path: entry.filename), options: .atomic)
        }
    }

    func read(from url: URL) throws -> NativeArchiveContents {
        let packageData = try BoundedFileReader(maximumByteCount: 100 * 1_024 * 1_024)
            .read(from: url.appending(path: "Document.json"))
        let manifestData = try BoundedFileReader(maximumByteCount: 4 * 1_024 * 1_024)
            .read(from: url.appending(path: "Manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        let assetsURL = url.appending(path: "Assets", directoryHint: .isDirectory)
        var totalAssetByteCount = 0
        let assets = try manifest.assets.map { entry in
            guard entry.filename == entry.id.rawValue.uuidString else {
                throw NativeArchiveError.unsafeAssetPath
            }
            let assetURL = assetsURL.appending(path: entry.filename)
            guard fileManager.fileExists(atPath: assetURL.path) else {
                throw NativeArchiveError.missingAsset(entry.id)
            }
            let data = try BoundedFileReader().read(from: assetURL)
            totalAssetByteCount = try Self.checkedAssetTotal(totalAssetByteCount, adding: data.count)
            return DocumentAsset(
                id: entry.id,
                data: data,
                contentType: entry.contentType
            )
        }
        return NativeArchiveContents(package: try serializer.decode(packageData), assets: assets)
    }

    func fileWrapper(package: NativeNotebookPackage, assets: [DocumentAsset]) throws -> FileWrapper {
        let sortedAssets = assets.sorted(by: assetOrder)
        let entries = sortedAssets.map { asset in
            AssetManifestEntry(
                id: asset.id,
                contentType: asset.contentType,
                filename: asset.id.rawValue.uuidString
            )
        }
        let assetWrappers = Dictionary(uniqueKeysWithValues: zip(sortedAssets, entries).map { asset, entry in
            (entry.filename, FileWrapper(regularFileWithContents: asset.data))
        })
        return FileWrapper(directoryWithFileWrappers: [
            "Document.json": FileWrapper(regularFileWithContents: try serializer.encode(package)),
            "Manifest.json": FileWrapper(regularFileWithContents: try encodedManifest(Manifest(assets: entries))),
            "Assets": FileWrapper(directoryWithFileWrappers: assetWrappers)
        ])
    }

    private func encodedManifest(_ manifest: Manifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    private func assetOrder(_ first: DocumentAsset, _ second: DocumentAsset) -> Bool {
        first.id.rawValue.uuidString < second.id.rawValue.uuidString
    }

    private static func checkedAssetTotal(_ current: Int, adding count: Int) throws -> Int {
        let (total, overflow) = current.addingReportingOverflow(count)
        guard !overflow, total <= maximumTotalAssetByteCount else {
            throw BoundedFileReaderError.fileTooLarge
        }
        return total
    }
}
