import UIKit

enum PNGExportError: Error, Equatable {
    case invalidRegion
    case encodingFailed
}

@MainActor
struct CanvasPNGExporter {
    func export(_ canvas: Canvas, region: CanvasRect, scale: Double = 1) throws -> Data {
        guard region.size.width > 0, region.size.height > 0, scale > 0 else {
            throw PNGExportError.invalidRegion
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: region.size.width * scale, height: region.size.height * scale)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -region.minX, y: -region.minY)
            PaperRenderer.draw(canvas.template, in: context, bounds: region.cgRect)
            for layer in canvas.layers where layer.isVisible {
                for object in layer.objects where object.bounds.intersects(region) {
                    draw(object, in: context)
                }
            }
        }
        guard let data = image.pngData() else { throw PNGExportError.encodingFailed }
        return data
    }

    private func draw(_ object: CanvasObject, in context: CGContext) {
        switch object {
        case let .stroke(stroke):
            guard let first = stroke.samples.first else { return }
            context.setStrokeColor(stroke.style.color.cgColor)
            context.setLineWidth(stroke.style.width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: first.point.cgPoint)
            for sample in stroke.samples.dropFirst() { context.addLine(to: sample.point.cgPoint) }
            context.strokePath()
        case let .shape(shape):
            guard let first = shape.points.first else { return }
            context.setStrokeColor(shape.style.color.cgColor)
            context.setLineWidth(shape.style.width)
            context.move(to: first.cgPoint)
            for point in shape.points.dropFirst() { context.addLine(to: point.cgPoint) }
            context.strokePath()
        case let .text(text):
            NSString(string: text.text).draw(
                in: text.frame.cgRect,
                withAttributes: [.font: UIFont.systemFont(ofSize: text.fontSize), .foregroundColor: UIColor.label]
            )
        case let .image(image):
            context.setStrokeColor(UIColor.systemGray3.cgColor)
            context.stroke(image.frame.cgRect)
        case let .pdf(pdf):
            context.setStrokeColor(UIColor.systemGray3.cgColor)
            context.stroke(pdf.frame.cgRect)
        }
    }
}

private extension CanvasPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

private extension CanvasRect {
    var cgRect: CGRect { CGRect(x: minX, y: minY, width: size.width, height: size.height) }
}

private extension InkColor {
    var cgColor: CGColor { UIColor(red: red, green: green, blue: blue, alpha: alpha).cgColor }
}
