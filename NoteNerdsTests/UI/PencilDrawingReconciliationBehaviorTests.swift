import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
extension PencilCanvasInputBehaviorTests {
    func testChangedPrefixWithNewInkIsNotAPlainAddition() {
        let original = stroke(sampleCount: 6, xOffset: 0)
        var pressureUpdated = original
        pressureUpdated.samples[0].pressure += 0.25
        let newStroke = stroke(sampleCount: 8, xOffset: 100)

        let edit = CanvasStrokeEdit(before: [original], after: [pressureUpdated, newStroke])

        XCTAssertNil(edit.addedStrokes)
    }

    func testAppendOnlySnapshotReusesTheCommittedNativeDrawing() throws {
        let layerID = LayerID()
        let baselinePencilStrokes = (0..<200).map { index in
            PencilStrokeTestFixture.pencilStroke(
                color: .black,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                randomSeed: UInt32(index + 100),
                transform: CGAffineTransform(translationX: CGFloat(index * 4), y: 0)
            )
        }
        let committedDrawing = PKDrawing(strokes: baselinePencilStrokes)
        let baseline = PencilDrawingReconciler.edit(
            drawing: committedDrawing,
            baseline: [],
            activeLayerID: layerID,
            configuration: .favoriteOne,
            pencilRoll: 0,
            createdAt: DomainFixtures.fixedDate
        ).after
        let appendedStroke = PencilStrokeTestFixture.pencilStroke(
            color: .black,
            size: CGSize(width: 3, height: 3),
            opacity: 1,
            randomSeed: 999
        )
        let result = try XCTUnwrap(PencilDrawingReconciler.reconcile(
            drawing: PKDrawing(strokes: baselinePencilStrokes + [appendedStroke]),
            committedDrawing: committedDrawing,
            baseline: baseline,
            contacts: [PencilContactSnapshot(
                input: PencilStrokeInput(
                    configuration: .favoriteOne,
                    layerID: layerID,
                    createdAt: DomainFixtures.fixedDate
                ),
                appendedStrokeKeys: [PencilNativeStrokeKey(appendedStroke)],
                endingStrokeCount: baselinePencilStrokes.count + 1
            )],
            fallbackInput: PencilStrokeInput(
                configuration: .favoriteOne,
                layerID: layerID,
                createdAt: DomainFixtures.fixedDate
            )
        ))

        XCTAssertEqual(result.reusedStrokeCount, baseline.count)
        XCTAssertEqual(Array(result.edit.after.prefix(baseline.count)), baseline)
        XCTAssertEqual(result.completedStrokes.count, 1)
        XCTAssertEqual(result.publication, .completedStrokes)
    }

    func testObjectEraseReusesEveryUnchangedNativeSurvivor() throws {
        let layerID = LayerID()
        let nativeStrokes = (0..<200).map { index in
            PencilStrokeTestFixture.pencilStroke(
                color: .black,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                randomSeed: UInt32(index + 300),
                transform: CGAffineTransform(translationX: CGFloat(index * 4), y: 0)
            )
        }
        let baselineDrawing = PKDrawing(strokes: nativeStrokes)
        let baseline = PencilDrawingReconciler.edit(
            drawing: baselineDrawing,
            baseline: [],
            activeLayerID: layerID,
            configuration: .favoriteOne,
            pencilRoll: 0,
            createdAt: DomainFixtures.fixedDate
        ).after

        let result = try XCTUnwrap(PencilDrawingReconciler.reconcile(
            drawing: PKDrawing(strokes: Array(nativeStrokes.dropFirst())),
            committedDrawing: baselineDrawing,
            baseline: baseline,
            contacts: [],
            fallbackInput: PencilStrokeInput(
                configuration: ToolConfiguration(
                    tool: .eraser,
                    width: .medium,
                    color: .black,
                    eraserMode: .stroke
                ),
                layerID: layerID,
                createdAt: DomainFixtures.fixedDate
            )
        ))

        XCTAssertEqual(result.reusedStrokeCount, nativeStrokes.count - 1)
        XCTAssertEqual(result.edit.after, Array(baseline.dropFirst()))
        XCTAssertEqual(result.publication, .drawingChanged)
    }

