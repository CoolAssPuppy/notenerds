import Foundation

enum NotionManagedPageError: Error, Equatable, Sendable {
    case missingPreview(String)
    case textTooLarge
}

struct NotionManagedPagePlan: Equatable, Sendable {
    let root: NotionJSONValue
    let children: [NotionJSONValue]
}

enum NotionManagedPageBuilder {
    static let marker = "note-nerds-managed-v1"
    static let title = "Note Nerds content"

    static func plan(
        snapshot: NotionNotebookSnapshot,
        previewUploadIDs: [String: String],
        files: NotionNotebookRemoteFiles,
        syncedAt: Date
    ) throws -> NotionManagedPagePlan {
        var children = [
            code(marker),
            paragraph("Notebook ID: \(snapshot.row.notebookID)"),
            callout(metadata(snapshot: snapshot, syncedAt: syncedAt))
        ]
        for canvas in snapshot.canvases {
            guard let previewID = previewUploadIDs[canvas.canvasID] else {
                throw NotionManagedPageError.missingPreview(canvas.canvasID)
            }
            children.append(heading("heading_2", canvas.title))
            children.append(code("Canvas ID: \(canvas.canvasID)"))
            children.append(
                paragraph("Paper: \(canvas.paperType.displayName), layers: \(canvas.layerCount)")
            )
            children.append(image(uploadID: previewID))
            try appendSection(title: "Typed text", values: canvas.typedText, to: &children)
            try appendSection(
                title: "Recognized handwriting",
                values: canvas.recognizedHandwriting,
                to: &children
            )
            try appendSection(title: "PDF text", values: canvas.embeddedPDFText, to: &children)
        }
        children.append(pdf(uploadID: files.pdfUploadID, caption: "PDF"))
        children.append(file(uploadID: files.nativeUploadID, caption: "Native notebook"))
        return NotionManagedPagePlan(
            root: .object([
                "type": .string("toggle"),
                "toggle": .object(["rich_text": .array([richText(title)])])
            ]),
            children: children
        )
    }

    private static func metadata(snapshot: NotionNotebookSnapshot, syncedAt: Date) -> String {
        var lines = [
            "Note Nerds copy",
            "Last synced: \(timestamp(syncedAt))",
            "Status: \(snapshot.row.syncStatus.rawValue)",
            "Modified: \(timestamp(snapshot.row.modifiedAt))",
            "Folder: \(folderSummary(snapshot.row.folderPath))",
            "Canvases: \(snapshot.row.canvasCount)"
        ]
        if let trashedAt = snapshot.row.trashedAt {
            lines.append("Trash date: \(timestamp(trashedAt))")
        }
        return lines.joined(separator: "\n")
    }

    private static func appendSection(
        title: String,
        values: [String],
        to children: inout [NotionJSONValue]
    ) throws {
        let chunks = values.flatMap { $0.chunkedForNotion() }
        guard chunks.count <= 10_000 else { throw NotionManagedPageError.textTooLarge }
        guard !chunks.isEmpty else { return }
        children.append(heading("heading_3", title))
        children.append(contentsOf: chunks.map(paragraph))
    }

    private static func heading(_ type: String, _ text: String) -> NotionJSONValue {
        .object([
            "type": .string(type),
            type: .object(["rich_text": .array([richText(String(text.prefix(2_000)))])])
        ])
    }

    private static func paragraph(_ text: String) -> NotionJSONValue {
        .object([
            "type": .string("paragraph"),
            "paragraph": .object(["rich_text": .array([richText(text)])])
        ])
    }

    private static func callout(_ text: String) -> NotionJSONValue {
        .object([
            "type": .string("callout"),
            "callout": .object(["rich_text": .array([richText(text)])])
        ])
    }

    private static func code(_ text: String) -> NotionJSONValue {
        .object([
            "type": .string("code"),
            "code": .object([
                "rich_text": .array([richText(text)]),
                "language": .string("plain text")
            ])
        ])
    }

    private static func image(uploadID: String) -> NotionJSONValue {
        .object([
            "type": .string("image"),
            "image": .object([
                "type": .string("file_upload"),
                "file_upload": .object(["id": .string(uploadID)])
            ])
        ])
    }

    private static func file(uploadID: String, caption: String) -> NotionJSONValue {
        .object([
            "type": .string("file"),
            "file": .object([
                "type": .string("file_upload"),
                "file_upload": .object(["id": .string(uploadID)]),
                "caption": .array([richText(caption)])
            ])
        ])
    }

    private static func pdf(uploadID: String, caption: String) -> NotionJSONValue {
        .object([
            "type": .string("pdf"),
            "pdf": .object([
                "type": .string("file_upload"),
                "file_upload": .object(["id": .string(uploadID)]),
                "caption": .array([richText(caption)])
            ])
        ])
    }

    private static func richText(_ text: String) -> NotionJSONValue {
        .object([
            "type": .string("text"),
            "text": .object(["content": .string(text)])
        ])
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func folderSummary(_ folderPath: String) -> String {
        guard !folderPath.isEmpty else { return "My Notebooks" }
        return String(folderPath.prefix(1_000))
    }
}

private extension String {
    func chunkedForNotion() -> [String] {
        guard !isEmpty else { return [] }
        var result: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: 2_000, limitedBy: endIndex) ?? endIndex
            result.append(String(self[start..<end]))
            start = end
        }
        return result
    }
}
