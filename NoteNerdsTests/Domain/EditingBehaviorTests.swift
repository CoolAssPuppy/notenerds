import XCTest
@testable import NoteNerds

final class EditingBehaviorTests: XCTestCase {
    func testCanvasStrokeEditPreservesConcurrentStrokeAndDuplicateLegacyIdentifiers() {
        let layerID = LayerID()
        let repeatedID = StrokeID()
        let first = DomainFixtures.stroke(id: repeatedID, layerID: layerID)
        var second = first
        second.samples[0].point.x += 40
        var concurrentSecond = second
        concurrentSecond.samples[0].point.y += 30
        let concurrent = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let replacement = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let edit = CanvasStrokeEdit(
            before: [first, second],
            after: [second, replacement]
        )

        let result = edit.applying(to: [first, concurrentSecond, concurrent])

        XCTAssertEqual(result, [concurrentSecond, replacement, concurrent])
    }

    func testCanvasStrokeEditKeepsRemotelyChangedSurvivingDuplicateLegacyStroke() {
        let layerID = LayerID()
        let repeatedID = StrokeID()
        let first = DomainFixtures.stroke(id: repeatedID, layerID: layerID)
        var second = first
        second.samples[0].point.x += 40
        var remoteSecond = second
        remoteSecond.samples[0].point.y += 10
        let edit = CanvasStrokeEdit(
            before: [first, second],
            after: [second]
        )

        let result = edit.applying(to: [remoteSecond])

        XCTAssertEqual(result, [remoteSecond])
    }

    func testCanvasStrokeEditDoesNotDuplicateAConcurrentlyChangedStroke() {
        let layerID = LayerID()
        let original = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let untouched = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        var remoteVersion = original
        remoteVersion.samples[0].point.y += 30
        var localVersion = original
        localVersion.samples[0].point.x += 40
        let edit = CanvasStrokeEdit(
            before: [original, untouched],
            after: [localVersion, untouched]
        )

        let result = edit.applying(to: [remoteVersion, untouched])

        XCTAssertEqual(result, [localVersion, untouched])
    }

    func testCanvasStrokeEditKeepsANewEraserFragmentBesideItsSourceStroke() {
        let layerID = LayerID()
        let source = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let untouched = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let concurrent = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        var firstFragment = source
        firstFragment.samples[0].point.x += 20
        let secondFragment = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let edit = CanvasStrokeEdit(
            before: [source, untouched],
            after: [firstFragment, secondFragment, untouched]
        )

        let result = edit.applying(to: [source, untouched, concurrent])

        XCTAssertEqual(result, [firstFragment, secondFragment, untouched, concurrent])
    }

    @MainActor
    func testVisibleStrokeEditUpdatesOriginalLayersAndPreservesConcurrentInk() throws {
        let backgroundLayerID = LayerID()
        let writingLayerID = LayerID()
        let background = DomainFixtures.stroke(id: StrokeID(), layerID: backgroundLayerID)
        let writing = DomainFixtures.stroke(id: StrokeID(), layerID: writingLayerID)
        let concurrent = DomainFixtures.stroke(id: StrokeID(), layerID: writingLayerID)
        var movedBackground = background
        movedBackground.samples[0].point.x += 30
        let canvas = Canvas(
            title: "Layered writing",
            layers: [
                Layer(id: backgroundLayerID, name: "Background", objects: [.stroke(background)]),
                Layer(id: writingLayerID, name: "Writing", objects: [.stroke(writing), .stroke(concurrent)])
            ]
        )
        let notebook = Notebook(title: "Layered note", canvases: [canvas])
        let model = AppModel(automaticallyRestore: false)
        model.library = LibraryState(notebooks: [notebook])

        model.applyVisibleStrokeEdit(
            CanvasStrokeEdit(
                before: [background, writing],
                after: [movedBackground]
            ),
            in: notebook.id,
            canvasID: canvas.id
        )

        let savedCanvas = try XCTUnwrap(model.notebook(notebook.id)?.canvases.first)
        XCTAssertEqual(savedCanvas.layers[0].objects.compactMap(\.strokeValue), [movedBackground])
        XCTAssertEqual(savedCanvas.layers[1].objects.compactMap(\.strokeValue), [concurrent])
    }