    func testAppendSnapshotKeepsAnEarlierCommittedStrokeChange() throws {
        let layerID = LayerID()
        let first = PencilStrokeTestFixture.blackStroke(randomSeed: 501)
        let second = PencilStrokeTestFixture.blackStroke(randomSeed: 502)
        let committedDrawing = PKDrawing(strokes: [first, second])
        let baseline = PencilDrawingReconciler.edit(
            drawing: committedDrawing,
            baseline: [],
            activeLayerID: layerID,
            configuration: .favoriteOne,
            pencilRoll: 0,
            createdAt: DomainFixtures.fixedDate
        ).after
        let changedFirst = PencilStrokeTestFixture.blackStroke(randomSeed: 501, forceOffset: 0.25)
        let added = PencilStrokeTestFixture.blackStroke(randomSeed: 503)
        let incomingDrawing = PKDrawing(strokes: [changedFirst, second, added])
        let input = PencilStrokeInput(
            configuration: .favoriteOne,
            layerID: layerID,
            createdAt: DomainFixtures.fixedDate
        )

        let result = try XCTUnwrap(PencilDrawingReconciler.reconcile(
            drawing: incomingDrawing,
            committedDrawing: committedDrawing,
            baseline: baseline,
            contacts: [PencilContactSnapshot(
                input: input,
                appendedStrokeKeys: [PencilNativeStrokeKey(added)],
                endingStrokeCount: incomingDrawing.strokes.count
            )],
            fallbackInput: input
        ))

        XCTAssertEqual(result.edit.after.count, 3)
        XCTAssertEqual(
            result.edit.after[0].samples.map(\.pressure),
            changedFirst.path.map { Double($0.force) }
        )
        XCTAssertEqual(result.completedStrokes.count, 1)
        XCTAssertEqual(result.publication, .drawingChanged)
    }

    func testWritingThenPrecisionEraseKeepsMetadataForEveryNewFragment() throws {
        let layerID = LayerID()
        let source = PencilStrokeTestFixture.pencilStroke(
            inkType: .pen,
            color: .black,
            size: CGSize(width: 2, height: 2),
            opacity: 1,
            randomSeed: 601
        )
        var firstFragment = source
        firstFragment.transform = CGAffineTransform(translationX: -20, y: 0)
        var secondFragment = source
        secondFragment.transform = CGAffineTransform(translationX: 40, y: 0)
        let drawingInput = handwritingInput(layerID: layerID)
        let eraserInput = precisionEraserInput(layerID: layerID)
        let result = try XCTUnwrap(PencilDrawingReconciler.reconcile(
            drawing: PKDrawing(strokes: [firstFragment, secondFragment]),
            committedDrawing: PKDrawing(),
            baseline: [],
            contacts: [
                PencilContactSnapshot(
                    input: drawingInput,
                    appendedStrokeKeys: [PencilNativeStrokeKey(source)],
                    endingStrokeCount: 1
                ),
                PencilContactSnapshot(
                    input: eraserInput,
                    appendedStrokeKeys: [],
                    endingStrokeCount: 2
                )
            ],
            fallbackInput: eraserInput
        ))

        XCTAssertEqual(result.edit.after.count, 2)
        XCTAssertEqual(result.completedStrokes.count, 2)
        XCTAssertEqual(result.completedStrokes.map(\.stroke.layerID), [layerID, layerID])
        XCTAssertEqual(result.completedStrokes.map(\.stroke.style.instrument), [.ballpoint, .ballpoint])
        XCTAssertEqual(result.completedStrokes.map(\.shouldConvertToText), [true, true])
        XCTAssertEqual(result.publication, .completedStrokes)
    }

    private func handwritingInput(layerID: LayerID) -> PencilStrokeInput {
        PencilStrokeInput(
            configuration: ToolConfiguration(
                tool: .handwritingToText,
                width: .thin,
                color: .black
            ),
            layerID: layerID,
            createdAt: DomainFixtures.fixedDate
        )
    }

    private func precisionEraserInput(layerID: LayerID) -> PencilStrokeInput {
        PencilStrokeInput(
            configuration: ToolConfiguration(
                tool: .eraser,
                width: .medium,
                color: .black,
                eraserMode: .precision
            ),
            layerID: layerID,
            createdAt: DomainFixtures.fixedDate
        )
    }

