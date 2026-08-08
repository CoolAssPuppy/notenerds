import Foundation

struct HandwritingRecognitionResult: Codable, Hashable, Sendable {
    var text: String
    var confidence: Double
    var bounds: CanvasRect
    var sourceStrokeIDs: Set<StrokeID>
    var recognizerVersion: String
}

protocol HandwritingRecognizer: Sendable {
    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult
}

struct PersistedHandwritingRecognition: Codable, Hashable, Sendable {
    let result: HandwritingRecognitionResult
    private let sourceFingerprints: [StrokeID: UInt64]

    init(result: HandwritingRecognitionResult, sourceStrokes: [Stroke]) {
        self.result = result
        sourceFingerprints = Dictionary(uniqueKeysWithValues: sourceStrokes.map { ($0.id, $0.recognitionFingerprint) })
    }

    func isStale(sourceStrokes: [Stroke], recognizerVersion: String) -> Bool {
        guard result.recognizerVersion == recognizerVersion else { return true }
        let current = Dictionary(uniqueKeysWithValues: sourceStrokes.map { ($0.id, $0.recognitionFingerprint) })
        return current != sourceFingerprints
    }
}

private extension Stroke {
    var recognitionFingerprint: UInt64 {
        var fingerprint: UInt64 = 14_695_981_039_346_656_037
        func mix(_ value: UInt64) {
            fingerprint ^= value
            fingerprint &*= 1_099_511_628_211
        }
        mix(style.width.bitPattern)
        mix(style.color.red.bitPattern)
        mix(style.color.green.bitPattern)
        mix(style.color.blue.bitPattern)
        mix(style.color.alpha.bitPattern)
        for sample in samples {
            mix(sample.point.x.bitPattern)
            mix(sample.point.y.bitPattern)
            mix(sample.pressure.bitPattern)
            mix(sample.altitude.bitPattern)
            mix(sample.azimuth.bitPattern)
            mix(sample.roll.bitPattern)
            mix(sample.timeOffset.bitPattern)
        }
        return fingerprint
    }
}
