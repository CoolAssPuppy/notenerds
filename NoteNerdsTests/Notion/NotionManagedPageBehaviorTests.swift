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
            ]
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
        XCTAssertTrue(serializedChildren.contains("11111111-1111-1111-1111-111111111111"))
        XCTAssertTrue(serializedChildren.contains("22222222-2222-2222-2222-222222222222"))
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
            previewUploadIDs: [snapshot.canvases[0].canvasID: "11111111-1111-1111-1111-111111111111"]
        )
        let textChunks = try plan.children.flatMap(paragraphText)

        XCTAssertTrue(textChunks.allSatisfy { $0.count <= 2_000 })
        XCTAssertEqual(textChunks.filter { $0.first == "a" }.map(\.count), [2_000, 2_000, 1])
    }

    func testManagedPageRequiresAPreviewForEveryCanvas() {
        let snapshot = NotionNotebookSnapshot.fixture()

        XCTAssertThrowsError(
            try NotionManagedPageBuilder.plan(snapshot: snapshot, previewUploadIDs: [:])
        ) { error in
            XCTAssertEqual(
                error as? NotionManagedPageError,
                .missingPreview(snapshot.canvases[0].canvasID)
            )
        }
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
}

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
                schemaVersion: 4,
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
