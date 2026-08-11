import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class PencilCanvasInputBehaviorTests: XCTestCase {
    func testModelRefreshWaitsUntilPencilLift() {
        let current = stroke(sampleCount: 4, xOffset: 0)
        let incoming = stroke(sampleCount: 4, xOffset: 200)

        XCTAssertFalse(
            PencilCanvasModelReconciliation.requiresRedraw(
                current: [current],
                incoming: [incoming],
                isUsingTool: true
            )
        )
        XCTAssertTrue(
            PencilCanvasModelReconciliation.requiresRedraw(
                current: [current],
                incoming: [incoming],
                isUsingTool: false
            )
        )
    }

    func testRepeatedPartialUpdatesPublishOneCompleteStrokeAfterPencilLift() async {
        let completeStroke = stroke(sampleCount: 12, xOffset: 0)
        let canvasView = PKCanvasView()
        var publishedStrokes: [[Stroke]] = []
        let published = expectation(description: "Complete stroke published")
        let coordinator = PencilStrokeTestFixture.coordinator {
            publishedStrokes.append($0)
            published.fulfill()
        }

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        for sampleCount in 1...completeStroke.samples.count {
            var partialStroke = completeStroke
            partialStroke.samples = Array(completeStroke.samples.prefix(sampleCount))
            canvasView.drawing = PencilCanvasRenderer.drawing(from: [partialStroke])
            coordinator.canvasViewDrawingDidChange(canvasView)
        }

        XCTAssertTrue(publishedStrokes.isEmpty)

        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(publishedStrokes.count, 1)
        XCTAssertEqual(publishedStrokes[0].count, 1)
        XCTAssertEqual(publishedStrokes[0][0].samples.count, completeStroke.samples.count)
        XCTAssertEqual(publishedStrokes[0][0].samples.map(\.point), completeStroke.samples.map(\.point))
    }

    func testPencilKitFinalUpdatePublishesOnceAfterToolUseEnds() async {
        let completeStroke = stroke(sampleCount: 12, xOffset: 0)
        var partialStroke = completeStroke
        partialStroke.samples = Array(completeStroke.samples.prefix(5))
        let canvasView = PKCanvasView()
        var publishedStrokes: [[Stroke]] = []
        let published = expectation(description: "Final PencilKit drawing published")
        let coordinator = PencilStrokeTestFixture.coordinator { strokes in
            publishedStrokes.append(strokes)
            published.fulfill()
        }

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [partialStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        XCTAssertTrue(publishedStrokes.isEmpty)

        canvasView.drawing = PencilCanvasRenderer.drawing(from: [completeStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)

        XCTAssertTrue(publishedStrokes.isEmpty)
        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(publishedStrokes.count, 1)
        XCTAssertEqual(publishedStrokes[0][0].samples.count, completeStroke.samples.count)
        XCTAssertEqual(publishedStrokes[0][0].samples.map(\.point), completeStroke.samples.map(\.point))
    }

    func testLatePencilKitPressureUpdateRevisesTheSavedStrokeWithoutDuplication() async {
        let partialStroke = PencilStrokeTestFixture.pencilStroke(
            color: .black,
            size: CGSize(width: 3, height: 3),
            opacity: 1,
            randomSeed: 41
        )
        let intermediateStroke = PencilStrokeTestFixture.pencilStroke(
            color: .black,
            size: CGSize(width: 3, height: 3),
            opacity: 1,
            randomSeed: 41,
            forceOffset: 0.2
        )
        let finalStroke = PencilStrokeTestFixture.pencilStroke(
            color: .black,
            size: CGSize(width: 3, height: 3),
            opacity: 1,
            randomSeed: 41,
            forceOffset: 0.4
        )
        let canvasView = PKCanvasView()
        var completedStrokes: [Stroke] = []
        var revisedStrokes: [Stroke] = []
        let revised = expectation(description: "Final pressure saved")
        let coordinator = PencilStrokeTestFixture.coordinator(
            onStrokesCompleted: { completedStrokes = $0 },
            onDrawingChanged: {
                revisedStrokes = $0
                revised.fulfill()
            }
        )

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [partialStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        try? await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(completedStrokes.count, 1)
        let originalID = completedStrokes[0].id

        canvasView.drawing = PKDrawing(strokes: [intermediateStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        canvasView.drawing = PKDrawing(strokes: [finalStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        await fulfillment(of: [revised], timeout: 1)

        XCTAssertEqual(revisedStrokes.count, 1)
        XCTAssertEqual(revisedStrokes[0].id, originalID)
        let publishedPressure = revisedStrokes[0].samples.map(\.pressure)
        let finalPressure = finalStroke.path.map { Double($0.force) }
        XCTAssertEqual(publishedPressure, finalPressure)
    }

    func testFinalDrawingChangeBeforeToolUseEndsStillPublishesTheStroke() async {
        let completeStroke = stroke(sampleCount: 12, xOffset: 0)
        let canvasView = PKCanvasView()
        let published = expectation(description: "Stroke published without another drawing change")
        var publishedStrokes: [Stroke] = []
        let coordinator = PencilStrokeTestFixture.coordinator {
            publishedStrokes = $0
            published.fulfill()
        }

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [completeStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(publishedStrokes.count, 1)
        XCTAssertEqual(publishedStrokes[0].samples.map(\.point), completeStroke.samples.map(\.point))
    }

    func testPendingStrokePublishesWhenTheCanvasIsRemoved() async throws {
        let published = expectation(description: "Pending stroke published after canvas removal")
        var publishedStrokes: [Stroke] = []
        let coordinator = PencilStrokeTestFixture.coordinator {
            publishedStrokes = $0
            published.fulfill()
        }
        let finalStroke = stroke(sampleCount: 12, xOffset: 0)
        weak var removedCanvasView: PKCanvasView?
        autoreleasepool {
            let canvasView = PKCanvasView()
            removedCanvasView = canvasView
            coordinator.canvasViewDidBeginUsingTool(canvasView)
            canvasView.drawing = PencilCanvasRenderer.drawing(from: [finalStroke])
            coordinator.canvasViewDrawingDidChange(canvasView)
            coordinator.canvasViewDidEndUsingTool(canvasView)
            PencilCanvasView.dismantleUIView(canvasView, coordinator: coordinator)
        }

        XCTAssertNil(removedCanvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(publishedStrokes.count, 1)
        XCTAssertEqual(publishedStrokes[0].samples.map(\.point), finalStroke.samples.map(\.point))
    }

    func testDismantledCanvasSavesPendingInkOnlyToItsOriginalCanvasAfterSelectionChanges() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let originalCanvas = Canvas(title: "Original canvas")
        let selectedCanvas = Canvas(title: "Selected canvas")
        let notebook = Notebook(title: "Canvas switch", canvases: [originalCanvas, selectedCanvas])
        let lastViewedCanvasKey = "lastViewedCanvasID.\(notebook.id.rawValue.uuidString.lowercased())"
        let priorLastViewedCanvasID = UserDefaults.standard.string(forKey: lastViewedCanvasKey)
        defer {
            UserDefaults.standard.set(priorLastViewedCanvasID, forKey: lastViewedCanvasKey)
        }
        UserDefaults.standard.set(
            originalCanvas.id.rawValue.uuidString.lowercased(),
            forKey: lastViewedCanvasKey
        )
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let firstSession = await PencilStrokeTestFixture.restoredModel(
            repository: repository,
            documentStore: documentStore
        )
        let snapshotFlusher = dismantleCanvasWithPendingInk(
            model: firstSession,
            notebook: notebook,
            canvas: originalCanvas
        )
        UserDefaults.standard.set(
            selectedCanvas.id.rawValue.uuidString.lowercased(),
            forKey: lastViewedCanvasKey
        )
        let selectedEditor = NotebookEditorView(model: firstSession, notebook: notebook)
        XCTAssertEqual(selectedEditor.currentCanvas.id, selectedCanvas.id)

        await snapshotFlusher.flushPendingSnapshots()
        await firstSession.checkpointDocuments()
        let restoredNotebook = await PencilStrokeTestFixture.restoredNotebook(
            notebook.id,
            repository: repository,
            documentStore: documentStore
        )
        let reopened = try XCTUnwrap(restoredNotebook)
        let originalStrokes = reopened.canvases[0].layers[0].objects.compactMap(\.strokeValue)
        let selectedStrokes = reopened.canvases[1].layers[0].objects.compactMap(\.strokeValue)
        XCTAssertEqual(originalStrokes.count, 1)
        XCTAssertEqual(PencilKitStrokeArchiveCodec.randomSeed(for: originalStrokes[0]), 811)
        XCTAssertTrue(selectedStrokes.isEmpty)
    }

    func testModelRefreshDuringPencilContactDoesNotReplaceTheNativeDrawing() async {
        let existingStroke = stroke(sampleCount: 8, xOffset: 0)
        let remoteStroke = stroke(sampleCount: 6, xOffset: 100)
        let localStroke = stroke(sampleCount: 12, xOffset: 200)
        let canvasView = PKCanvasView()
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [existingStroke])
        var publishedStrokes: [[Stroke]] = []
        let published = expectation(description: "Local stroke published")
        let coordinator = PencilStrokeTestFixture.coordinator {
            publishedStrokes.append($0)
            published.fulfill()
        }
        coordinator.knownStrokeCount = 1
        coordinator.canonicalStrokes = [existingStroke]

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [existingStroke, localStroke])
        coordinator.receiveModelStrokes([existingStroke, remoteStroke])

        XCTAssertEqual(coordinator.canonicalStrokes, [existingStroke])

        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(publishedStrokes.count, 1)
        XCTAssertEqual(publishedStrokes[0].count, 1)
        XCTAssertEqual(publishedStrokes[0][0].samples.map(\.point), localStroke.samples.map(\.point))
        XCTAssertEqual(
            coordinator.canonicalStrokes.map(\.id),
            [existingStroke.id, publishedStrokes[0][0].id]
        )
        XCTAssertEqual(canvasView.drawing.strokes.count, 2)
    }

    func testModelReturningToTheCurrentDrawingClearsAnOlderDeferredRefresh() async {
        let currentStroke = stroke(sampleCount: 8, xOffset: 0)
        let staleStroke = stroke(sampleCount: 6, xOffset: 100)
        let currentDrawing = PencilCanvasRenderer.drawing(from: [currentStroke])
        let canvasView = PKCanvasView()
        canvasView.drawing = currentDrawing
        let coordinator = PencilStrokeTestFixture.coordinator { _ in }
        coordinator.knownStrokeCount = 1
        coordinator.canonicalStrokes = [currentStroke]

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        coordinator.receiveModelStrokes([staleStroke])
        coordinator.receiveModelStrokes([currentStroke])
        coordinator.canvasViewDidEndUsingTool(canvasView)
        try? await Task.sleep(for: .milliseconds(170))

        XCTAssertEqual(coordinator.canonicalStrokes.map(\.id), [currentStroke.id])
        XCTAssertEqual(canvasView.drawing, currentDrawing)
    }

    func testModelRefreshDuringEraseLeavesTheNativeResultUntouched() async {
        let existingStroke = stroke(sampleCount: 8, xOffset: 0)
        let remoteStroke = stroke(sampleCount: 6, xOffset: 100)
        let canvasView = PKCanvasView()
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [existingStroke])
        var changedStrokes: [[Stroke]] = []
        let published = expectation(description: "Erase published")
        let coordinator = PencilStrokeTestFixture.coordinator(
            onStrokesCompleted: { _ in },
            onDrawingChanged: {
                changedStrokes.append($0)
                published.fulfill()
            }
        )
        coordinator.knownStrokeCount = 1
        coordinator.canonicalStrokes = [existingStroke]

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing()
        coordinator.receiveModelStrokes([existingStroke, remoteStroke])
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(changedStrokes, [[]])
        XCTAssertTrue(coordinator.canonicalStrokes.isEmpty)
        XCTAssertTrue(canvasView.drawing.strokes.isEmpty)
    }

    func testRapidConsecutiveStrokesCoalesceIntoOneCompleteUpdate() async {
        let firstStroke = stroke(sampleCount: 8, xOffset: 0)
        let secondStroke = stroke(sampleCount: 10, xOffset: 100)
        let canvasView = PKCanvasView()
        var publishedStrokes: [[Stroke]] = []
        let published = expectation(description: "Rapid strokes published")
        let coordinator = PencilStrokeTestFixture.coordinator {
            publishedStrokes.append($0)
            published.fulfill()
        }

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [firstStroke])
        coordinator.canvasViewDidEndUsingTool(canvasView)
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [firstStroke, secondStroke])
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(publishedStrokes.map(\.count), [2])
        XCTAssertEqual(publishedStrokes[0][0].samples.map(\.point), firstStroke.samples.map(\.point))
        XCTAssertEqual(publishedStrokes[0][1].samples.map(\.point), secondStroke.samples.map(\.point))
        let storedStrokes = publishedStrokes[0]
        XCTAssertEqual(coordinator.canonicalStrokes, storedStrokes)
        XCTAssertFalse(PencilCanvasModelReconciliation.requiresRedraw(
            current: coordinator.canonicalStrokes,
            incoming: storedStrokes
        ))
    }

    func testFinishingInputDoesNotReplacePencilKitsNativeDrawing() async {
        let stroke = stroke(sampleCount: 12, xOffset: 0)
        let canvasView = DrawingWriteCountingCanvasView()
        var publishedStrokes: [Stroke] = []
        let published = expectation(description: "Native drawing published")
        let coordinator = PencilStrokeTestFixture.coordinator {
            publishedStrokes = $0
            published.fulfill()
        }

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [stroke])
        canvasView.resetDrawingWriteCount()
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(publishedStrokes.count, 1)
        XCTAssertEqual(canvasView.drawingWriteCount, 0)
    }

    func testDuplicateLegacyIdentifiersRemainSafeDuringAConcurrentModelUpdate() async {
        let repeatedID = StrokeID()
        let first = stroke(sampleCount: 8, xOffset: 0, id: repeatedID)
        let second = stroke(sampleCount: 8, xOffset: 80, id: repeatedID)
        let concurrent = stroke(sampleCount: 6, xOffset: 160)
        let local = stroke(sampleCount: 10, xOffset: 240)
        let canvasView = PKCanvasView()
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [first, second])
        let published = expectation(description: "Local stroke published")
        var publishedStrokes: [Stroke] = []
        let coordinator = PencilStrokeTestFixture.coordinator {
            publishedStrokes = $0
            published.fulfill()
        }
        coordinator.knownStrokeCount = 2
        coordinator.canonicalStrokes = [first, second]

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [first, second, local])
        coordinator.receiveModelStrokes([first, second, concurrent])
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(publishedStrokes.count, 1)
        XCTAssertEqual(canvasView.drawing.strokes.count, 3)
    }

    func testTaggedModelDrawingDelegateEchoCreatesNoLocalChange() async {
        let stroke = stroke(sampleCount: 8, xOffset: 0)
        let drawing = PencilCanvasRenderer.drawing(from: [stroke])
        let canvasView = PKCanvasView()
        var publicationCount = 0
        let coordinator = PencilStrokeTestFixture.coordinator(
            onStrokesCompleted: { _ in publicationCount += 1 },
            onDrawingChanged: { _ in publicationCount += 1 }
        )
        coordinator.canonicalStrokes = [stroke]
        coordinator.tagAppliedModelDrawing(drawing)
        canvasView.drawing = drawing

        coordinator.canvasViewDrawingDidChange(canvasView)
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(publicationCount, 0)
        XCTAssertFalse(coordinator.isProtectingNativeDrawing)
    }

    func testExistingStrokeGeometryPublishesOnlyAfterToolUseEnds() async {
        let original = stroke(sampleCount: 6, xOffset: 0)
        let moved = stroke(sampleCount: 6, xOffset: 300)
        let canvasView = PKCanvasView()
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [moved])
        var changedStrokes: [[Stroke]] = []
        let published = expectation(description: "Geometry change published")
        let coordinator = PencilStrokeTestFixture.coordinator(
            onStrokesCompleted: { _ in },
            onDrawingChanged: {
                changedStrokes.append($0)
                published.fulfill()
            }
        )
        coordinator.knownStrokeCount = 1
        coordinator.canonicalStrokes = [original]

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        coordinator.canvasViewDrawingDidChange(canvasView)

        XCTAssertTrue(changedStrokes.isEmpty)

        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(changedStrokes.count, 1)
        XCTAssertEqual(changedStrokes[0][0].id, original.id)
        XCTAssertEqual(changedStrokes[0][0].samples.map(\.point), moved.samples.map(\.point))
    }
}

