import Foundation

enum NotionNotebookPayloadError: Error, Equatable, Sendable {
    case missingAsset(AssetID)
    case duplicateCanvasIdentifier(CanvasID)
}

struct NotionNotebookPayloadBuilder: Sendable {
    private let archive: NotionTransportArchive
    private let maximumPreviewDimension: Double

    init(
        archive: NotionTransportArchive = NotionTransportArchive(),
        maximumPreviewDimension: Double = 1_024
    ) {
        self.archive = archive
        self.maximumPreviewDimension = maximumPreviewDimension
    }

    func build(
        notebook: Notebook,
        library: LibraryState,
        exportedAt: Date
    ) async throws -> NotionNotebookPayload {
        let assets = try referencedAssets(for: notebook, in: library)
        let archive = self.archive
        let (nativeFile, snapshot) = try await Task.detached(priority: .userInitiated) {
            let encodedArchive = try archive.encode(
                package: NativeNotebookPackage(schemaVersion: .current, notebook: notebook),
                assets: assets,
                exportedAt: exportedAt
            )
            let nativeFile = try NotionTransportFile.encode(encodedArchive)
            let snapshot = try NotionNotebookMapper.snapshot(
                for: notebook,
                in: library,
                contentHash: NotionContentHasher.sha256Hex(of: nativeFile)
            )
            return (nativeFile, snapshot)
        }.value
        return try await renderPayload(
            notebook: notebook,
            assets: assets,
            nativeArchive: nativeFile,
            snapshot: snapshot
        )
    }

    @MainActor
    private func renderPayload(
        notebook: Notebook,
        assets: [DocumentAsset],
        nativeArchive: Data,
        snapshot: NotionNotebookSnapshot
    ) throws -> NotionNotebookPayload {
        let pngExporter = CanvasPNGExporter()
        let previews = try renderPreviews(notebook: notebook, exporter: pngExporter)
        return NotionNotebookPayload(
            snapshot: snapshot,
            nativeArchive: nativeArchive,
            pdf: try NotebookPDFExporter().export(notebook, assets: assets),
            previews: previews
        )
    }

    @MainActor
    private func renderPreviews(
        notebook: Notebook,
        exporter: CanvasPNGExporter
    ) throws -> [String: Data] {
        var previews: [String: Data] = [:]
        for canvas in notebook.canvases {
            let identifier = canvas.id.rawValue.uuidString.lowercased()
            guard previews[identifier] == nil else {
                throw NotionNotebookPayloadError.duplicateCanvasIdentifier(canvas.id)
            }
            let bounds = canvas.exportBounds
            let longestSide = max(bounds.size.width, bounds.size.height)
            let scale = min(1, maximumPreviewDimension / max(longestSide, 1))
            previews[identifier] = try exporter.export(canvas, region: bounds, scale: scale)
        }
        return previews
    }

    private func referencedAssets(
        for notebook: Notebook,
        in library: LibraryState
    ) throws -> [DocumentAsset] {
        let identifiers = Set(
            notebook.canvases
                .flatMap(\.layers)
                .flatMap(\.objects)
                .compactMap(Self.assetID)
        )
        return try identifiers
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
            .map { identifier in
                guard let asset = library.asset(id: identifier) else {
                    throw NotionNotebookPayloadError.missingAsset(identifier)
                }
                return asset
            }
    }

    private static func assetID(for object: CanvasObject) -> AssetID? {
        switch object {
        case let .image(image): image.assetID
        case let .pdf(pdf): pdf.assetID
        case .stroke, .shape, .text: nil
        }
    }
}
