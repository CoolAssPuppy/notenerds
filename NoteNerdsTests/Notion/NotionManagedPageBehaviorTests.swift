import XCTest
@testable import NoteNerds

final class NotionManagedPageBehaviorTests: XCTestCase {
    func testManagedPagePlacesEveryCanvasInsideOneOrderedNotebookSection() throws {
        let snapshot = NotionNotebookSnapshot.fixture()
        let plan = try NotionManagedPageBuilder.plan(
            snapshot: snapshot,
            previewUploadIDs: [
                snapshot.canvases[0].canvasID: "11111111-1111-1111-1111-111111111111",
                snapshot.canvases[1].canvasID: "22222222-2222-2222-2222-222222222222"
            ],
            files: remoteFiles,
            syncedAt: DomainFixtures.fixedDate
        )
        let root = try jsonObject(plan.root)
        let rootToggle = try XCTUnwrap(root["toggle"] as? [String: Any])
        let serializedChildren = try plan.children.map(jsonString).joined(separator: "\n")

        XCTAssertEqual(root["type"] as? String, "toggle")
        XCTAssertEqual(try richTextContent(rootToggle), "Note Nerds content")
        XCTAssertTrue(serializedChildren.contains("note-nerds-managed-v1"))
        XCTAssertTrue(serializedChildren.contains(snapshot.row.notebookID))
        XCTAssertTrue(serializedChildren.contains("First typed note"))
        XCTAssertTrue(serializedChildren.contains("First handwriting"))
        XCTAssertTrue(serializedChildren.contains("Reference text"))
        XCTAssertTrue(
            serializedChildren.contains("11111111-1111-1111-1111-111111111111"),
            serializedChildren
        )
        XCTAssertTrue(
            serializedChildren.contains("22222222-2222-2222-2222-222222222222"),
            serializedChildren
        )
        XCTAssertTrue(serializedChildren.contains("Last synced"))
        XCTAssertTrue(serializedChildren.contains(iso8601(DomainFixtures.fixedDate)))
        XCTAssertTrue(serializedChildren.contains("Note Nerds copy"))
        XCTAssertTrue(serializedChildren.contains("Open in Note Nerds"))
        XCTAssertEqual(
            try linkedURL(plan.children[3]),
            "notenerds://notebook/\(snapshot.row.notebookID)"
        )
        XCTAssertTrue(serializedChildren.contains("Native notebook"))
        XCTAssertTrue(serializedChildren.contains("PDF"))
        XCTAssertTrue(serializedChildren.contains("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        XCTAssertTrue(serializedChildren.contains("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        XCTAssertEqual(serializedChildren.components(separatedBy: #""type":"file""#).count - 1, 1)
        XCTAssertEqual(serializedChildren.components(separatedBy: #""type":"pdf""#).count - 1, 1)
        XCTAssertEqual(serializedChildren.components(separatedBy: #""type":"callout""#).count - 1, 1)
        let firstRange = try XCTUnwrap(serializedChildren.range(of: "Opening"))
        let secondRange = try XCTUnwrap(serializedChildren.range(of: "Details"))
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound)
    }

    func testManagedPageSplitsNotionTextAtTwoThousandCharacters() throws {
        var snapshot = NotionNotebookSnapshot.fixture()
        let longText = String(repeating: "a", count: 4_001)
        snapshot = NotionNotebookSnapshot(
            row: snapshot.row,
            canvases: [
                NotionCanvasSnapshot(
                    canvasID: snapshot.canvases[0].canvasID,
                    title: "Long text",
                    paperType: .blankWhite,
                    layerCount: 1,
                    typedText: [longText],
                    recognizedHandwriting: [],
                    embeddedPDFText: []
                )
            ]
        )
        let plan = try NotionManagedPageBuilder.plan(
            snapshot: snapshot,
            previewUploadIDs: [snapshot.canvases[0].canvasID: "11111111-1111-1111-1111-111111111111"],
            files: remoteFiles,
            syncedAt: DomainFixtures.fixedDate
        )
        let textChunks = try plan.children.flatMap(paragraphText)

        XCTAssertTrue(textChunks.allSatisfy { $0.count <= 2_000 })
        XCTAssertEqual(textChunks.filter { $0.first == "a" }.map(\.count), [2_000, 2_000, 1])
    }

    func testManagedPageRequiresAPreviewForEveryCanvas() {
        let snapshot = NotionNotebookSnapshot.fixture()

        XCTAssertThrowsError(
            try NotionManagedPageBuilder.plan(
                snapshot: snapshot,
                previewUploadIDs: [:],
                files: remoteFiles,
                syncedAt: DomainFixtures.fixedDate
            )
        ) { error in
            XCTAssertEqual(
                error as? NotionManagedPageError,
                .missingPreview(snapshot.canvases[0].canvasID)
            )
        }
    }

    func testManagedPageShowsTrashStatusAndDate() throws {
        let original = NotionNotebookSnapshot.fixture()
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(60)
        let snapshot = NotionNotebookSnapshot(
            row: NotionNotebookRow(
                name: original.row.name,
                folderPath: original.row.folderPath,
                folderID: original.row.folderID,
                notebookID: original.row.notebookID,
                modifiedAt: original.row.modifiedAt,
                canvasCount: original.row.canvasCount,
                tags: original.row.tags,
                isFavorite: original.row.isFavorite,
                schemaVersion: original.row.schemaVersion,
                contentHash: original.row.contentHash,
                syncStatus: .inTrash,
                trashedAt: trashDate
            ),
            canvases: original.canvases
        )

        let plan = try NotionManagedPageBuilder.plan(
            snapshot: snapshot,
            previewUploadIDs: [
                snapshot.canvases[0].canvasID: "11111111-1111-1111-1111-111111111111",
                snapshot.canvases[1].canvasID: "22222222-2222-2222-2222-222222222222"
            ],
            files: remoteFiles,
            syncedAt: DomainFixtures.fixedDate
        )
        let serializedChildren = try plan.children.map(jsonString).joined(separator: "\n")

        XCTAssertTrue(serializedChildren.contains("Status: In Trash"))
        XCTAssertTrue(serializedChildren.contains("Trash date: \(iso8601(trashDate))"))
    }

    private func jsonObject(_ value: NotionJSONValue) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func jsonString(_ value: NotionJSONValue) throws -> String {
        try XCTUnwrap(String(data: JSONEncoder().encode(value), encoding: .utf8))
    }

    private func richTextContent(_ value: [String: Any]) throws -> String {
        let richText = try XCTUnwrap(value["rich_text"] as? [[String: Any]])
        let text = try XCTUnwrap(richText.first?["text"] as? [String: String])
        return try XCTUnwrap(text["content"])
    }

    private func paragraphText(_ value: NotionJSONValue) throws -> [String] {
        let object = try jsonObject(value)
        guard let paragraph = object["paragraph"] as? [String: Any],
              let richText = paragraph["rich_text"] as? [[String: Any]] else {
            return []
        }
        return richText.compactMap { item in
            (item["text"] as? [String: String])?["content"]
        }
    }

    private func linkedURL(_ value: NotionJSONValue) throws -> String {
        let object = try jsonObject(value)
        let paragraph = try XCTUnwrap(object["paragraph"] as? [String: Any])
        let richText = try XCTUnwrap(paragraph["rich_text"] as? [[String: Any]])
        let text = try XCTUnwrap(richText.first?["text"] as? [String: Any])
        let link = try XCTUnwrap(text["link"] as? [String: String])
        return try XCTUnwrap(link["url"])
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private let remoteFiles = NotionNotebookRemoteFiles(
    nativeUploadID: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    pdfUploadID: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
)

private extension NotionNotebookSnapshot {
    static func fixture() -> NotionNotebookSnapshot {
        NotionNotebookSnapshot(
            row: NotionNotebookRow(
                name: "Project Atlas",
                folderPath: "Projects",
                folderID: "33333333-3333-3333-3333-333333333333",
                notebookID: "44444444-4444-4444-4444-444444444444",
                modifiedAt: DomainFixtures.fixedDate,
                canvasCount: 2,
                tags: ["work"],
                isFavorite: false,
                schemaVersion: DocumentSchemaVersion.current.rawValue,
                contentHash: String(repeating: "f", count: 64),
                syncStatus: .complete,
                trashedAt: nil
            ),
            canvases: [
                NotionCanvasSnapshot(
                    canvasID: "55555555-5555-5555-5555-555555555555",
                    title: "Opening",
                    paperType: .blankCream,
                    layerCount: 2,
                    typedText: ["First typed note"],
                    recognizedHandwriting: ["First handwriting"],
                    embeddedPDFText: ["Reference text"]
                ),
                NotionCanvasSnapshot(
                    canvasID: "66666666-6666-6666-6666-666666666666",
                    title: "Details",
                    paperType: .gridSmall,
                    layerCount: 1,
                    typedText: ["Second typed note"],
                    recognizedHandwriting: [],
                    embeddedPDFText: []
                )
            ]
        )
    }
}