    @MainActor
    func testVisibleStrokeEditErasesTheCorrectDuplicateAndUndoRestoresExactOrder() throws {
        let layerID = LayerID()
        let repeatedID = StrokeID()
        let first = DomainFixtures.stroke(id: repeatedID, layerID: layerID)
        var second = first
        second.samples[0].point.x += 40
        let text = TextBlock(
            id: ObjectID(),
            layerID: layerID,
            text: "Between duplicate ink",
            frame: CanvasRect(x: 20, y: 30, width: 160, height: 40),
            fontSize: 18,
            alignment: .left,
            fontName: nil
        )
        let originalObjects: [CanvasObject] = [.stroke(first), .text(text), .stroke(second)]
        let canvas = Canvas(
            title: "Ordered objects",
            layers: [Layer(id: layerID, name: "Layer 1", objects: originalObjects)]
        )
        let notebook = Notebook(title: "Ordered objects", canvases: [canvas])
        let model = AppModel(automaticallyRestore: false)
        model.library = LibraryState(notebooks: [notebook])

        model.applyVisibleStrokeEdit(
            CanvasStrokeEdit(before: [first, second], after: [second]),
            in: notebook.id,
            canvasID: canvas.id
        )

        XCTAssertEqual(
            model.notebook(notebook.id)?.canvases[0].layers[0].objects,
            [.text(text), .stroke(second)]
        )

        model.undo(notebook.id)

        XCTAssertEqual(model.notebook(notebook.id)?.canvases[0].layers[0].objects, originalObjects)
    }

    @MainActor
    func testVisibleStrokeSplitStaysAtTheSourceObjectPositionAndUndoesCleanly() throws {
        let layerID = LayerID()
        let source = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let untouched = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let concurrent = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let text = TextBlock(
            id: ObjectID(),
            layerID: layerID,
            text: "Between the ink",
            frame: CanvasRect(x: 20, y: 30, width: 160, height: 40),
            fontSize: 18,
            alignment: .left,
            fontName: nil
        )
        var firstFragment = source
        firstFragment.samples[0].point.x += 20
        let secondFragment = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let originalObjects: [CanvasObject] = [
            .stroke(source), .text(text), .stroke(untouched), .stroke(concurrent)
        ]
        let canvas = Canvas(
            title: "Split ink",
            layers: [Layer(id: layerID, name: "Layer 1", objects: originalObjects)]
        )
        let notebook = Notebook(title: "Split ink", canvases: [canvas])
        let model = AppModel(automaticallyRestore: false)
        model.library = LibraryState(notebooks: [notebook])

        model.applyVisibleStrokeEdit(
            CanvasStrokeEdit(
                before: [source, untouched],
                after: [firstFragment, secondFragment, untouched]
            ),
            in: notebook.id,
            canvasID: canvas.id
        )

        XCTAssertEqual(
            model.notebook(notebook.id)?.canvases[0].layers[0].objects,
            [.stroke(firstFragment), .stroke(secondFragment), .text(text), .stroke(untouched), .stroke(concurrent)]
        )

        model.undo(notebook.id)

        XCTAssertEqual(model.notebook(notebook.id)?.canvases[0].layers[0].objects, originalObjects)
    }

    func testReplacingVisibleStrokesHandlesDuplicateLegacyIdentifiers() throws {
        let layerID = LayerID()
        let repeatedID = StrokeID()
        let first = DomainFixtures.stroke(id: repeatedID, layerID: layerID)
        var second = first
        second.samples[0].point.x += 40
        let canvas = Canvas(
            title: "Legacy notes",
            layers: [Layer(id: layerID, name: "Notes", objects: [.stroke(first), .stroke(second)])]
        )
        var notebook = Notebook(title: "Imported notes", canvases: [canvas])
        let added = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)

        let operation = try DocumentOperation.replacingObjects(
            in: notebook,
            canvasID: canvas.id,
            objectIDs: [first.objectID],
            with: [.stroke(first), .stroke(second), .stroke(added)]
        )
        try operation.apply(to: &notebook)
        var strokes = notebook.canvases[0].layers[0].objects.compactMap(\.strokeValue)

        XCTAssertEqual(strokes, [first, second, added])

        try operation.undo(on: &notebook)
        strokes = notebook.canvases[0].layers[0].objects.compactMap(\.strokeValue)

