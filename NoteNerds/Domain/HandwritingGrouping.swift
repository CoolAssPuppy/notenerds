import Foundation

struct HandwritingGroupBuilder: Sendable {
    func groups(from strokes: [Stroke]) -> [[Stroke]] {
        guard let first = strokes.first else { return [] }
        return strokes.dropFirst().reduce(into: [[first]]) { groups, stroke in
            guard let previous = groups[groups.count - 1].last else {
                groups.append([stroke])
                return
            }
            if belongsTogether(previous, stroke) {
                groups[groups.count - 1].append(stroke)
            } else {
                groups.append([stroke])
            }
        }
    }

    private func belongsTogether(_ first: Stroke, _ second: Stroke) -> Bool {
        let horizontalGap = max(0, second.bounds.minX - first.bounds.maxX)
        let verticalDistance = abs(second.bounds.minY - first.bounds.minY)
        let lineHeight = max(max(first.bounds.size.height, second.bounds.size.height), 20)
        return horizontalGap <= lineHeight * 2.5 && verticalDistance <= lineHeight * 1.2
    }
}

actor HandwritingRecognitionCoordinator {
    private let recognizer: any HandwritingRecognizer
    private let minimumConfidence: Double
    nonisolated let recognizerVersion: String

    init(recognizer: any HandwritingRecognizer, minimumConfidence: Double = 0.5) {
        self.recognizer = recognizer
        self.minimumConfidence = minimumConfidence
        recognizerVersion = recognizer.recognizerVersion
    }

    func recognizeSafely(strokes: [Stroke]) async -> HandwritingRecognitionResult? {
        do {
            let result = try await recognizer.recognize(strokes: strokes)
            return result.confidence >= minimumConfidence ? result : nil
        } catch {
            return nil
        }
    }
}
