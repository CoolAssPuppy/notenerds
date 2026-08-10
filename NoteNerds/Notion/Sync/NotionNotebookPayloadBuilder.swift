import Foundation

enum NotionNotebookPayloadError: Error, Equatable, Sendable {
    case duplicateCanvasIdentifier(CanvasID)
}

struct NotionNotebookPayloadBuilder: Sendable {
    private let maximumPreviewDimension: Double

    init(maximumPreviewDimension: Double = 512) {
        self.maximumPreviewDimension = maximumPreviewDimension
    }

    func build(
        notebook: Notebook,
        library: LibraryState,
        exportedAt _: Date
    ) async throws -> NotionNotebookPayload {
        let notebookData = try await Task.detached(priority: .userInitiated) {
            try NativeDocumentSerializer().encode(
                NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
            )
        }.value
        let snapshot = try NotionNotebookMapper.snapshot(
            for: notebook,
            in: library,
            contentHash: NotionContentHasher.sha256Hex(of: notebookData)
        )
        return try await renderPayload(
            notebook: notebook,
            snapshot: snapshot
        )
    }

    @MainActor
    private func renderPayload(
        notebook: Notebook,
        snapshot: NotionNotebookSnapshot
    ) throws -> NotionNotebookPayload {
        let pngExporter = CanvasPNGExporter()
        let previews = try renderPreviews(notebook: notebook, exporter: pngExporter)
        return NotionNotebookPayload(
            snapshot: snapshot,
            nativeArchive: Data(),
            pdf: Data(),
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
}