    func testErasedPendingInkCannotClaimTheMetadataOfTheNextStroke() throws {
        let firstLayerID = LayerID()
        let secondLayerID = LayerID()
        let erasedStroke = PencilStrokeTestFixture.blackPenStroke(randomSeed: 611)
        let survivingStroke = PencilStrokeTestFixture.blackStroke(randomSeed: 612)
        let penInput = PencilStrokeInput(
            configuration: .favoriteOne,
            layerID: firstLayerID,
            createdAt: DomainFixtures.fixedDate
        )
        let markerInput = PencilStrokeInput(
            configuration: ToolConfiguration(tool: .marker, width: .thick, color: .black),
            layerID: secondLayerID,
            createdAt: DomainFixtures.fixedDate
        )
        let eraserInput = PencilStrokeInput(
            configuration: ToolConfiguration(tool: .eraser, width: .medium, color: .black),
            layerID: firstLayerID,
            createdAt: DomainFixtures.fixedDate
        )

        let result = try XCTUnwrap(PencilDrawingReconciler.reconcile(
            drawing: PKDrawing(strokes: [survivingStroke]),
            committedDrawing: PKDrawing(),
            baseline: [],
            contacts: [
                PencilContactSnapshot(
                    input: penInput,
                    appendedStrokeKeys: [PencilNativeStrokeKey(erasedStroke)],
                    endingStrokeCount: 1
                ),
                PencilContactSnapshot(input: eraserInput, appendedStrokeKeys: [], endingStrokeCount: 0),
                PencilContactSnapshot(
                    input: markerInput,
                    appendedStrokeKeys: [PencilNativeStrokeKey(survivingStroke)],
                    endingStrokeCount: 1
                )
            ],
            fallbackInput: markerInput
        ))

        XCTAssertEqual(result.completedStrokes.count, 1)
        XCTAssertEqual(result.completedStrokes[0].stroke.layerID, secondLayerID)
        XCTAssertEqual(result.completedStrokes[0].stroke.style.instrument, .marker)
    }

    func testUnchangedDrawingNeedsNoModelPublication() throws {
        let layerID = LayerID()
        let nativeStroke = PencilStrokeTestFixture.blackStroke(randomSeed: 620)
        let drawing = PKDrawing(strokes: [nativeStroke])
        let baseline = PencilDrawingReconciler.edit(
            drawing: drawing,
            baseline: [],
            activeLayerID: layerID,
            configuration: .favoriteOne,
            createdAt: DomainFixtures.fixedDate
        ).after
        let input = PencilStrokeInput(
            configuration: .favoriteOne,
            layerID: layerID,
            createdAt: DomainFixtures.fixedDate
        )

        let result = try XCTUnwrap(PencilDrawingReconciler.reconcile(
            drawing: drawing,
            committedDrawing: drawing,
            baseline: baseline,
            contacts: [],
            fallbackInput: input
        ))

        XCTAssertEqual(result.publication, .none)
    }

    func testFullReconciliationStopsWhileIndexingALargeBaseline() throws {
        let layerID = LayerID()
        let nativeStrokes = (0..<200).map { index in
            PencilStrokeTestFixture.pencilStroke(
                color: .black,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                randomSeed: 777,
                transform: CGAffineTransform(translationX: CGFloat(index * 8), y: 0)
            )
        }
        let baseline = PencilDrawingReconciler.edit(
            drawing: PKDrawing(strokes: nativeStrokes),
            baseline: [],
            activeLayerID: layerID,
            configuration: .favoriteOne,
            pencilRoll: 0,
            createdAt: DomainFixtures.fixedDate
        ).after
        var cancellationChecks = 0

        let result = PencilDrawingReconciler.reconcile(
            drawing: PKDrawing(),
            committedDrawing: nil,
            baseline: baseline,
            contacts: [],
            fallbackInput: PencilStrokeInput(
                configuration: ToolConfiguration(
                    tool: .eraser,
                    width: .medium,
                    color: .black,
                    eraserMode: .stroke
                ),
                layerID: layerID,
                createdAt: DomainFixtures.fixedDate
            ),
            shouldCancel: {
                cancellationChecks += 1
                return cancellationChecks > 1
            }
        )

        XCTAssertNil(result)
        XCTAssertEqual(cancellationChecks, 2)
    }

    func testFullReconciliationStopsWhileMatchingRepeatedSeeds() throws {
        let layerID = LayerID()
        let nativeStrokes = (0..<200).map { index in
            PencilStrokeTestFixture.pencilStroke(
                color: .black,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                randomSeed: 888,
                transform: CGAffineTransform(translationX: CGFloat(index * 8), y: 0)
            )
        }
        let baseline = PencilDrawingReconciler.edit(
            drawing: PKDrawing(strokes: nativeStrokes),
            baseline: [],
            activeLayerID: layerID,
            configuration: .favoriteOne,
            pencilRoll: 0,
            createdAt: DomainFixtures.fixedDate
        ).after
        var cancellationChecks = 0
        let cancellationLimit = baseline.count + 3

        let result = PencilDrawingReconciler.reconcile(
            drawing: PKDrawing(strokes: [nativeStrokes[0]]),
            committedDrawing: nil,
            baseline: baseline,
            contacts: [],
            fallbackInput: PencilStrokeInput(
                configuration: .favoriteOne,
                layerID: layerID,
                createdAt: DomainFixtures.fixedDate
            ),
            shouldCancel: {
                cancellationChecks += 1
                return cancellationChecks > cancellationLimit
            }
        )

        XCTAssertNil(result)
        XCTAssertEqual(cancellationChecks, cancellationLimit + 1)
    }
}
