import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
extension PencilCanvasInputBehaviorTests {
    func testCanvasPanRequiresTwoFingersToRejectPalmMovement() {
        let canvasView = PKCanvasView()

        PencilCanvasView.configureViewport(canvasView)

        XCTAssertEqual(canvasView.panGestureRecognizer.minimumNumberOfTouches, 2)
    }

    func testEraserPublishesWhenNoDrawingChangeFollowsToolUseEnd() async {
        let pencilStroke = PencilStrokeTestFixture.pencilStroke(
            color: .black,
            size: CGSize(width: 3, height: 3),
            opacity: 1,
            randomSeed: 9
        )
        let existingStroke = PencilStrokeTestFixture.capture(
            [pencilStroke],
            configurations: [.favoriteOne]
        )[0]
        let canvasView = PKCanvasView()
        canvasView.drawing = PKDrawing(strokes: [pencilStroke])
        let published = expectation(description: "Erase published after tool use ends")
        let coordinator = PencilStrokeTestFixture.coordinator(
            onStrokesCompleted: { _ in },
            onDrawingChanged: { strokes in
                XCTAssertTrue(strokes.isEmpty)
                published.fulfill()
            }
        )
        coordinator.canonicalStrokes = [existingStroke]
        coordinator.configuration = ToolConfiguration(
            tool: .eraser,
            width: .medium,
            color: .black
        )

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing()
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
    }

    func testObjectEraserKeepsTheIdentityAndStyleOfSurvivingStrokes() async {
        let sequence = PencilStrokeTestFixture.markerHighlightMarkerSequence()
        let captured = PencilStrokeTestFixture.capture(
            sequence.pencilStrokes,
            configurations: sequence.configurations
        )
        let canvasView = PKCanvasView()
        canvasView.drawing = PKDrawing(strokes: [
            sequence.pencilStrokes[0],
            sequence.pencilStrokes[2]
        ])
        var changedStrokes: [Stroke] = []
        let published = expectation(description: "Object erase published")
        let coordinator = PencilStrokeTestFixture.coordinator(
            onStrokesCompleted: { _ in },
            onDrawingChanged: {
                changedStrokes = $0
                published.fulfill()
            }
        )
        coordinator.knownStrokeCount = captured.count
        coordinator.canonicalStrokes = captured

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(changedStrokes.map(\.id), [captured[0].id, captured[2].id])
        XCTAssertEqual(changedStrokes.map(\.style), [captured[0].style, captured[2].style])
        XCTAssertEqual(
            PencilCanvasRenderer.drawing(from: changedStrokes).strokes.map(\.randomSeed),
            [11, 33]
        )
    }

    func testPrecisionEraserSplitPublishesAWholeDrawingEdit() async {
        let sourcePencilStroke = PencilStrokeTestFixture.pencilStroke(
            color: .black,
            size: CGSize(width: 3, height: 3),
            opacity: 1,
            randomSeed: 71
        )
        let sourceStroke = PencilStrokeTestFixture.capture(
            [sourcePencilStroke],
            configurations: [.favoriteOne]
        )[0]
        var firstFragment = sourcePencilStroke
        firstFragment.transform = CGAffineTransform(translationX: -20, y: 0)
        var secondFragment = sourcePencilStroke
        secondFragment.transform = CGAffineTransform(translationX: 40, y: 0)
        let canvasView = PKCanvasView()
        canvasView.drawing = PKDrawing(strokes: [firstFragment, secondFragment])
        var addedPublicationCount = 0
        var editedStrokes: [Stroke] = []
        let published = expectation(description: "Split erase published")
        let coordinator = PencilStrokeTestFixture.coordinator(
            onStrokesCompleted: { _ in
                addedPublicationCount += 1
                published.fulfill()
            },
            onDrawingChanged: {
                editedStrokes = $0
                published.fulfill()
            }
        )
        coordinator.configuration = ToolConfiguration(
            tool: .eraser,
            width: .medium,
            color: .black,
            eraserMode: .precision
        )
        coordinator.knownStrokeCount = 1
        coordinator.canonicalStrokes = [sourceStroke]

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(addedPublicationCount, 0)
        XCTAssertEqual(editedStrokes.count, 2)
        XCTAssertEqual(editedStrokes.first?.id, sourceStroke.id)
        XCTAssertNotEqual(editedStrokes.last?.id, sourceStroke.id)
    }

