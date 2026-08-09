import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class PencilStrokePersistenceBehaviorTests: XCTestCase {
    func testMarkerHighlightMarkerRetainsPencilKitRenderingAfterReopen() throws {
        let sequence = PencilStrokeTestFixture.markerHighlightMarkerSequence()
        let completedStrokes = PencilStrokeTestFixture.capture(
            sequence.pencilStrokes,
            configurations: sequence.configurations
        )
        let reopenedStrokes = try PencilStrokeTestFixture.roundTrippedStrokes(
            in: notebook(with: completedStrokes)
        )

        try assertRenderingMatches(
            original: sequence.pencilStrokes,
            reopened: PencilCanvasRenderer.drawing(from: reopenedStrokes).strokes
        )
    }

    func testLegacyStrokeWithoutNativeArchiveRendersConsistentlyAfterSerialization() throws {
        let legacyStroke = canonicalStroke(sampleCount: 12, xOffset: 40)
        let reopenedStroke = try XCTUnwrap(
            PencilStrokeTestFixture.roundTrippedStrokes(
                in: notebook(with: [legacyStroke])
            ).first
        )
        let firstReopen = try XCTUnwrap(
            PencilCanvasRenderer.drawing(from: [legacyStroke]).strokes.first
        )
        let secondReopen = try XCTUnwrap(
            PencilCanvasRenderer.drawing(from: [reopenedStroke]).strokes.first
        )

        XCTAssertNil(reopenedStroke.pencilKitArchive)
        XCTAssertEqual(firstReopen.randomSeed, secondReopen.randomSeed)
        XCTAssertEqual(firstReopen.renderBounds, secondReopen.renderBounds)
    }

    func testCanonicalEditDoesNotRestoreAnOlderArchivedStroke() throws {
        let sequence = PencilStrokeTestFixture.markerHighlightMarkerSequence()
        var edited = try XCTUnwrap(PencilStrokeTestFixture.capture(
            [sequence.pencilStrokes[0]],
            configurations: [sequence.configurations[0]]
        ).first)
        let originalBounds = try XCTUnwrap(
            PencilCanvasRenderer.drawing(from: [edited]).strokes.first
        ).renderBounds
        edited.samples = edited.samples.map { sample in
            var moved = sample
            moved.point.x += 100
            return moved
        }

        let reopened = try XCTUnwrap(PencilCanvasRenderer.drawing(from: [edited]).strokes.first)

        XCTAssertEqual(reopened.renderBounds, originalBounds.offsetBy(dx: 100, dy: 0))
    }

    func testLassoTransformRetainsExactSelectedAndNearbyWritingAfterReopen() throws {
        let setup = lassoSetup()
        let result = PencilCanvasSelectionTransform.applying(
            objectIDs: [setup.selected.objectID],
            transform: setup.transform,
            center: setup.center,
            to: setup.drawing,
            canonicalStrokes: [setup.selected, setup.nearby]
        )

        XCTAssertEqual(
            result.drawing.strokes[0].path.map(\.location),
            setup.drawing.strokes[0].path.map(\.location)
        )
        XCTAssertEqual(
            result.drawing.strokes[1].path.map(\.location),
            setup.drawing.strokes[1].path.map(\.location)
        )
        XCTAssertEqual(result.canonicalStrokes[1], setup.nearby)

        let reopened = try reopenedDrawing(after: result, setup: setup)

        assertStroke(reopened.strokes[0], equals: result.drawing.strokes[0])
        assertStroke(reopened.strokes[1], equals: result.drawing.strokes[1])
    }

    private func lassoSetup() -> LassoSetup {
        let sequence = PencilStrokeTestFixture.markerHighlightMarkerSequence()
        let captured = PencilStrokeTestFixture.capture(
            [sequence.pencilStrokes[0], sequence.pencilStrokes[2]],
            configurations: [sequence.configurations[0], sequence.configurations[2]]
        )
        let transform = SelectionTransform(
            scaleX: 0.75,
            scaleY: 1.2,
            rotation: 0.15,
            translation: CanvasPoint(x: 40, y: 25)
        )
        return LassoSetup(
            selected: captured[0],
            nearby: captured[1],
            drawing: PencilCanvasRenderer.drawing(from: captured),
            transform: transform,
            center: CanvasPoint(x: 20, y: 20)
        )
    }

    private func reopenedDrawing(
        after result: PencilCanvasSelectionTransformResult,
        setup: LassoSetup
    ) throws -> PKDrawing {
        var notebook = notebook(with: [setup.selected, setup.nearby])
        let operation = try DocumentOperation.transformObjects(
            in: notebook,
            canvasID: notebook.canvases[0].id,
            objectIDs: [setup.selected.objectID],
            transform: setup.transform,
            center: setup.center,
            strokeReplacements: [result.canonicalStrokes[0]]
        )
        try operation.apply(to: &notebook)
        return PencilCanvasRenderer.drawing(
            from: try PencilStrokeTestFixture.roundTrippedStrokes(in: notebook)
        )
    }

    private func notebook(with strokes: [Stroke]) -> Notebook {
        var notebook = DomainFixtures.notebook()
        notebook.canvases[0].layers[0].objects = strokes.map(CanvasObject.stroke)
        return notebook
    }

    private func canonicalStroke(sampleCount: Int, xOffset: Double) -> Stroke {
        var result = DomainFixtures.stroke()
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

    private func assertRenderingMatches(original: [PKStroke], reopened: [PKStroke]) throws {
        XCTAssertEqual(reopened.count, original.count)
        for (originalStroke, reopenedStroke) in zip(original, reopened) {
            assertStroke(reopenedStroke, equals: originalStroke)
            XCTAssertEqual(reopenedStroke.ink.inkType, originalStroke.ink.inkType)
            assertColor(reopenedStroke.ink.color, equals: originalStroke.ink.color)
        }
        let bounds = original.map(\.renderBounds).reduce(CGRect.null) { $0.union($1) }
            .insetBy(dx: -8, dy: -8)
        let originalPixels = try rgbaPixelData(
            from: PKDrawing(strokes: original).image(from: bounds, scale: 2)
        )
        let reopenedPixels = try rgbaPixelData(
            from: PKDrawing(strokes: reopened).image(from: bounds, scale: 2)
        )
        XCTAssertEqual(reopenedPixels.count, originalPixels.count)
        let differentChannels = zip(reopenedPixels, originalPixels).filter(!=).count
        let largestDifference = zip(reopenedPixels, originalPixels)
            .map { abs(Int($0) - Int($1)) }
            .max() ?? 0
        let differentChannelRatio = Double(differentChannels) / Double(originalPixels.count)
        XCTAssertLessThanOrEqual(differentChannelRatio, 0.03)
        XCTAssertLessThanOrEqual(largestDifference, 8)
    }

    private func assertStroke(_ actual: PKStroke, equals expected: PKStroke) {
        XCTAssertEqual(actual.randomSeed, expected.randomSeed)
        assertTransform(actual.transform, equals: expected.transform)
        XCTAssertEqual(actual.renderBounds, expected.renderBounds)
    }

    private func assertTransform(_ actual: CGAffineTransform, equals expected: CGAffineTransform) {
        XCTAssertEqual(actual.a, expected.a, accuracy: 0.000_1)
        XCTAssertEqual(actual.b, expected.b, accuracy: 0.000_1)
        XCTAssertEqual(actual.c, expected.c, accuracy: 0.000_1)
        XCTAssertEqual(actual.d, expected.d, accuracy: 0.000_1)
        XCTAssertEqual(actual.tx, expected.tx, accuracy: 0.000_1)
        XCTAssertEqual(actual.ty, expected.ty, accuracy: 0.000_1)
    }

    private func assertColor(_ actual: UIColor, equals expected: UIColor) {
        let actualComponents = actual.rgbaComponents
        let expectedComponents = expected.rgbaComponents
        XCTAssertEqual(actualComponents.red, expectedComponents.red, accuracy: 0.000_01)
        XCTAssertEqual(actualComponents.green, expectedComponents.green, accuracy: 0.000_01)
        XCTAssertEqual(actualComponents.blue, expectedComponents.blue, accuracy: 0.000_01)
        XCTAssertEqual(actualComponents.alpha, expectedComponents.alpha, accuracy: 0.000_01)
    }

    private func rgbaPixelData(from image: UIImage) throws -> Data {
        let cgImage = try XCTUnwrap(image.cgImage)
        let bytesPerRow = cgImage.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * cgImage.height)
        let context = try XCTUnwrap(CGContext(
            data: &bytes,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return Data(bytes)
    }
}

private struct LassoSetup {
    let selected: Stroke
    let nearby: Stroke
    let drawing: PKDrawing
    let transform: SelectionTransform
    let center: CanvasPoint
}

private struct RGBAComponents {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
}

private extension UIColor {
    var rgbaComponents: RGBAComponents {
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        var alpha = CGFloat.zero
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBAComponents(red: red, green: green, blue: blue, alpha: alpha)
    }
}
