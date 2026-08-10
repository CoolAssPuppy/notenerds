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

    func testAppleRecognizerReadsAsymmetricHandwritingRightSideUp() async throws {
        let layerID = LayerID()
        let strokes = handwrittenNoteStrokes(layerID: layerID)

        let result = try await AppleHandwritingRecognizer().recognize(strokes: strokes)
        let latinLetters = result.text.uppercased().filter { character in
            character >= "A" && character <= "Z"
        }

        XCTAssertEqual(latinLetters, "NOTE", "Expected right-side-up NOTE, recognized \(result.text)")
        XCTAssertEqual(result.sourceStrokeIDs, Set(strokes.map(\.id)))
        XCTAssertEqual(result.bounds, CanvasRect.enclosing(strokes.flatMap { $0.samples.map(\.point) }))
    }

    func testHighlighterAcrossHandwritingIsExcludedFromAppleRecognition() async throws {
        let layerID = LayerID()
        let writingStrokes = handwrittenNoteStrokes(layerID: layerID)
        var highlighter = handwritingStroke(
            points: [CanvasPoint(x: 0, y: 58), CanvasPoint(x: 375, y: 58)],
            layerID: layerID
        )
        highlighter.style = StrokeStyle(
            instrument: .highlighter,
            width: 28,
            color: InkColor(red: 1, green: 0.8, blue: 0, alpha: 0.35)
        )
        let recognitionStrokes = (writingStrokes + [highlighter])
            .filter(\.isHandwritingRecognitionCandidate)

        let result = try await AppleHandwritingRecognizer().recognize(strokes: recognitionStrokes)
        let recognizedLetters = result.text
            .uppercased()
            .filter { character in character >= "A" && character <= "Z" }

        XCTAssertEqual(recognizedLetters, "NOTE")
        XCTAssertEqual(result.sourceStrokeIDs, Set(writingStrokes.map(\.id)))
        XCTAssertFalse(result.sourceStrokeIDs.contains(highlighter.id))
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
    func testCompletedHandwritingBecomesAHandwritingSearchResult() async throws {
        let layer = Layer(name: "Notes")
        let canvas = Canvas(title: "Canvas 1", layers: [layer])
        let notebook = Notebook(title: "Meeting notebook", canvases: [canvas])
        let strokes = capitalFStrokes(layerID: layer.id)
        let phrase = "Quarterly agenda"
        let recognition = HandwritingRecognitionResult(
            text: phrase,
            confidence: 0.95,
            bounds: CanvasRect.enclosing(strokes.flatMap { $0.samples.map(\.point) }),
            sourceStrokeIDs: Set(strokes.map(\.id)),
            recognizerVersion: "test"
        )
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: StubRecognizer(result: recognition)
            ),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        model.searchQuery = "quarterly"

        _ = model.addStrokes(strokes, to: notebook.id, canvasID: canvas.id, layerID: layer.id)
        let result = try await waitForHandwritingResult(in: model, matching: phrase)

        XCTAssertEqual(result.matchType, .handwriting)
        XCTAssertEqual(result.notebookID, notebook.id)
        XCTAssertEqual(result.canvasID, canvas.id)
        XCTAssertEqual(result.bounds, recognition.bounds)
        XCTAssertEqual(result.sourceStrokeIDs, recognition.sourceStrokeIDs)
        XCTAssertEqual(
            model.notebook(notebook.id)?.canvases[0].layers[0].objects.compactMap(\.strokeValue),
            strokes
        )
    }

    @MainActor
    func testRecognitionCompletionPreservesEditsMadeWhileRecognitionRuns() async throws {
        let layer = Layer(name: "Notes")
        let canvas = Canvas(title: "Canvas 1", layers: [layer])
        let notebook = Notebook(title: "Concurrent edits", canvases: [canvas])
        let strokes = capitalFStrokes(layerID: layer.id)
        let phrase = "Recognized after edit"
        let recognition = HandwritingRecognitionResult(
            text: phrase,
            confidence: 0.95,
            bounds: CanvasRect.enclosing(strokes.flatMap { $0.samples.map(\.point) }),
            sourceStrokeIDs: Set(strokes.map(\.id)),
            recognizerVersion: "test"
        )
        let recognizer = PausingHandwritingRecognizer(result: recognition)
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(recognizer: recognizer),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        model.searchQuery = "recognized"
        _ = model.addStrokes(strokes, to: notebook.id, canvasID: canvas.id, layerID: layer.id)
        await recognizer.waitUntilPaused()
        model.addTextBlock(
            TextBlockInsertion(
                text: "Added during recognition",
                fontSize: 18,
                alignment: .left,
                fontName: nil,
                frame: CanvasRect(x: 140, y: 140, width: 260, height: 44),
                layerID: layer.id,
                canvasID: canvas.id
            ),
            notebookID: notebook.id
        )

        await recognizer.finish()
        _ = try await waitForHandwritingResult(in: model, matching: phrase)

        let objects = try XCTUnwrap(model.notebook(notebook.id)?.canvases[0].layers[0].objects)
        XCTAssertTrue(objects.contains { object in
            guard case let .text(text) = object else { return false }
            return text.text == "Added during recognition"
        })
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

    private func capitalFStrokes(layerID: LayerID) -> [Stroke] {
        [
            handwritingStroke(
                points: [CanvasPoint(x: 10, y: 10), CanvasPoint(x: 10, y: 110)],
                layerID: layerID
            ),
            handwritingStroke(
                points: [CanvasPoint(x: 10, y: 10), CanvasPoint(x: 75, y: 10)],
                layerID: layerID
            ),
            handwritingStroke(
                points: [CanvasPoint(x: 10, y: 55), CanvasPoint(x: 60, y: 55)],
                layerID: layerID
            )
        ]
    }

    private func handwrittenNoteStrokes(layerID: LayerID) -> [Stroke] {
        let lines: [[CanvasPoint]] = [
            [CanvasPoint(x: 10, y: 110), CanvasPoint(x: 10, y: 10)],
            [CanvasPoint(x: 10, y: 10), CanvasPoint(x: 70, y: 110)],
            [CanvasPoint(x: 70, y: 110), CanvasPoint(x: 70, y: 10)],
            [
                CanvasPoint(x: 100, y: 25), CanvasPoint(x: 110, y: 10),
                CanvasPoint(x: 140, y: 5), CanvasPoint(x: 165, y: 15),
                CanvasPoint(x: 175, y: 45), CanvasPoint(x: 175, y: 80),
                CanvasPoint(x: 160, y: 105), CanvasPoint(x: 130, y: 112),
                CanvasPoint(x: 105, y: 100), CanvasPoint(x: 95, y: 70),
                CanvasPoint(x: 95, y: 40), CanvasPoint(x: 100, y: 25)
            ],
            [CanvasPoint(x: 200, y: 10), CanvasPoint(x: 270, y: 10)],
            [CanvasPoint(x: 235, y: 10), CanvasPoint(x: 235, y: 110)],
            [CanvasPoint(x: 300, y: 10), CanvasPoint(x: 300, y: 110)],
            [CanvasPoint(x: 300, y: 10), CanvasPoint(x: 365, y: 10)],
            [CanvasPoint(x: 300, y: 58), CanvasPoint(x: 350, y: 58)],
            [CanvasPoint(x: 300, y: 110), CanvasPoint(x: 365, y: 110)]
        ]
        return lines.map { handwritingStroke(points: $0, layerID: layerID) }
    }

    private func handwritingStroke(points: [CanvasPoint], layerID: LayerID) -> Stroke {
        Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: points.enumerated().map { index, point in
                StrokeSample(
                    point: point,
                    pressure: 0.6,
                    altitude: 0.8,
                    azimuth: 0,
                    roll: 0,
                    timeOffset: Double(index) * 0.1
                )
            },
            style: StrokeStyle(instrument: .ballpoint, width: 7, color: .black),
            createdAt: DomainFixtures.fixedDate
        )
    }

    @MainActor
    private func waitForHandwritingResult(
        in model: AppModel,
        matching phrase: String
    ) async throws -> LibrarySearchResult {
        for _ in 0..<100 {
            if let result = model.searchResults.first(where: { result in
                result.matchType == .handwriting && result.snippet == phrase
            }) {
                return result
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try XCTUnwrap(model.searchResults.first { $0.matchType == .handwriting })
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

private actor PausingHandwritingRecognizer: HandwritingRecognizer {
    let result: HandwritingRecognitionResult
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(result: HandwritingRecognitionResult) {
        self.result = result
    }

    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        if !isPaused {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                isPaused = true
                pauseWaiters.forEach { $0.resume() }
                pauseWaiters.removeAll()
            }
        }
        return result
    }

    func waitUntilPaused() async {
        guard !isPaused else { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
