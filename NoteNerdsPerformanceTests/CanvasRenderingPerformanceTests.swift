import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

/// Bounds the cost of turning a saved page of ink back into a PencilKit
/// drawing.
///
/// Opening a canvas, turning a page, and undoing all rebuild the drawing from
/// every saved stroke on the main thread. Each stroke used to be re-hashed over
/// every sample and unarchived again on each pass, so a full page cost time
/// proportional to its own size on every one of those actions.
final class CanvasRenderingPerformanceTests: XCTestCase {
    private let strokeCount = 400
    private let sampleCount = 300

    func testRenderingAFullPageOfSavedInkStaysUnderATenthOfASecond() {
        let strokes = archivedStrokes()
        let clock = ContinuousClock()

        let start = clock.now
        let drawing = PencilCanvasRenderer.drawing(from: strokes)
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(drawing.strokes.count, strokeCount)
        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    func testRepeatedRenderingOfTheSameInkDoesNotRepeatTheDecodeCost() {
        let strokes = archivedStrokes()
        let clock = ContinuousClock()
        _ = PencilCanvasRenderer.drawing(from: strokes)

        let start = clock.now
        for _ in 0..<5 {
            _ = PencilCanvasRenderer.drawing(from: strokes)
        }
        let elapsed = start.duration(to: clock.now)

        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    private func archivedStrokes() -> [Stroke] {
        (0..<strokeCount).map { index in
            let pencilStroke = pencilStroke(seed: UInt32(index + 1))
            let stroke = Stroke(
                id: StrokeID(),
                layerID: LayerID(),
                samples: samples(),
                style: StrokeStyle(instrument: .ballpoint, width: 2, color: .black),
                createdAt: Date(timeIntervalSince1970: 1_750_000_000),
                pencilKitArchive: nil
            )
            return PencilKitStrokeArchiveCodec.preserving(pencilStroke, in: stroke)
        }
    }

    private func samples() -> [StrokeSample] {
        (0..<sampleCount).map { index in
            let scalar = Double(index)
            return StrokeSample(
                point: CanvasPoint(x: 100 + scalar, y: 200 + scalar * 0.5),
                pressure: 0.5,
                altitude: 0.7,
                azimuth: 1.1,
                roll: 0,
                timeOffset: scalar * 0.008
            )
        }
    }

    private func pencilStroke(seed: UInt32) -> PKStroke {
        let points = (0..<sampleCount).map { index in
            let scalar = CGFloat(index)
            return PKStrokePoint(
                location: CGPoint(x: 100 + scalar, y: 200 + scalar * 0.5),
                timeOffset: Double(index) * 0.008,
                size: CGSize(width: 2, height: 2),
                opacity: 1,
                force: 0.5,
                azimuth: 1.1,
                altitude: 0.7
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_750_000_000)),
            randomSeed: seed
        )
    }
}
