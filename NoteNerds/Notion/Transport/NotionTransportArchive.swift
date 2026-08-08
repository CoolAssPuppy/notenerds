import Foundation

struct NotionTransportArchive: Sendable {
    private static let magic = Data("NNARCH01".utf8)
    private static let headerByteCount = 16

    private let limits: NotionTransportLimits
    private let serializer: NativeDocumentSerializer

    init(
        limits: NotionTransportLimits = NotionTransportLimits(),
        serializer: NativeDocumentSerializer = NativeDocumentSerializer()
    ) {
        self.limits = limits
        self.serializer = serializer
    }

    func encode(
        package: NativeNotebookPackage,
        assets: [DocumentAsset],
        exportedAt: Date
    ) throws -> Data {
        let sortedAssets = assets.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        let manifestEntries = sortedAssets.map { asset in
            NotionTransportAssetEntry(
                id: asset.id,
                contentType: asset.contentType,
                filename: asset.id.rawValue.uuidString
            )
        }
        let manifest = NotionTransportAssetManifest(assets: manifestEntries)
        let components = try archiveComponents(package: package, assets: sortedAssets, manifest: manifest)
        try validateEncodeBounds(components: components, assetCount: sortedAssets.count)
        let entries = makeEntries(components)
        let payloadByteCount = try checkedSum(entries.map(\.byteCount))
        let index = NotionTransportIndex(
            schemaVersion: NotionTransportIndex.currentSchemaVersion,
            notebookID: package.notebook.id.rawValue.uuidString.lowercased(),
            exportedAt: exportedAt,
            uncompressedByteCount: payloadByteCount,
            assetCount: sortedAssets.count,
            entries: entries
        )
        let indexData = try encodeJSON(index)
        guard indexData.count <= limits.maximumIndexByteCount else {
            throw NotionTransportArchiveError.indexTooLarge
        }
        var archive = Self.magic
        archive.reserveCapacity(Self.headerByteCount + indexData.count + payloadByteCount)
        archive.append(contentsOf: UInt64(indexData.count).networkBytes)
        archive.append(indexData)
        for component in components {
            archive.append(component.data)
        }
        return archive
    }

    func decode(_ archive: Data) throws -> NativeArchiveContents {
        let parsed = try parseHeader(archive)
        let index = try decodeIndex(parsed.indexData)
        let payloadByteCount = archive.count - parsed.payloadStart
        try validate(index: index, payloadByteCount: payloadByteCount)

        var dataByPath: [String: Data] = [:]
        for entry in index.entries {
            let start = parsed.payloadStart + entry.offset
            let data = archive.subdata(in: start..<(start + entry.byteCount))
            guard NotionContentHasher.sha256Hex(of: data) == entry.sha256 else {
                throw NotionTransportArchiveError.checksumMismatch(entry.path)
            }
            dataByPath[entry.path] = data
        }
        let documentData = try requiredData("Document.json", in: dataByPath)
        let manifestData = try requiredData("Manifest.json", in: dataByPath)
        let package = try serializer.decode(documentData)
        guard package.notebook.id.rawValue.uuidString.lowercased() == index.notebookID else {
            throw NotionTransportArchiveError.notebookMismatch
        }
        let manifest = try decodeManifest(manifestData)
        guard manifest.assets.count == index.assetCount else {
            throw NotionTransportArchiveError.invalidManifest
        }
        let assets = try manifest.assets.map { entry in
            let expectedFilename = entry.id.rawValue.uuidString
            guard entry.filename == expectedFilename,
                  let data = dataByPath["Assets/\(expectedFilename)"] else {
                throw NotionTransportArchiveError.invalidManifest
            }
            return DocumentAsset(id: entry.id, data: data, contentType: entry.contentType)
        }
        guard Set(assets.map(\.id)).count == assets.count else {
            throw NotionTransportArchiveError.invalidManifest
        }
        return NativeArchiveContents(package: package, assets: assets)
    }

    private func archiveComponents(
        package: NativeNotebookPackage,
        assets: [DocumentAsset],
        manifest: NotionTransportAssetManifest
    ) throws -> [(path: String, data: Data)] {
        var components = [
            (path: "Document.json", data: try serializer.encode(package)),
            (path: "Manifest.json", data: try encodeJSON(manifest))
        ]
        components.append(contentsOf: assets.map { asset in
            (path: "Assets/\(asset.id.rawValue.uuidString)", data: asset.data)
        })
        return components
    }

    private func makeEntries(_ components: [(path: String, data: Data)]) -> [NotionTransportEntry] {
        var offset = 0
        return components.map { component in
            defer { offset += component.data.count }
            return NotionTransportEntry(
                path: component.path,
                offset: offset,
                byteCount: component.data.count,
                sha256: NotionContentHasher.sha256Hex(of: component.data)
            )
        }
    }

