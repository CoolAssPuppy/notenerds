import SwiftUI
import UIKit

enum CanvasThumbnailCache {
    private static let cache = Cache()

    static func image(for canvas: Canvas, size: CGSize) -> UIImage {
        let key = cacheKey(for: canvas, size: size)
        if let cached = cache.image(for: key) { return cached }
        let rendered = CanvasThumbnailRenderer.image(for: canvas, size: size)
        cache.store(rendered, for: key)
        return rendered
    }

    private static func cacheKey(for canvas: Canvas, size: CGSize) -> NSString {
        let stamp = canvas.modifiedAt.timeIntervalSince1970
        return "\(canvas.id.rawValue.uuidString)-\(stamp)-\(Int(size.width))x\(Int(size.height))" as NSString
    }

    private final class Cache: @unchecked Sendable {
        private let entries = NSCache<NSString, UIImage>()

        func image(for key: NSString) -> UIImage? {
            entries.object(forKey: key)
        }

        func store(_ image: UIImage, for key: NSString) {
            entries.setObject(image, forKey: key)
        }
    }
}

enum CanvasThumbnailRenderer {
    static func image(for canvas: Canvas, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let sourceBounds = canvas.contentBounds ?? CanvasViewport.defaultVisibleBounds
            let transform = thumbnailTransform(source: sourceBounds, destination: size)
            for object in canvas.layers.filter(\.isVisible).flatMap(\.objects) {
                draw(object, transform: transform, in: context.cgContext)
            }
        }
    }

    private static func thumbnailTransform(
        source: CanvasRect,
        destination: CGSize
    ) -> (CanvasPoint) -> CGPoint {
        let width = max(source.size.width, 1)
        let height = max(source.size.height, 1)
        let scale = min((destination.width - 24) / width, (destination.height - 24) / height)
        return { point in
            CGPoint(
                x: 12 + (point.x - source.minX) * scale,
                y: 12 + (point.y - source.minY) * scale
            )
        }
    }

    private static func draw(
        _ object: CanvasObject,
        transform: (CanvasPoint) -> CGPoint,
        in context: CGContext
    ) {
        switch object {
        case let .stroke(stroke):
            drawPath(stroke.samples.map(\.point), color: stroke.style.color, transform: transform, in: context)
        case let .shape(shape):
            drawPath(shape.points, color: shape.style.color, transform: transform, in: context)
        case let .text(text):
            let point = transform(text.frame.origin)
            (text.text as NSString).draw(
                at: point,
                withAttributes: [.font: UIFont.preferredFont(forTextStyle: .caption2)]
            )
        case let .image(image):
            drawPlaceholder(at: transform(image.frame.origin), symbol: "photo", in: context)
        case let .pdf(pdf):
            drawPlaceholder(at: transform(pdf.frame.origin), symbol: "doc", in: context)
        }
    }

    private static func drawPath(
        _ points: [CanvasPoint],
        color: InkColor,
        transform: (CanvasPoint) -> CGPoint,
        in context: CGContext
    ) {
        guard let first = points.first else { return }
        context.setStrokeColor(
            UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha).cgColor
        )
        context.setLineWidth(1.5)
        context.beginPath()
        context.move(to: transform(first))
        for point in points.dropFirst() { context.addLine(to: transform(point)) }
        context.strokePath()
    }

    private static func drawPlaceholder(at point: CGPoint, symbol: String, in context: CGContext) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        guard let image = UIImage(systemName: symbol, withConfiguration: configuration) else { return }
        image.draw(at: point)
    }
}