extension PencilCanvasInputBehaviorTests {
    func stroke(
        sampleCount: Int,
        xOffset: Double,
        id: StrokeID = StrokeID()
    ) -> Stroke {
        var result = DomainFixtures.stroke(id: id)
        result.samples = (0..<sampleCount).map { index in
            StrokeSample(
                point: CanvasPoint(x: xOffset + Double(index * 7), y: Double(index * 5)),
                pressure: 0.5,
                altitude: 0.7,
                azimuth: 1.1,
                roll: 0.2,
                timeOffset: Double(index) * 0.01
            )
        }
        return result
    }

    private func dismantleCanvasWithPendingInk(
        model: AppModel,
        notebook: Notebook,
        canvas: Canvas
    ) -> PencilCanvasSnapshotFlusher {
        let callbacks = NotebookEditorView(model: model, notebook: notebook)
            .pencilPersistenceCallbacks(for: canvas.id)
        let coordinator = PencilStrokeTestFixture.coordinator(
            activeLayerID: canvas.layers[0].id,
            onCompletedPencilStrokes: callbacks.onStrokesCompleted
        )
        let snapshotFlusher = PencilCanvasSnapshotFlusher()
        let canvasView = PKCanvasView()
        coordinator.attachSnapshotFlusher(snapshotFlusher, canvasView: canvasView)
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [PencilStrokeTestFixture.blackStroke(randomSeed: 811)])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)
        PencilCanvasView.dismantleUIView(canvasView, coordinator: coordinator)
        return snapshotFlusher
    }
}
@MainActor
private final class DrawingWriteCountingCanvasView: PKCanvasView {
    private(set) var drawingWriteCount = 0

    override var drawing: PKDrawing {
        didSet { drawingWriteCount += 1 }
    }

    func resetDrawingWriteCount() {
        drawingWriteCount = 0
    }
}
