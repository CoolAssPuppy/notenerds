import Foundation

enum NotionPageProperties {
    static func make(
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) throws -> [String: NotionJSONValue] {
        [
            "Name": .object(["title": .array(try richText(snapshot.row.name))]),
            "Folder": .object(["rich_text": .array(try richText(snapshot.row.folderPath))]),
            "Folder ID": .object(["rich_text": .array(try richText(snapshot.row.folderID))]),
            "Notebook ID": .object(["rich_text": .array(try richText(snapshot.row.notebookID))]),
            "Modified": date(snapshot.row.modifiedAt),
            "Trash Date": optionalDate(snapshot.row.trashedAt),
            "Canvas Count": .object(["number": .number(Double(snapshot.row.canvasCount))]),
            "Tags": .object([
                "multi_select": .array(snapshot.row.tags.map {
                    .object(["name": .string(notionMultiSelectName($0))])
                })
            ]),
            "Favorite": .object(["checkbox": .bool(snapshot.row.isFavorite)]),
            "Schema Version": .object(["number": .number(Double(snapshot.row.schemaVersion))]),
            "Content Hash": .object(["rich_text": .array(try richText(snapshot.row.contentHash))]),
            "Native Notebook": file(files.nativeUploadID),
            "PDF": file(files.pdfUploadID),
            "Sync Status": .object([
                "select": .object(["name": .string(snapshot.row.syncStatus.rawValue)])
            ])
        ]
    }

    private static func richText(_ value: String) throws -> [NotionJSONValue] {
        let chunks = value.chunked(maximumCharacterCount: 2_000)
        guard chunks.count <= 100 else { throw NotionAPIError.payloadTooLarge }
        return chunks.map { chunk in
            .object([
                "type": .string("text"),
                "text": .object(["content": .string(chunk)])
            ])
        }
    }

    private static func date(_ value: Date) -> NotionJSONValue {
        .object(["date": .object(["start": .string(iso8601(value))])])
    }

    private static func optionalDate(_ value: Date?) -> NotionJSONValue {
        guard let value else { return .object(["date": .null]) }
        return date(value)
    }

    private static func file(_ uploadID: String?) -> NotionJSONValue {
        guard let uploadID else { return .object(["files": .array([])]) }
        return .object([
            "files": .array([
                .object([
                    "type": .string("file_upload"),
                    "file_upload": .object(["id": .string(uploadID)])
                ])
            ])
        ])
    }

    private static func notionMultiSelectName(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: "，")
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private extension String {
    func chunked(maximumCharacterCount: Int) -> [String] {
        guard !isEmpty else { return [] }
        var chunks: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: maximumCharacterCount, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }
        return chunks
    }
}
