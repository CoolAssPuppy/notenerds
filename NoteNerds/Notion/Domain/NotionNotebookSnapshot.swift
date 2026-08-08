import CryptoKit
import Foundation

enum NotionNotebookSyncStatus: String, Codable, Equatable, Sendable {
    case complete = "Complete"
    case inTrash = "In Trash"
}

struct NotionNotebookRow: Codable, Equatable, Sendable {
    let name: String
    let folderPath: String
    let folderID: String
    let notebookID: String
    let modifiedAt: Date
    let canvasCount: Int
    let tags: [String]
    let isFavorite: Bool
    let schemaVersion: Int
    let contentHash: String
    let syncStatus: NotionNotebookSyncStatus
    let trashedAt: Date?
}

struct NotionCanvasSnapshot: Codable, Equatable, Sendable {
    let canvasID: String
    let title: String
    let paperType: PaperType
    let layerCount: Int
    let typedText: [String]
    let recognizedHandwriting: [String]
    let embeddedPDFText: [String]
}

struct NotionNotebookSnapshot: Codable, Equatable, Sendable {
    let row: NotionNotebookRow
    let canvases: [NotionCanvasSnapshot]
}

enum NotionNotebookMapper {
    static func snapshot(
        for notebook: Notebook,
        in library: LibraryState,
        contentHash: String
    ) throws -> NotionNotebookSnapshot {
        let row = NotionNotebookRow(
            name: notebook.title,
            folderPath: try NotionFolderPathResolver.path(for: notebook.parentFolderID, in: library),
            folderID: notebook.parentFolderID?.notionValue ?? "",
            notebookID: notebook.id.rawValue.uuidString.lowercased(),
            modifiedAt: notebook.modifiedAt,
            canvasCount: notebook.canvases.count,
            tags: notebook.tags.sorted(),
            isFavorite: notebook.isFavorite,
            schemaVersion: DocumentSchemaVersion.current.rawValue,
            contentHash: contentHash,
            syncStatus: notebook.trashedAt == nil ? .complete : .inTrash,
            trashedAt: notebook.trashedAt
        )
        return NotionNotebookSnapshot(
            row: row,
            canvases: notebook.canvases.map { canvasSnapshot($0, in: notebook) }
        )
    }

    private static func canvasSnapshot(_ canvas: Canvas, in notebook: Notebook) -> NotionCanvasSnapshot {
        let objects = canvas.layers.flatMap(\.objects)
        return NotionCanvasSnapshot(
            canvasID: canvas.id.rawValue.uuidString.lowercased(),
            title: canvas.title,
            paperType: canvas.template,
            layerCount: canvas.layers.count,
            typedText: objects.compactMap(typedText),
            recognizedHandwriting: notebook.recognitionByCanvas[canvas.id, default: []]
                .compactMap { normalizedText($0.result.text) },
            embeddedPDFText: objects.compactMap(pdfText)
        )
    }

    private static func typedText(_ object: CanvasObject) -> String? {
        guard case let .text(text) = object else { return nil }
        return normalizedText(text.text)
    }

    private static func pdfText(_ object: CanvasObject) -> String? {
        guard case let .pdf(pdf) = object, let text = pdf.embeddedText else { return nil }
        return normalizedText(text)
    }

    private static func normalizedText(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum NotionContentHasher {
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension FolderID {
    var notionValue: String { rawValue.uuidString.lowercased() }
}
