import XCTest
@testable import NoteNerds

final class CanvasRedrawDecisionBehaviorTests: XCTestCase {
    func testAnUnchangedPageDoesNotRedraw() {
        let strokes = [DomainFixtures.stroke(id: StrokeID()), DomainFixtures.stroke(id: StrokeID())]

        XCTAssertFalse(
            PencilCanvasModelReconciliation.requiresRedraw(current: strokes, incoming: strokes)
        )
    }

    func testEditingAStrokeRedraws() {
        let original = DomainFixtures.stroke(id: StrokeID())
        var edited = original
        edited.samples = Array(original.samples.prefix(1))

        XCTAssertTrue(
            PencilCanvasModelReconciliation.requiresRedraw(current: [original], incoming: [edited])
        )
    }

    func testChangingOnlyTheStyleRedraws() {
        let original = DomainFixtures.stroke(id: StrokeID())
        var recoloured = original
        recoloured.style = StrokeStyle(
            instrument: .highlighter,
            width: 12,
            color: InkColor(red: 1, green: 0.9, blue: 0.1, alpha: 0.4)
        )

        XCTAssertTrue(
            PencilCanvasModelReconciliation.requiresRedraw(current: [original], incoming: [recoloured])
        )
    }

    func testMovingAStrokeToAnotherLayerRedraws() {
        let original = DomainFixtures.stroke(id: StrokeID())
        var moved = original
        moved.layerID = LayerID()

        XCTAssertTrue(
            PencilCanvasModelReconciliation.requiresRedraw(current: [original], incoming: [moved])
        )
    }

    func testAddingAndRemovingStrokesRedraws() {
        let first = DomainFixtures.stroke(id: StrokeID())
        let second = DomainFixtures.stroke(id: StrokeID())

        XCTAssertTrue(
            PencilCanvasModelReconciliation.requiresRedraw(current: [first], incoming: [first, second])
        )
        XCTAssertTrue(
            PencilCanvasModelReconciliation.requiresRedraw(current: [first, second], incoming: [first])
        )
    }

    func testReorderingStrokesRedraws() {
        let first = DomainFixtures.stroke(id: StrokeID())
        let second = DomainFixtures.stroke(id: StrokeID())

        XCTAssertTrue(
            PencilCanvasModelReconciliation.requiresRedraw(
                current: [first, second],
                incoming: [second, first]
            )
        )
    }

    func testALivePencilContactNeverRedraws() {
        let original = DomainFixtures.stroke(id: StrokeID())
        var edited = original
        edited.samples = Array(original.samples.prefix(1))

        XCTAssertFalse(
            PencilCanvasModelReconciliation.requiresRedraw(
                current: [original],
                incoming: [edited],
                isUsingTool: true
            )
        )
    }

    func testTheStoredFormatIgnoresTheRenderedContentIdentifier() throws {
        let original = DomainFixtures.stroke(id: StrokeID())
        var reordered = original
        reordered.samples = original.samples

        XCTAssertNotEqual(original.renderedContentID, reordered.renderedContentID)
        XCTAssertEqual(original, reordered)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Stroke.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }
}
