import Foundation

struct HandwritingTextLayout: Sendable {
    func textBlock(
        from recognitions: [HandwritingRecognitionResult],
        layerID: LayerID,
        fontSize: Double = 17
    ) -> TextBlock {
        let sorted = recognitions.sorted { first, second in
            if abs(first.bounds.minY - second.bounds.minY) <= lineThreshold(first, second) {
                return first.bounds.minX < second.bounds.minX
            }
            return first.bounds.minY < second.bounds.minY
        }
        var lines: [[HandwritingRecognitionResult]] = []
        for recognition in sorted {
            if let previous = lines.last?.first,
               abs(previous.bounds.minY - recognition.bounds.minY) <= lineThreshold(previous, recognition) {
                lines[lines.count - 1].append(recognition)
            } else {
                lines.append([recognition])
            }
        }
        let text = lines.map { line in
            line.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
        let points = recognitions.flatMap { recognition in
            [
                recognition.bounds.origin,
                CanvasPoint(x: recognition.bounds.maxX, y: recognition.bounds.maxY)
            ]
        }
        return TextBlock(
            id: ObjectID(),
            layerID: layerID,
            text: text,
            frame: CanvasRect.enclosing(points),
            fontSize: fontSize,
            alignment: .left
        )
    }

    private func lineThreshold(
        _ first: HandwritingRecognitionResult,
        _ second: HandwritingRecognitionResult
    ) -> Double {
        max(first.bounds.size.height, second.bounds.size.height) * 0.6
    }
}