        XCTAssertEqual(strokes, [first, second])
    }

    func testTransformingDuplicateLegacyStrokeIdentifiersDoesNotTrap() throws {
        let layerID = LayerID()
        let repeatedID = StrokeID()
        let first = DomainFixtures.stroke(id: repeatedID, layerID: layerID)
        var second = first
        second.samples[0].point.x += 40
        var movedFirst = first
        movedFirst.samples[0].point.y += 20
        var movedSecond = second
        movedSecond.samples[0].point.y += 30
        let canvas = Canvas(
            title: "Legacy selection",
            layers: [Layer(id: layerID, name: "Notes", objects: [.stroke(first), .stroke(second)])]
        )
        var notebook = Notebook(title: "Imported notes", canvases: [canvas])

        let operation = try DocumentOperation.transformObjects(
            in: notebook,
            canvasID: canvas.id,
            objectIDs: [first.objectID],
            transform: SelectionTransform(
                scaleX: 1,
                scaleY: 1,
                rotation: 0,
                translation: .zero
            ),
            center: .zero,
            strokeReplacements: [movedFirst, movedSecond]
        )
        try operation.apply(to: &notebook)

        let strokes = notebook.canvases[0].layers[0].objects.compactMap(\.strokeValue)
        XCTAssertEqual(strokes, [movedFirst, movedSecond])
    }

    func testSelectionTransformPreservesLayerMembershipAndUndoRestoresExactObjects() throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let original = canvas.layers[0].objects[0]
        let operation = try DocumentOperation.transformObjects(
            in: notebook,
            canvasID: canvas.id,
            objectIDs: [original.id],
            transform: SelectionTransform(
                scaleX: 2,
                scaleY: 2,
                rotation: .pi / 4,
                translation: CanvasPoint(x: 30, y: 20)
            ),
            center: CanvasPoint(x: 20, y: 30)
        )

        try operation.apply(to: &notebook)
        let transformed = notebook.canvases[0].layers[0].objects[0]
        XCTAssertEqual(transformed.layerID, original.layerID)
        XCTAssertNotEqual(transformed, original)

        try operation.undo(on: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects[0], original)
    }

    func testClipboardPasteCreatesFreshEditableObjectsWithOneOffset() throws {
        let notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let source = canvas.layers[0].objects
        let payload = SelectionClipboardPayload(objects: source)

        let pasted = payload.pasted(offset: CanvasPoint(x: 24, y: 32))

        XCTAssertEqual(pasted.count, source.count)
        XCTAssertNotEqual(pasted[0].id, source[0].id)
        XCTAssertEqual(pasted[0].layerID, source[0].layerID)
        XCTAssertEqual(pasted[0].bounds.minX, source[0].bounds.minX + 24, accuracy: 0.001)
        XCTAssertEqual(pasted[0].bounds.minY, source[0].bounds.minY + 32, accuracy: 0.001)
    }

    func testClipboardPastePreservesTheSelectedFont() throws {
        let layerID = LayerID()
        let source = CanvasObject.text(TextBlock(
            id: ObjectID(),
            layerID: layerID,
            text: "Set in Avenir",
            frame: CanvasRect(x: 0, y: 0, width: 240, height: 44),
            fontSize: 22,
            alignment: .left,
            fontName: "AvenirNext-Regular"
        ))

        let pasted = try XCTUnwrap(SelectionClipboardPayload(objects: [source]).pasted(offset: .zero).first)
        guard case let .text(textBlock) = pasted else {
            return XCTFail("Expected pasted text")
        }

        XCTAssertEqual(textBlock.fontName, "AvenirNext-Regular")
    }

    func testPrecisionEraserSplitsVectorStrokeAndKeepsSampleData() {
        let layerID = LayerID()
        var stroke = DomainFixtures.stroke(layerID: layerID)
        stroke.samples = (0...10).map { index in
            StrokeSample(
                point: CanvasPoint(x: Double(index * 10), y: 20),
                pressure: Double(index) / 10,
                altitude: 0.7,
                azimuth: 1.1,
                roll: 0.2,
                timeOffset: Double(index) * 0.01
            )
        }

        let fragments = VectorEraser().erase(
            stroke,
            along: [CanvasPoint(x: 50, y: 20)],
            radius: 12
        )

        XCTAssertEqual(fragments.count, 2)
        XCTAssertEqual(fragments.flatMap(\.samples).map(\.pressure), [0, 0.1, 0.2, 0.3, 0.7, 0.8, 0.9, 1])
        XCTAssertTrue(fragments.allSatisfy { $0.layerID == layerID && $0.style == stroke.style })
    }

    func testHandwritingConversionLayoutPreservesReadingOrderAndLineBreaks() {
        let first = recognition(text: "Hello", x: 10, y: 20)
        let second = recognition(text: "world", x: 100, y: 22)
        let nextLine = recognition(text: "Again", x: 10, y: 80)

        let block = HandwritingTextLayout().textBlock(
            from: [nextLine, second, first],
            layerID: LayerID()
        )

        XCTAssertEqual(block.text, "Hello world\nAgain")
        XCTAssertEqual(block.frame, CanvasRect(x: 10, y: 20, width: 150, height: 90))
    }

    func testConvertingSelectedStrokesKeepsOtherSelectedObjectTypesUnchanged() throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = try XCTUnwrap(layer.objects.compactMap(\.strokeValue).first)
        let existingText = TextBlock(
            id: ObjectID(),
            layerID: layer.id,
            text: "Keep me",
            frame: CanvasRect(x: 200, y: 200, width: 100, height: 40),
            fontSize: 17,
            alignment: .left
        )
        notebook.canvases[0].layers[0].objects.append(.text(existingText))
        let replacement = TextBlock(
            id: ObjectID(),
            layerID: layer.id,
            text: "Converted",
            frame: stroke.bounds,
            fontSize: 17,
            alignment: .left
        )
        let operation = try DocumentOperation.convertStrokesToText(
            in: notebook,
            canvasID: canvas.id,
            strokeIDs: [stroke.id],
            textBlock: replacement
        )

        try operation.apply(to: &notebook)

        let objects = notebook.canvases[0].layers[0].objects
        XCTAssertTrue(objects.contains(.text(existingText)))
        XCTAssertTrue(objects.contains(.text(replacement)))
        XCTAssertFalse(objects.contains(.stroke(stroke)))
    }

    func testShapeSnapUndoRestoresOriginalFreehandStroke() throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let shape = RecognizedShape(
            id: ObjectID(), layerID: stroke.layerID, kind: .line,
            points: [CanvasPoint(x: 10, y: 20), CanvasPoint(x: 30, y: 40)],
            style: stroke.style, originalStroke: stroke
        )
        let operation = try DocumentOperation.snapStrokeToShape(
            canvasID: canvas.id,
            strokeID: stroke.id,
            shape: shape,
            in: notebook
        )

        try operation.apply(to: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects[0], .shape(shape))
        try operation.undo(on: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects[0], .stroke(stroke))
    }

    @MainActor
    func testCompletingAHighlightKeepsUnderlyingWritingAndAvoidsCanvasReplacement() throws {
        let notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let underlyingWriting = try XCTUnwrap(layer.objects[0].strokeValue)
        let highlight = Stroke(
            id: StrokeID(),
            layerID: layer.id,
            samples: [
                timedSample(x: 0, y: 20, time: 0),
                timedSample(x: 120, y: 20, time: 0.1),
                timedSample(x: 120, y: 20, time: 0.7)
            ],
            style: StrokeStyle(
                instrument: .highlighter,
                width: 6,
                color: InkColor(red: 0.95, green: 0.78, blue: 0.2, alpha: 0.45)
            ),
            createdAt: DomainFixtures.fixedDate
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "library.json")
        let model = AppModel(
            repository: LocalLibraryRepository(fileURL: fileURL),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])

        let didSnapShape = model.addStrokes(
            [highlight],
            to: notebook.id,
            canvasID: canvas.id,
            layerID: layer.id
        )

        let storedObjects = try XCTUnwrap(model.notebook(notebook.id)?.canvases[0].layers[0].objects)
        let storedStrokes = storedObjects.compactMap(\.strokeValue)
        XCTAssertFalse(didSnapShape)
        XCTAssertEqual(storedObjects, [.stroke(underlyingWriting), .stroke(highlight)])
        XCTAssertFalse(PencilCanvasModelReconciliation.requiresRedraw(
            current: [underlyingWriting, highlight],
            incoming: storedStrokes
        ))
    }

    func testEraserRemembersStrokeAndPrecisionModes() {
        var palette = ToolPaletteState()
        palette.select(.eraser)
        palette.setEraserMode(.precision)
        palette.select(.ballpoint)

        palette.select(.eraser)

        XCTAssertEqual(palette.current.eraserMode, .precision)
    }
}
