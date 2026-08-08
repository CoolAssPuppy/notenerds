import SwiftUI

struct CanvasContentThumbnail: View {
    let canvas: Canvas

    var body: some View {
        ZStack {
            PaperPreview(paperType: canvas.template)
            SwiftUI.Canvas { context, size in
                let sourceBounds = canvas.contentBounds ?? CanvasRect(x: 0, y: 0, width: 400, height: 300)
                let transform = thumbnailTransform(source: sourceBounds, destination: size)
                for object in canvas.layers.filter(\.isVisible).flatMap(\.objects) {
                    draw(object, transform: transform, context: &context)
                }
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.secondary.opacity(0.2))
        }
    }

    private func thumbnailTransform(source: CanvasRect, destination: CGSize) -> (CanvasPoint) -> CGPoint {
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

    private func draw(
        _ object: CanvasObject,
        transform: (CanvasPoint) -> CGPoint,
        context: inout GraphicsContext
    ) {
        switch object {
        case let .stroke(stroke):
            drawPath(stroke.samples.map(\.point), color: stroke.style.color, transform: transform, context: &context)
        case let .shape(shape):
            drawPath(shape.points, color: shape.style.color, transform: transform, context: &context)
        case let .text(text):
            context.draw(Text(text.text).font(.caption2).foregroundStyle(.primary), at: transform(text.frame.origin))
        case let .image(image):
            drawPlaceholder(image.frame, symbol: "photo", transform: transform, context: &context)
        case let .pdf(pdf):
            drawPlaceholder(pdf.frame, symbol: "doc", transform: transform, context: &context)
        }
    }

    private func drawPath(
        _ points: [CanvasPoint],
        color: InkColor,
        transform: (CanvasPoint) -> CGPoint,
        context: inout GraphicsContext
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: transform(first))
        for point in points.dropFirst() { path.addLine(to: transform(point)) }
        context.stroke(path, with: .color(color.swiftUIColor), lineWidth: 1.5)
    }

    private func drawPlaceholder(
        _ frame: CanvasRect,
        symbol: String,
        transform: (CanvasPoint) -> CGPoint,
        context: inout GraphicsContext
    ) {
        context.draw(Image(systemName: symbol), at: transform(frame.origin))
    }
}

private extension InkColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
