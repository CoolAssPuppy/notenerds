import Foundation

enum NotionNotebookPayloadError: Error, Equatable, Sendable {
    case missingAsset(AssetID)
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
        let (nativeArchive, snapshot) = try await Task.detached(priority: .userInitiated) {
            let nativeArchive = try archive.encode(
                package: NativeNotebookPackage(schemaVersion: .current, notebook: notebook),
                assets: assets,
                exportedAt: exportedAt
            )
            let snapshot = try NotionNotebookMapper.snapshot(
                for: notebook,
                in: library,
                contentHash: NotionContentHasher.sha256Hex(of: nativeArchive)
            )
            return (nativeArchive, snapshot)
        }.value
        return try await renderPayload(
            notebook: notebook,
            assets: assets,
            nativeArchive: nativeArchive,
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
        let previews = try Dictionary(
            uniqueKeysWithValues: notebook.canvases.map { canvas in
                let bounds = canvas.exportBounds
                let longestSide = max(bounds.size.width, bounds.size.height)
                let scale = min(1, maximumPreviewDimension / max(longestSide, 1))
                return (
                    canvas.id.rawValue.uuidString.lowercased(),
                    try pngExporter.export(canvas, region: bounds, scale: scale)
                )
            }
        )
        return NotionNotebookPayload(
            snapshot: snapshot,
            nativeArchive: nativeArchive,
            pdf: try NotebookPDFExporter().export(notebook, assets: assets),
            previews: previews
        )
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
