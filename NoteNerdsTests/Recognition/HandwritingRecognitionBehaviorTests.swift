import XCTest
@testable import NoteNerds

final class HandwritingRecognitionBehaviorTests: XCTestCase {
    func testAppleRecognizerRejectsAnEmptyStrokeGroup() async {
        let recognizer = AppleHandwritingRecognizer()

        do {
            _ = try await recognizer.recognize(strokes: [])
            XCTFail("Expected empty handwriting to be rejected")
        } catch {
            XCTAssertEqual(error as? AppleHandwritingRecognitionError, .emptyInput)
        }
    }

    func testLowConfidenceRecognitionLeavesInkUnchanged() async {
        let stroke = DomainFixtures.stroke()
        let recognizer = StubRecognizer(result: HandwritingRecognitionResult(
            text: "uncertain",
            confidence: 0.2,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "test"
        ))
        let coordinator = HandwritingRecognitionCoordinator(recognizer: recognizer, minimumConfidence: 0.5)

        let result = await coordinator.recognizeSafely(strokes: [stroke])

        XCTAssertNil(result)
    }

    func testRecognitionFailureLeavesInkUnchanged() async {
        let coordinator = HandwritingRecognitionCoordinator(
            recognizer: FailingRecognizer(),
            minimumConfidence: 0.5
        )

        let result = await coordinator.recognizeSafely(strokes: [DomainFixtures.stroke()])

        XCTAssertNil(result)
    }

    func testNearbyStrokesFormOneWritingGroupAndDistantLineStartsAnother() {
        let layerID = LayerID()
        let first = DomainFixtures.stroke(layerID: layerID)
        var nearby = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        nearby.samples = nearby.samples.map { sample in
            var moved = sample
            moved.point.x += 35
            return moved
        }
        var distant = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        distant.samples = distant.samples.map { sample in
            var moved = sample
            moved.point.y += 180
            return moved
        }

        let groups = HandwritingGroupBuilder().groups(from: [first, nearby, distant])

        XCTAssertEqual(groups.map(\.count), [2, 1])
    }

    func testPersistedRecognitionBecomesStaleWhenSourceGeometryChanges() {
        let stroke = DomainFixtures.stroke()
        let result = HandwritingRecognitionResult(
            text: "hello",
            confidence: 0.9,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "Vision-1"
        )
        let record = PersistedHandwritingRecognition(result: result, sourceStrokes: [stroke])
        var changed = stroke
        changed.samples[0].point.x += 1

        XCTAssertFalse(record.isStale(sourceStrokes: [stroke], recognizerVersion: "Vision-1"))
        XCTAssertTrue(record.isStale(sourceStrokes: [changed], recognizerVersion: "Vision-1"))
        XCTAssertTrue(record.isStale(sourceStrokes: [stroke], recognizerVersion: "Vision-2"))
    }

    @MainActor
    func testWritingModeWaitsForPauseBeforeConvertingTheGroup() async throws {
        let notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        let result = HandwritingRecognitionResult(
            text: "Grouped text",
            confidence: 0.9,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "test"
        )
        let repositoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "library.json")
        let model = AppModel(
            repository: LocalLibraryRepository(fileURL: repositoryURL),
            recognitionCoordinator: HandwritingRecognitionCoordinator(recognizer: StubRecognizer(result: result)),
            conversionDelay: .milliseconds(20),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])

        _ = model.addStrokes(
            [stroke],
            to: notebook.id,
            canvasID: canvas.id,
            layerID: layer.id,
            shouldConvertToText: true
        )
        XCTAssertTrue(model.notebook(notebook.id)?.canvases[0].layers[0].objects.contains(.stroke(stroke)) == true)

        try await Task.sleep(for: .milliseconds(100))

        let objects = try XCTUnwrap(model.notebook(notebook.id)?.canvases[0].layers[0].objects)
        XCTAssertFalse(objects.contains(.stroke(stroke)))
        XCTAssertTrue(objects.contains { if case .text = $0 { true } else { false } })
    }
}

private struct StubRecognizer: HandwritingRecognizer {
    let result: HandwritingRecognitionResult

    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult { result }
}

private struct FailingRecognizer: HandwritingRecognizer {
    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        throw CocoaError(.coderReadCorrupt)
    }
}
