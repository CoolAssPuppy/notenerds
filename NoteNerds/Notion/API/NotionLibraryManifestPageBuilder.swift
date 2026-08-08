import Foundation

enum NotionLibraryManifestPageBuilder {
    static let marker = "note-nerds-library-manifest-v1"
    static let title = "Note Nerds library manifest"

    static func plan(uploadID: String) throws -> NotionManagedPagePlan {
        guard UUID(uuidString: uploadID) != nil else { throw NotionAPIError.invalidIdentifier }
        return NotionManagedPagePlan(
            root: .object([
                "type": .string("toggle"),
                "toggle": .object(["rich_text": .array([richText(title)])])
            ]),
            children: [
                .object([
                    "type": .string("code"),
                    "code": .object([
                        "rich_text": .array([richText(marker)]),
                        "language": .string("plain text")
                    ])
                ]),
                .object([
                    "type": .string("file"),
                    "file": .object([
                        "type": .string("file_upload"),
                        "file_upload": .object(["id": .string(uploadID)])
                    ])
                ])
            ]
        )
    }

    private static func richText(_ text: String) -> NotionJSONValue {
        .object([
            "type": .string("text"),
            "text": .object(["content": .string(text)])
        ])
    }
}
