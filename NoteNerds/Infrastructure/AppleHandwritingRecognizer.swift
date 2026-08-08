import CoreGraphics
import Foundation
import Vision

enum AppleHandwritingRecognitionError: Error, Equatable {
    case emptyInput
    case imageCreationFailed
    case noTextRecognized
}

actor AppleHandwritingRecognizer: HandwritingRecognizer {
    private let recognizerVersion = "Vision-1"

    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        guard strokes.contains(where: { !$0.samples.isEmpty }) else {
            throw AppleHandwritingRecognitionError.emptyInput
        }
        let bounds = CanvasRect.enclosing(strokes.flatMap { $0.samples.map(\.point) })
        let image = try render(strokes: strokes, bounds: bounds)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined(separator: "\n")
        guard !text.isEmpty else { throw AppleHandwritingRecognitionError.noTextRecognized }
        let confidence = candidates.reduce(0.0) { $0 + Double($1.confidence) } / Double(candidates.count)
        return HandwritingRecognitionResult(
            text: text,
            confidence: confidence,
            bounds: bounds,
            sourceStrokeIDs: Set(strokes.map(\.id)),
            recognizerVersion: recognizerVersion
        )
    }

    private func render(strokes: [Stroke], bounds: CanvasRect) throws -> CGImage {
        let padding = 24.0
        let contentWidth = max(bounds.size.width, 1)
        let contentHeight = max(bounds.size.height, 1)
        let scale = min(3.0, 2048.0 / max(contentWidth, contentHeight))
        let width = max(Int(ceil((contentWidth + padding * 2) * scale)), 1)
        let height = max(Int(ceil((contentHeight + padding * 2) * scale)), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AppleHandwritingRecognitionError.imageCreationFailed
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.samples.first else { continue }
            context.setLineWidth(max(stroke.style.width * scale, 2))
            context.move(to: imagePoint(first.point, bounds: bounds, padding: padding, scale: scale))
            for sample in stroke.samples.dropFirst() {
                context.addLine(to: imagePoint(sample.point, bounds: bounds, padding: padding, scale: scale))
            }
            context.strokePath()
        }
        guard let image = context.makeImage() else {
            throw AppleHandwritingRecognitionError.imageCreationFailed
        }
        return image
    }

    private func imagePoint(
        _ point: CanvasPoint,
        bounds: CanvasRect,
        padding: Double,
        scale: Double
    ) -> CGPoint {
        CGPoint(
            x: (point.x - bounds.minX + padding) * scale,
            y: (point.y - bounds.minY + padding) * scale
        )
    }
}
