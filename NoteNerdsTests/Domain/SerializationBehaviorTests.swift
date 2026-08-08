import XCTest
@testable import NoteNerds

final class SerializationBehaviorTests: XCTestCase {
    func testNativeDocumentRoundTripPreservesCanonicalContent() throws {
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook())
        let serializer = NativeDocumentSerializer()

        let encoded = try serializer.encode(package)
        let decoded = try serializer.decode(encoded)

        XCTAssertEqual(decoded, package)
    }

    func testSerializationIsDeterministic() throws {
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook())
        let serializer = NativeDocumentSerializer()

        XCTAssertEqual(try serializer.encode(package), try serializer.encode(package))
    }

    func testNativeDocumentPreservesTheSelectedSystemFont() throws {
        var notebook = DomainFixtures.notebook()
        let text = TextBlock(
            id: ObjectID(),
            layerID: notebook.canvases[0].layers[0].id,
            text: "Set in Avenir Next",
            frame: CanvasRect(x: 100, y: 200, width: 360, height: 44),
            fontSize: 22,
            alignment: .left,
            fontName: "AvenirNext-Regular"
        )
        notebook.canvases[0].layers[0].objects = [.text(text)]
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: notebook)

        let decoded = try NativeDocumentSerializer().decode(NativeDocumentSerializer().encode(package))

        guard case let .text(decodedText) = decoded.notebook.canvases[0].layers[0].objects[0] else {
            return XCTFail("Expected a text block")
        }
        XCTAssertEqual(decodedText.fontName, text.fontName)
    }

    func testNewerSchemaVersionIsRejectedWithoutDiscardingInput() throws {
        let serializer = NativeDocumentSerializer()
        let newerDocument = Data("{\"schemaVersion\":999,\"notebook\":{}}".utf8)

        XCTAssertThrowsError(try serializer.decode(newerDocument)) { error in
            XCTAssertEqual(error as? NativeDocumentError, .unsupportedNewerVersion(999))
        }
        XCTAssertEqual(String(data: newerDocument, encoding: .utf8), "{\"schemaVersion\":999,\"notebook\":{}}")
    }

    func testOlderSchemaIsMigratedToCurrentVersion() throws {
        let package = NativeNotebookPackage(
            schemaVersion: DocumentSchemaVersion(rawValue: 1),
            notebook: DomainFixtures.notebook()
        )
        let data = try NativeDocumentSerializer().encode(package)

        let migrated = try NativeDocumentSerializer().decode(data)

        XCTAssertEqual(migrated.schemaVersion, .current)
        XCTAssertEqual(migrated.notebook, package.notebook)
    }

    func testLegacyCanvasTemplatesDecodeAsSupportedPaperTypes() throws {
        let mappings: [(String, PaperType)] = [
            ("blank", .blankCream),
            ("grid", .gridSmall),
            ("dotGrid", .dotSmall),
            ("ruled", .whiteLegalPad),
            ("narrowRuled", .whiteLegalPad),
            ("checklist", .whiteLegalPad)
        ]

        for (legacyValue, expectedPaperType) in mappings {
            let decoded = try JSONDecoder().decode(PaperType.self, from: Data("\"\(legacyValue)\"".utf8))
            XCTAssertEqual(decoded, expectedPaperType)
        }
    }
}