    func testTwentyRapidStrokesSurviveApplicationRelaunch() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let canvas = Canvas(title: "Rapid writing")
        let notebook = Notebook(title: "Rapid writing", canvases: [canvas])
        let layerID = canvas.layers[0].id
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let firstSession = await PencilStrokeTestFixture.restoredModel(
            repository: repository,
            documentStore: documentStore
        )
        let stored = expectation(description: "Rapid Pencil strokes stored")
        let coordinator = PencilStrokeTestFixture.coordinator(activeLayerID: layerID) { strokes in
            _ = firstSession.addStrokes(
                strokes,
                to: notebook.id,
                canvasID: canvas.id,
                layerID: layerID
            )
            stored.fulfill()
        }
        let pencilStrokes = (0..<20).map { index in
            PencilStrokeTestFixture.blackStroke(
                randomSeed: UInt32(index + 1),
                transform: CGAffineTransform(translationX: CGFloat(index * 12), y: 0)
            )
        }
        let canvasView = PKCanvasView()

        for index in pencilStrokes.indices {
            coordinator.canvasViewDidBeginUsingTool(canvasView)
            canvasView.drawing = PKDrawing(strokes: Array(pencilStrokes.prefix(index + 1)))
            coordinator.canvasViewDrawingDidChange(canvasView)
            coordinator.canvasViewDidEndUsingTool(canvasView)
        }
        await fulfillment(of: [stored], timeout: 1)
        await firstSession.checkpointDocuments()
        let restoredNotebook = await PencilStrokeTestFixture.restoredNotebook(
            notebook.id,
            repository: repository,
            documentStore: documentStore
        )
        let reopened = try XCTUnwrap(restoredNotebook)
        let reopenedStrokes = reopened.canvases[0].layers[0].objects.compactMap(\.strokeValue)
        XCTAssertEqual(reopenedStrokes.count, 20)
        assertNativeSeeds(reopenedStrokes, equal: pencilStrokes)
    }

    func testImmediateSnapshotFlushSavesAnActivePencilStrokeBeforeCheckpoint() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let canvas = Canvas(title: "Immediate save")
        let notebook = Notebook(title: "Immediate save", canvases: [canvas])
        let layerID = canvas.layers[0].id
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let firstSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await firstSession.restoreLibrary()
        let coordinator = PencilStrokeTestFixture.coordinator(activeLayerID: layerID) { strokes in
            _ = firstSession.addStrokes(
                strokes,
                to: notebook.id,
                canvasID: canvas.id,
                layerID: layerID
            )
        }
        let snapshotFlusher = PencilCanvasSnapshotFlusher()
        let canvasView = PKCanvasView()
        coordinator.attachSnapshotFlusher(snapshotFlusher, canvasView: canvasView)
        let nativeStroke = PencilStrokeTestFixture.pencilStroke(
            color: .black,
            size: CGSize(width: 3, height: 3),
            opacity: 1,
            randomSeed: 404
        )

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [nativeStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        await snapshotFlusher.flushPendingSnapshots()
        await firstSession.checkpointDocuments()

        let restoredNotebook = await PencilStrokeTestFixture.restoredNotebook(
            notebook.id,
            repository: repository,
            documentStore: documentStore
        )
        let reopened = try XCTUnwrap(restoredNotebook)
        let reopenedStrokes = reopened.canvases[0].layers[0].objects.compactMap(\.strokeValue)
        XCTAssertEqual(reopenedStrokes.count, 1)
        XCTAssertEqual(PencilKitStrokeArchiveCodec.randomSeed(for: reopenedStrokes[0]), 404)
    }

    func testEraseAndNewInkSurviveApplicationRelaunch() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let scenario = mixedEditScenario()
        try await repository.save(LibraryState(notebooks: [scenario.notebook]))
        try await documentStore.save(
            NativeNotebookPackage(schemaVersion: .current, notebook: scenario.notebook)
        )
        let firstSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            conversionDelay: .seconds(30),
            automaticallyRestore: false
        )
        await firstSession.restoreLibrary()
        let editor = NotebookEditorView(model: firstSession, notebook: scenario.notebook)
        let callbacks = editor.pencilPersistenceCallbacks(for: scenario.canvas.id)
        let published = expectation(description: "Mixed edit stored")
        var conversionIntents: [Bool] = []
        let coordinator = mixedEditCoordinator(
            layerID: scenario.layerID,
            callbacks: callbacks,
            published: published
        ) {
            conversionIntents = $0
        }
        coordinator.canonicalStrokes = scenario.baseline
        coordinator.committedNativeDrawing = scenario.baselineDrawing
        coordinator.knownStrokeCount = scenario.baseline.count
        let canvasView = PKCanvasView()
        canvasView.drawing = scenario.baselineDrawing

        performEraseThenHandwriting(
            coordinator: coordinator,
            canvasView: canvasView,
            survivingStroke: scenario.survivingNativeStroke
        )

        await fulfillment(of: [published], timeout: 1)
        firstSession.conversionTasks[scenario.canvas.id]?.cancel()
        await firstSession.checkpointDocuments()
        let restoredNotebook = await PencilStrokeTestFixture.restoredNotebook(
            scenario.notebook.id,
            repository: repository,
            documentStore: documentStore
        )
        let reopened = try XCTUnwrap(restoredNotebook)
        let reopenedStrokes = reopened.canvases[0].layers[0].objects.compactMap(\.strokeValue)

        assertMixedEditPersistence(
            conversionIntents: conversionIntents, strokes: reopenedStrokes, scenario: scenario
        )
    }

    func testPencilAccessoriesTrackHoverWithoutAddingAVisualTarget() {
        let canvasView = PKCanvasView()
        let existingSubviews = Set(canvasView.subviews.map(ObjectIdentifier.init))
        let coordinator = PencilStrokeTestFixture.coordinator { _ in }

        PencilCanvasInputAccessories.install(on: canvasView, coordinator: coordinator)

        let addedSubviews = canvasView.subviews.filter {
            !existingSubviews.contains(ObjectIdentifier($0))
        }
        XCTAssertTrue(addedSubviews.isEmpty)
        XCTAssertTrue(canvasView.interactions.contains { $0 is UIPencilInteraction })
        XCTAssertTrue(canvasView.gestureRecognizers?.contains { $0 is UIHoverGestureRecognizer } == true)
    }

    func testInfiniteCanvasSelectionAndLassoUseVisibleVectorPaths() {
        let parent = CALayer()
        let outlines = CanvasSelectionOutlineLayers()
        outlines.add(to: parent)

        outlines.update(
            selectionBounds: CGRect(x: 9_000, y: 9_000, width: 600, height: 400),
            handlePoints: [CGPoint(x: 9_000, y: 9_000)],
            lassoPoints: [CGPoint(x: 9_100, y: 9_100), CGPoint(x: 9_500, y: 9_400)]
        )

        XCTAssertEqual(parent.sublayers?.count, 3)
        XCTAssertTrue(outlines.isSelectionVisible)
        XCTAssertTrue(outlines.isLassoVisible)
        XCTAssertTrue(outlines.isSelectionAnimating)
        XCTAssertEqual(outlines.selectionPathBounds, CGRect(x: 8_994, y: 8_994, width: 612, height: 412))
        XCTAssertEqual(outlines.lassoPathBounds, CGRect(x: 9_100, y: 9_100, width: 400, height: 300))
    }

    func testLassoOutlineUsesAnimatedMarchingAnts() {
        let outline = CanvasLassoOutlineLayer()

        XCTAssertEqual(outline.lineDashPattern, [6, 4])
        XCTAssertNotNil(outline.animation(forKey: "marchingAnts"))
    }

    private func assertNativeSeeds(_ strokes: [Stroke], equal pencilStrokes: [PKStroke]) {
        XCTAssertEqual(
            PencilCanvasRenderer.drawing(from: strokes).strokes.map(\.randomSeed),
            pencilStrokes.map(\.randomSeed)
        )
    }

    private func assertMixedEditPersistence(
        conversionIntents: [Bool],
        strokes: [Stroke],
        scenario: MixedEditScenario
    ) {
        XCTAssertEqual(conversionIntents, [true])
        XCTAssertEqual(strokes.count, 2)
        XCTAssertEqual(strokes[0].id, scenario.baseline[1].id)
        XCTAssertEqual(strokes.map(\.layerID), [scenario.layerID, scenario.layerID])
        XCTAssertEqual(strokes.map(\.style.instrument), [.ballpoint, .ballpoint])
        XCTAssertEqual(
            strokes.map { PencilKitStrokeArchiveCodec.randomSeed(for: $0) },
            [902, 903]
        )
    }

    private func performEraseThenHandwriting(
        coordinator: PencilCanvasView.Coordinator,
        canvasView: PKCanvasView,
        survivingStroke: PKStroke
    ) {
        coordinator.configuration = ToolConfiguration(
            tool: .eraser,
            width: .medium,
            color: .black,
            eraserMode: .stroke
        )
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [survivingStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        let newStroke = PencilStrokeTestFixture.blackPenStroke(
            randomSeed: 903,
            transform: CGAffineTransform(translationX: 240, y: 0)
        )
        coordinator.configuration = ToolConfiguration(
            tool: .handwritingToText,
            width: .thin,
            color: .black
        )
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [survivingStroke, newStroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)
    }

    private func mixedEditScenario() -> MixedEditScenario {
        let layerID = LayerID()
        let erasedStroke = PencilStrokeTestFixture.blackStroke(randomSeed: 901)
        let survivingStroke = PencilStrokeTestFixture.blackStroke(
            randomSeed: 902,
            transform: CGAffineTransform(translationX: 120, y: 0)
        )
        let drawing = PKDrawing(strokes: [erasedStroke, survivingStroke])
        let baseline = PencilDrawingReconciler.edit(
            drawing: drawing,
            baseline: [],
            activeLayerID: layerID,
            configuration: .favoriteOne,
            pencilRoll: 0,
            createdAt: DomainFixtures.fixedDate
        ).after
        let canvas = Canvas(
            title: "Mixed edit",
            layers: [Layer(id: layerID, name: "Writing", objects: baseline.map(CanvasObject.stroke))]
        )
        return MixedEditScenario(
            layerID: layerID,
            survivingNativeStroke: survivingStroke,
            baselineDrawing: drawing,
            baseline: baseline,
            canvas: canvas,
            notebook: Notebook(title: "Mixed edit", canvases: [canvas])
        )
    }

    private func mixedEditCoordinator(
        layerID: LayerID,
        callbacks: NotebookEditorPencilPersistenceCallbacks,
        published: XCTestExpectation,
        onConversionIntents: @escaping @MainActor ([Bool]) -> Void
    ) -> PencilCanvasView.Coordinator {
        PencilCanvasView.Coordinator(
            activeLayerID: layerID,
            onStrokesCompleted: callbacks.onStrokesCompleted,
            onDrawingChanged: { edit, completedStrokes in
                onConversionIntents(completedStrokes.map(\.shouldConvertToText))
                callbacks.onDrawingChanged(edit, completedStrokes)
                published.fulfill()
            },
            onConvertStrokesToText: { _ in },
            onViewportChanged: { _ in },
            onPencilSqueeze: { _, _ in },
            onPencilDoubleTap: {},
            onPlannerRegionPageRequested: { _ in }
        )
    }
}

private struct MixedEditScenario {
    let layerID: LayerID
    let survivingNativeStroke: PKStroke
    let baselineDrawing: PKDrawing
    let baseline: [Stroke]
    let canvas: Canvas
    let notebook: Notebook
}