    private func validateEncodeBounds(
        components: [(path: String, data: Data)],
        assetCount: Int
    ) throws {
        guard components.count <= limits.maximumEntryCount else {
            throw NotionTransportArchiveError.tooManyEntries
        }
        let metadataBytes = try checkedSum(components.prefix(2).map { $0.data.count })
        guard metadataBytes <= limits.maximumMetadataByteCount else {
            throw NotionTransportArchiveError.metadataTooLarge
        }
        let assetBytes = try checkedSum(components.dropFirst(2).map { $0.data.count })
        guard assetCount == components.count - 2, assetBytes <= limits.maximumAssetByteCount else {
            throw NotionTransportArchiveError.assetsTooLarge
        }
    }

    private func parseHeader(_ archive: Data) throws -> (indexData: Data, payloadStart: Int) {
        guard archive.count >= Self.headerByteCount,
              archive.prefix(Self.magic.count) == Self.magic else {
            throw NotionTransportArchiveError.invalidHeader
        }
        let rawLength = archive[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard rawLength <= UInt64(limits.maximumIndexByteCount),
              rawLength <= UInt64(Int.max) else {
            throw NotionTransportArchiveError.indexTooLarge
        }
        let indexEnd = Self.headerByteCount + Int(rawLength)
        guard indexEnd <= archive.count else { throw NotionTransportArchiveError.invalidLength }
        return (
            Data(archive[Self.headerByteCount..<indexEnd]),
            indexEnd
        )
    }

    private func decodeIndex(_ data: Data) throws -> NotionTransportIndex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let index = try decoder.decode(NotionTransportIndex.self, from: data)
        guard index.schemaVersion == NotionTransportIndex.currentSchemaVersion else {
            throw NotionTransportArchiveError.unsupportedSchema(index.schemaVersion)
        }
        return index
    }

    private func validate(index: NotionTransportIndex, payloadByteCount: Int) throws {
        guard index.entries.count <= limits.maximumEntryCount else {
            throw NotionTransportArchiveError.tooManyEntries
        }
        guard Set(index.entries.map(\.path)).count == index.entries.count else {
            throw NotionTransportArchiveError.duplicatePath
        }
        try index.entries.forEach { try guardSafePath($0.path) }
        let requiredPaths = ["Document.json", "Manifest.json"]
        for required in requiredPaths where !index.entries.contains(where: { $0.path == required }) {
            throw NotionTransportArchiveError.missingRequiredEntry(required)
        }
        var expectedOffset = 0
        for entry in index.entries {
            guard entry.offset == expectedOffset, entry.byteCount >= 0 else {
                throw NotionTransportArchiveError.invalidLength
            }
            let (end, overflow) = entry.offset.addingReportingOverflow(entry.byteCount)
            guard !overflow, end <= payloadByteCount else {
                throw NotionTransportArchiveError.invalidLength
            }
            expectedOffset = end
        }
        guard expectedOffset == payloadByteCount,
              index.uncompressedByteCount == payloadByteCount else {
            throw NotionTransportArchiveError.invalidLength
        }
        try validateDecodeBounds(index.entries)
    }

    private func validateDecodeBounds(_ entries: [NotionTransportEntry]) throws {
        let metadata = try checkedSum(entries.filter { !$0.path.hasPrefix("Assets/") }.map(\.byteCount))
        guard metadata <= limits.maximumMetadataByteCount else {
            throw NotionTransportArchiveError.metadataTooLarge
        }
        let assets = try checkedSum(entries.filter { $0.path.hasPrefix("Assets/") }.map(\.byteCount))
        guard assets <= limits.maximumAssetByteCount else {
            throw NotionTransportArchiveError.assetsTooLarge
        }
    }

    private func guardSafePath(_ path: String) throws {
        if path == "Document.json" || path == "Manifest.json" { return }
        guard path.hasPrefix("Assets/") else { throw NotionTransportArchiveError.unsafePath }
        let filename = String(path.dropFirst("Assets/".count))
        guard !filename.contains("/"),
              let identifier = UUID(uuidString: filename),
              identifier.uuidString == filename else {
            throw NotionTransportArchiveError.unsafePath
        }
    }

    private func requiredData(_ path: String, in entries: [String: Data]) throws -> Data {
        guard let data = entries[path] else {
            throw NotionTransportArchiveError.missingRequiredEntry(path)
        }
        return data
    }

    private func decodeManifest(_ data: Data) throws -> NotionTransportAssetManifest {
        do {
            return try JSONDecoder().decode(NotionTransportAssetManifest.self, from: data)
        } catch {
            throw NotionTransportArchiveError.invalidManifest
        }
    }

    private func encodeJSON<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func checkedSum<S: Sequence>(_ values: S) throws -> Int where S.Element == Int {
        try values.reduce(0) { total, value in
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { throw NotionTransportArchiveError.invalidLength }
            return sum
        }
    }
}

private extension UInt64 {
    var networkBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}
