import Foundation

enum NotionNotebookPayloadError: Error, Equatable, Sendable {
    case missingAsset(AssetID)
    case duplicateCanvasIdentifier(CanvasID)
}

struct NotionNotebookPayloadPreparation: Sendable {
    let notebook: Notebook
    let assets: [DocumentAsset]
    let nativeArchive: Data
    let snapshot: NotionNotebookSnapshot
}

protocol NotionNotebookPayloadRendering: Sendable {
    func render(
        _ preparation: NotionNotebookPayloadPreparation,
        maximumPreviewDimension: Double
    ) throws -> NotionNotebookPayload
}

struct NotionNotebookPayloadBuilder: Sendable {
    private let archive: NotionTransportArchive
    private let renderer: any NotionNotebookPayloadRendering
    private let maximumPreviewDimension: Double

    init(
        archive: NotionTransportArchive = NotionTransportArchive(),
        renderer: any NotionNotebookPayloadRendering = NotionNotebookPayloadRenderer(),
        maximumPreviewDimension: Double = 512
    ) {
        self.archive = archive
        self.renderer = renderer
        self.maximumPreviewDimension = maximumPreviewDimension
    }

    func build(
        notebook: Notebook,
        library: LibraryState,
        exportedAt: Date
    ) async throws -> NotionNotebookPayload {
        let preparation = try await prepare(
            notebook: notebook,
            library: library,
            exportedAt: exportedAt
        )
        return try await render(preparation)
    }

    func prepare(
        notebook: Notebook,
        library: LibraryState,
        exportedAt: Date
    ) async throws -> NotionNotebookPayloadPreparation {
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
        return NotionNotebookPayloadPreparation(
            notebook: notebook,
            assets: assets,
            nativeArchive: nativeFile,
            snapshot: snapshot
        )
    }

    func render(
        _ preparation: NotionNotebookPayloadPreparation
    ) async throws -> NotionNotebookPayload {
        let renderer = renderer
        let maximumPreviewDimension = maximumPreviewDimension
        return try await Task.detached(priority: .utility) {
            try renderer.render(
                preparation,
                maximumPreviewDimension: maximumPreviewDimension
            )
        }.value
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
                guard let asset = library.asset(id: identifier), !asset.data.isEmpty else {
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

struct NotionNotebookPayloadRenderer: NotionNotebookPayloadRendering {
    func render(
        _ preparation: NotionNotebookPayloadPreparation,
        maximumPreviewDimension: Double
    ) throws -> NotionNotebookPayload {
        let previews = try renderPreviews(
            notebook: preparation.notebook,
            maximumPreviewDimension: maximumPreviewDimension
        )
        return NotionNotebookPayload(
            snapshot: preparation.snapshot,
            nativeArchive: preparation.nativeArchive,
            pdf: try NotebookPDFExporter().export(
                preparation.notebook,
                assets: preparation.assets
            ),
            previews: previews
        )
    }

    private func renderPreviews(
        notebook: Notebook,
        maximumPreviewDimension: Double
    ) throws -> [String: Data] {
        let exporter = CanvasPNGExporter()
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
}
