import XCTest
@testable import NoteNerds

final class NotionNotebookMappingBehaviorTests: XCTestCase {
    func testNotebookMapsToOneRowWithFolderAndLibraryMetadata() throws {
        let folder = Folder.fixture()
        let notebook = Notebook.notionFixture(parentFolderID: folder.id)
        let library = LibraryState(folders: [folder], notebooks: [notebook])

        let snapshot = try NotionNotebookMapper.snapshot(
            for: notebook,
            in: library,
            contentHash: String(repeating: "a", count: 64)
        )

        XCTAssertEqual(snapshot.row.name, "Project Atlas")
        XCTAssertEqual(snapshot.row.folderPath, "Projects")
        XCTAssertEqual(snapshot.row.folderID, folder.id.rawValue.uuidString.lowercased())
        XCTAssertEqual(snapshot.row.notebookID, notebook.id.rawValue.uuidString.lowercased())
        XCTAssertEqual(snapshot.row.modifiedAt, DomainFixtures.fixedDate.addingTimeInterval(120))
        XCTAssertEqual(snapshot.row.canvasCount, 2)
        XCTAssertEqual(snapshot.row.tags, ["planning", "work"])
        XCTAssertTrue(snapshot.row.isFavorite)
        XCTAssertEqual(snapshot.row.schemaVersion, DocumentSchemaVersion.current.rawValue)
        XCTAssertEqual(snapshot.row.contentHash, String(repeating: "a", count: 64))
        XCTAssertEqual(snapshot.row.syncStatus, .complete)
        XCTAssertNil(snapshot.row.trashedAt)
    }

    func testCanvasSectionsKeepCanvasAndObjectOrderWithSearchableText() throws {
        let notebook = Notebook.notionFixture()

        let snapshot = try NotionNotebookMapper.snapshot(
            for: notebook,
            in: LibraryState(notebooks: [notebook]),
            contentHash: String(repeating: "b", count: 64)
        )

        XCTAssertEqual(snapshot.canvases.map(\.title), ["Opening", "Details"])
        XCTAssertEqual(snapshot.canvases.map(\.canvasID), notebook.canvases.map {
            $0.id.rawValue.uuidString.lowercased()
        })
        XCTAssertEqual(snapshot.canvases[0].paperType, .blankCream)
        XCTAssertEqual(snapshot.canvases[0].layerCount, 2)
        XCTAssertEqual(snapshot.canvases[0].typedText, ["First typed note", "Second typed note"])
        XCTAssertEqual(snapshot.canvases[0].recognizedHandwriting, ["A handwritten idea"])
        XCTAssertEqual(snapshot.canvases[0].embeddedPDFText, ["Reference PDF text"])
        XCTAssertEqual(snapshot.canvases[1].typedText, ["Final note"])
    }

    func testRootAndTrashMapToExplicitNotionValues() throws {
        var notebook = Notebook.notionFixture()
        notebook.trashedAt = DomainFixtures.fixedDate.addingTimeInterval(300)

        let snapshot = try NotionNotebookMapper.snapshot(
            for: notebook,
            in: LibraryState(notebooks: [notebook]),
            contentHash: String(repeating: "c", count: 64)
        )

        XCTAssertEqual(snapshot.row.folderPath, "My Notebooks")
        XCTAssertEqual(snapshot.row.folderID, "")
        XCTAssertEqual(snapshot.row.syncStatus, .inTrash)
        XCTAssertEqual(snapshot.row.trashedAt, DomainFixtures.fixedDate.addingTimeInterval(300))
    }

    func testContentHashIsStableAndChangesWithContent() {
        let first = Data("same notebook".utf8)
        let second = Data("changed notebook".utf8)

        XCTAssertEqual(
            NotionContentHasher.sha256Hex(of: first),
            NotionContentHasher.sha256Hex(of: first)
        )
        XCTAssertEqual(NotionContentHasher.sha256Hex(of: first).count, 64)
        XCTAssertNotEqual(
            NotionContentHasher.sha256Hex(of: first),
            NotionContentHasher.sha256Hex(of: second)
        )
    }
}

private extension Folder {
    static func fixture() -> Folder {
        Folder(
            id: FolderID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
            name: "Projects",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
    }
}

private extension Notebook {
    // swiftlint:disable:next function_body_length
    static func notionFixture(parentFolderID: FolderID? = nil) -> Notebook {
        let firstCanvasID = CanvasID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let firstLayerID = LayerID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        let secondLayerID = LayerID(rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)
        let secondCanvasID = CanvasID(rawValue: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
        let thirdLayerID = LayerID(rawValue: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!)
        let firstText = TextBlock.fixture(text: "First typed note", layerID: firstLayerID, suffix: "01")
        let secondText = TextBlock.fixture(text: "Second typed note", layerID: secondLayerID, suffix: "02")
        let pdf = PDFObject(
            id: ObjectID(rawValue: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!),
            layerID: secondLayerID,
            assetID: AssetID(rawValue: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!),
            frame: CanvasRect(x: 20, y: 20, width: 200, height: 300),
            pageIndex: 0,
            embeddedText: "Reference PDF text"
        )
        let firstCanvas = Canvas(
            id: firstCanvasID,
            title: "Opening",
            template: .blankCream,
            layers: [
                Layer(id: firstLayerID, name: "Writing", objects: [.text(firstText)]),
                Layer(id: secondLayerID, name: "Sources", objects: [.text(secondText), .pdf(pdf)])
            ],
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let finalText = TextBlock.fixture(text: "Final note", layerID: thirdLayerID, suffix: "03")
        let secondCanvas = Canvas(
            id: secondCanvasID,
            title: "Details",
            template: .gridSmall,
            layers: [Layer(id: thirdLayerID, name: "Writing", objects: [.text(finalText)])],
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let recognition = HandwritingRecognitionResult(
            text: "A handwritten idea",
            confidence: 0.9,
            bounds: CanvasRect(x: 10, y: 10, width: 100, height: 40),
            sourceStrokeIDs: [],
            recognizerVersion: "test"
        )
        return Notebook(
            id: NotebookID(rawValue: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!),
            title: "Project Atlas",
            canvases: [firstCanvas, secondCanvas],
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate.addingTimeInterval(120),
            lastOpenedAt: DomainFixtures.fixedDate,
            isFavorite: true,
            tags: ["work", "planning"],
            parentFolderID: parentFolderID,
            recognitionByCanvas: [
                firstCanvasID: [PersistedHandwritingRecognition(result: recognition, sourceStrokes: [])]
            ]
        )
    }
}

private extension TextBlock {
    static func fixture(text: String, layerID: LayerID, suffix: String) -> TextBlock {
        TextBlock(
            id: ObjectID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA\(suffix)")!),
            layerID: layerID,
            text: text,
            frame: CanvasRect(x: 10, y: 10, width: 200, height: 40),
            fontSize: 20,
            alignment: .left
        )
    }
}
