import Foundation

struct HandwritingRecognitionResult: Codable, Hashable, Sendable {
    var text: String
    var confidence: Double
    var bounds: CanvasRect
    var sourceStrokeIDs: Set<StrokeID>
    var recognizerVersion: String
}

protocol HandwritingRecognizer: Sendable {
    var recognizerVersion: String { get }
    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult
}

extension HandwritingRecognizer {
    var recognizerVersion: String { "test" }
}

struct PersistedHandwritingRecognition: Codable, Hashable, Sendable {
    let result: HandwritingRecognitionResult
    private let sourceFingerprints: [StrokeID: UInt64]

    init(result: HandwritingRecognitionResult, sourceStrokes: [Stroke]) {
        self.result = result
        var fingerprints: [StrokeID: UInt64] = [:]
        for stroke in sourceStrokes {
            fingerprints[stroke.id] = stroke.recognitionFingerprint
        }
        sourceFingerprints = fingerprints
    }

    func isStale(sourceStrokes: [Stroke], recognizerVersion: String) -> Bool {
        guard result.recognizerVersion == recognizerVersion else { return true }
        guard sourceStrokes.count == sourceFingerprints.count else { return true }
        var current: [StrokeID: UInt64] = [:]
        for stroke in sourceStrokes {
            guard current[stroke.id] == nil else { return true }
            current[stroke.id] = stroke.recognitionFingerprint
        }
        return current != sourceFingerprints
    }

    var sourceStrokeIDs: Set<StrokeID> { Set(sourceFingerprints.keys) }
}

extension Stroke {
    var isHandwritingRecognitionCandidate: Bool {
        style.instrument != .highlighter
    }

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
