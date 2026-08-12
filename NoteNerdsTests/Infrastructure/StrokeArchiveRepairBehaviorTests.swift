import PencilKit
import XCTest
@testable import NoteNerds

/// Guards the one-time repair of stroke archives written by older builds.
///
/// The repair walks every sample of every stroke. Running it on every load cost
/// 470ms of launch across three notebooks on an iPad, so it has to stay gated on
/// the version the note was written with.
@MainActor
final class StrokeArchiveRepairBehaviorTests: XCTestCase {
    func testANoteWrittenByAnOlderBuildHasItsStaleArchiveCleared() throws {
        var package = makePackage(schemaVersion: DocumentSchemaVersion(rawValue: 6))
        package.notebook.canvases[0].layers[0].objects = [.stroke(staleArchivedStroke())]

        package.repairStrokeArchivesIfWrittenBeforeSelfInvalidation(
            storedVersion: DocumentSchemaVersion(rawValue: 6)
        )

        XCTAssertNil(firstStroke(in: package)?.pencilKitArchive)
    }

    func testANoteWrittenByAnOlderBuildKeepsAnArchiveThatStillMatches() throws {
        let stroke = archivedStroke()
        var package = makePackage(schemaVersion: DocumentSchemaVersion(rawValue: 6))
        package.notebook.canvases[0].layers[0].objects = [.stroke(stroke)]

        package.repairStrokeArchivesIfWrittenBeforeSelfInvalidation(
            storedVersion: DocumentSchemaVersion(rawValue: 6)
        )

        XCTAssertEqual(firstStroke(in: package)?.pencilKitArchive, stroke.pencilKitArchive)
    }

    func testACurrentNoteIsNotWalkedAtAll() throws {
        var package = makePackage(schemaVersion: .current)
        package.notebook.canvases[0].layers[0].objects = [.stroke(staleArchivedStroke())]

        package.repairStrokeArchivesIfWrittenBeforeSelfInvalidation(storedVersion: .current)

        XCTAssertNotNil(
            firstStroke(in: package)?.pencilKitArchive,
            "A note already at the current version must not be re-checked on load"
        )
    }

    func testChangingAStrokeDropsItsArchiveWithoutAnyRepairPass() {
        var stroke = archivedStroke()
        XCTAssertNotNil(stroke.pencilKitArchive)

        stroke.samples = Array(stroke.samples.prefix(2))

        XCTAssertNil(stroke.pencilKitArchive)
    }

    func testChangingAStrokeStyleDropsItsArchive() {
        var stroke = archivedStroke()

        stroke.style = StrokeStyle(instrument: .marker, width: 9, color: .black)

        XCTAssertNil(stroke.pencilKitArchive)
    }

    func testStrokeStoredFieldsCannotDriftFromItsManualConformances() throws {
        let stroke = archivedStroke()
        let storedFieldNames = Set(Mirror(reflecting: stroke).children.compactMap(\.label))
        XCTAssertEqual(
            storedFieldNames,
            ["id", "layerID", "samples", "style", "createdAt", "pencilKitArchive", "renderedContentID"]
        )

        let encoded = try JSONEncoder().encode(stroke)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["id", "layerID", "samples", "style", "createdAt", "pencilKitArchive"]
        )
        XCTAssertEqual(try JSONDecoder().decode(Stroke.self, from: encoded), stroke)
    }

    func testEveryStoredStrokeFieldParticipatesInEquality() {
        let original = archivedStroke()
        var changedLayer = original
        changedLayer.layerID = LayerID()
        var changedSamples = original
        changedSamples.samples[0].point.x += 1
        var changedStyle = original
        changedStyle.style.width += 1
        var changedArchive = original
        changedArchive.pencilKitArchive = nil
        let changedID = Stroke(
            id: StrokeID(),
            layerID: original.layerID,
            samples: original.samples,
            style: original.style,
            createdAt: original.createdAt,
            pencilKitArchive: original.pencilKitArchive
        )
        let changedDate = Stroke(
            id: original.id,
            layerID: original.layerID,
            samples: original.samples,
            style: original.style,
            createdAt: original.createdAt.addingTimeInterval(1),
            pencilKitArchive: original.pencilKitArchive
        )

        for changed in [changedID, changedLayer, changedSamples, changedStyle, changedDate, changedArchive] {
            XCTAssertNotEqual(changed, original)
            XCTAssertEqual(Set([original, changed]).count, 2)
        }
    }

    func testClosingANotebookReleasesItsDecodedPencilPaths() {
        let cache = PencilStrokeArchiveCache.shared
        cache.removeAll()
        let stroke = archivedStroke()
        _ = cache.stroke(for: stroke)
        XCTAssertTrue(cache.contains(stroke))
        var notebook = DomainFixtures.notebook(title: "Cached notebook")
        notebook.canvases[0].layers[0].objects = [.stroke(stroke)]
        let model = AppModel(automaticallyRestore: false)
        model.library = LibraryState(notebooks: [notebook])
        model.selectedNotebookID = notebook.id

        model.closeNotebook()

        XCTAssertFalse(cache.contains(stroke))
    }

    private func makePackage(schemaVersion: DocumentSchemaVersion) -> NativeNotebookPackage {
        NativeNotebookPackage(
            schemaVersion: schemaVersion,
            notebook: DomainFixtures.notebook(title: "Archive repair")
        )
    }

    private func firstStroke(in package: NativeNotebookPackage) -> Stroke? {
        package.notebook.canvases[0].layers[0].objects.compactMap(\.strokeValue).first
    }

    /// A stroke whose archive genuinely renders its samples.
    private func archivedStroke() -> Stroke {
        PencilKitStrokeArchiveCodec.preserving(
            PencilStrokeTestFixture.blackPenStroke(randomSeed: 7),
            in: DomainFixtures.stroke(id: StrokeID())
        )
    }

    /// A stroke carrying an archive that no longer describes it, the shape an
    /// older build could leave behind by transforming samples in place.
    private func staleArchivedStroke() -> Stroke {
        var stroke = archivedStroke()
        let archive = stroke.pencilKitArchive
        stroke.samples = Array(stroke.samples.prefix(1))
        stroke.pencilKitArchive = archive
        return stroke
    }
}
