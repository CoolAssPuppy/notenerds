import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class PencilStrokeClipboardBehaviorTests: XCTestCase {
    func testPastedMaskedStrokeKeepsExactRenderingAfterReopen() throws {
        let source = try archivedMaskedStroke()
        let offset = CanvasPoint(x: 24, y: 24)
        let pastedObjects = SelectionClipboardPayload(objects: [.stroke(source.canonical)])
            .pasted(offset: offset)
        let pastedStroke = try XCTUnwrap(pastedObjects.first?.strokeValue)
        let reopenedStroke = try XCTUnwrap(roundTripped([pastedStroke]).first)
        let reopened = try XCTUnwrap(
            PencilCanvasRenderer.drawing(from: [reopenedStroke]).strokes.first
        )
        var expected = source.pencil
        expected.transform = source.pencil.transform.concatenating(
            CGAffineTransform(translationX: offset.x, y: offset.y)
        )

        XCTAssertNotEqual(pastedStroke.id, source.canonical.id)
        XCTAssertNotNil(reopened.mask)
        XCTAssertEqual(reopened.maskedPathRanges, expected.maskedPathRanges)
        assertStroke(reopened, equals: expected)
        try assertAlphaPixels(reopened: reopened, expected: expected)
    }

    func testErasingOriginalAfterPasteKeepsTheDuplicateIdentity() throws {
        let source = try archivedMaskedStroke()
        let pastedStroke = try XCTUnwrap(
            SelectionClipboardPayload(objects: [.stroke(source.canonical)])
                .pasted(offset: CanvasPoint(x: 24, y: 24))
                .first?.strokeValue
        )
        let canvasView = PKCanvasView()
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [pastedStroke])
        var changedStrokes: [Stroke] = []
        let coordinator = PencilStrokeTestFixture.coordinator(
            onStrokesCompleted: { _ in },
            onDrawingChanged: { changedStrokes = $0 }
        )
        coordinator.knownStrokeCount = 2
        coordinator.canonicalStrokes = [source.canonical, pastedStroke]

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        XCTAssertEqual(changedStrokes.count, 1)
        XCTAssertEqual(changedStrokes.first?.id, pastedStroke.id)
        XCTAssertEqual(changedStrokes.first?.style, pastedStroke.style)
    }

    private func archivedMaskedStroke() throws -> (canonical: Stroke, pencil: PKStroke) {
        let color = InkColor(red: 0.55, green: 0.16, blue: 0.82, alpha: 1)
        let pencil = pencilStroke(
            color: color,
            mask: UIBezierPath(rect: CGRect(x: 118, y: 198, width: 24, height: 28))
        )
        let canvasView = PKCanvasView()
        var completedStrokes: [Stroke] = []
        let captureCoordinator = PencilStrokeTestFixture.coordinator {
            completedStrokes.append(contentsOf: $0)
        }
        captureCoordinator.configuration = ToolConfiguration(
            tool: .marker,
            width: .medium,
            color: color
        )
        captureCoordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [pencil])
        captureCoordinator.canvasViewDidEndUsingTool(canvasView)
        return (try XCTUnwrap(completedStrokes.first), pencil)
    }

    private func pencilStroke(color: InkColor, mask: UIBezierPath) -> PKStroke {
        let points = (0..<10).map { index in
            let scalar = CGFloat(index)
            return PKStrokePoint(
                location: CGPoint(x: 100 + scalar * 8, y: 200 + scalar * 4),
                timeOffset: Double(index) * 0.01,
                size: CGSize(width: 5, height: 8),
                opacity: 0.92,
                force: 0.4,
                azimuth: 1.1,
                altitude: 0.7
            )
        }
        return PKStroke(
            ink: PKInk(.marker, color: UIColor(color)),
            path: PKStrokePath(controlPoints: points, creationDate: DomainFixtures.fixedDate),
            transform: CGAffineTransform(a: 0.3, b: 0, c: 0, d: 0.3, tx: 160, ty: 240),
            mask: mask,
            randomSeed: 77
        )
    }

    private func roundTripped(_ strokes: [Stroke]) throws -> [Stroke] {
        var notebook = DomainFixtures.notebook()
        notebook.canvases[0].layers[0].objects = strokes.map(CanvasObject.stroke)
        return try PencilStrokeTestFixture.roundTrippedStrokes(in: notebook)
    }

    private func assertStroke(_ actual: PKStroke, equals expected: PKStroke) {
        XCTAssertEqual(actual.randomSeed, expected.randomSeed)
        XCTAssertEqual(actual.renderBounds, expected.renderBounds)
        XCTAssertEqual(actual.transform.a, expected.transform.a, accuracy: 0.000_01)
        XCTAssertEqual(actual.transform.d, expected.transform.d, accuracy: 0.000_01)
        XCTAssertEqual(actual.transform.tx, expected.transform.tx, accuracy: 0.000_01)
        XCTAssertEqual(actual.transform.ty, expected.transform.ty, accuracy: 0.000_01)
    }

    private func assertAlphaPixels(reopened: PKStroke, expected: PKStroke) throws {
        let bounds = expected.renderBounds.insetBy(dx: -8, dy: -8)
        let reopenedData = try alphaData(
            from: PKDrawing(strokes: [reopened]).image(from: bounds, scale: 2)
        )
        let expectedData = try alphaData(
            from: PKDrawing(strokes: [expected]).image(from: bounds, scale: 2)
        )
        XCTAssertEqual(reopenedData.count, expectedData.count)
        let differentPixels = zip(reopenedData, expectedData).filter(!=).count
        let largestDifference = zip(reopenedData, expectedData)
            .map { abs(Int($0) - Int($1)) }
            .max() ?? 0
        XCTAssertLessThanOrEqual(differentPixels, 8)
        XCTAssertLessThanOrEqual(largestDifference, 1)
    }

    private func alphaData(from image: UIImage) throws -> Data {
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
        return Data(stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] })
    }
}
