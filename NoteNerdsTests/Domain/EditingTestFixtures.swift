import Foundation
@testable import NoteNerds

func recognition(text: String, x: Double, y: Double) -> HandwritingRecognitionResult {
    HandwritingRecognitionResult(
        text: text,
        confidence: 0.9,
        bounds: CanvasRect(x: x, y: y, width: 60, height: 30),
        sourceStrokeIDs: [],
        recognizerVersion: "test"
    )
}

func timedSample(x: Double, y: Double, time: TimeInterval) -> StrokeSample {
    StrokeSample(
        point: CanvasPoint(x: x, y: y),
        pressure: 0.5,
        altitude: 1,
        azimuth: 0,
        roll: 0,
        timeOffset: time
    )
}
