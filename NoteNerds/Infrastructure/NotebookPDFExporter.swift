import PDFKit
import UIKit

@MainActor
struct NotebookPDFExporter {
    private let pageBounds = CGRect(x: 0, y: 0, width: 1024, height: 1366)

    func export(_ notebook: Notebook, assets: [DocumentAsset] = []) throws -> Data {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0.data) })
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            for canvas in notebook.canvases {
                let objects = canvas.layers.filter(\.isVisible).flatMap(\.objects)
                let pdfObjects = objects.compactMap(\.pdfValue).sorted { $0.pageIndex < $1.pageIndex }
                if pdfObjects.isEmpty {
                    drawCanvas(canvas, objects: objects, assets: assetsByID, in: context)
                } else {
                    for pdfObject in pdfObjects {
                        drawPDFCanvasPage(
                            pdfObject,
                            annotations: objects.filter { $0.id != pdfObject.id },
                            assets: assetsByID,
                            in: context
                        )
                    }
                }
            }
        }
    }

    private func drawCanvas(
        _ canvas: Canvas,
        objects: [CanvasObject],
        assets: [AssetID: Data],
        in rendererContext: UIGraphicsPDFRendererContext
    ) {
        rendererContext.beginPage()
        PaperRenderer.draw(canvas.template, in: rendererContext.cgContext, bounds: pageBounds)
        rendererContext.cgContext.saveGState()
        applyFitTransform(for: canvas.exportBounds, to: rendererContext.cgContext)
        for object in objects { draw(object, assets: assets, in: rendererContext.cgContext) }
        rendererContext.cgContext.restoreGState()
    }

    private func drawPDFCanvasPage(
        _ pdfObject: PDFObject,
        annotations: [CanvasObject],
        assets: [AssetID: Data],
        in rendererContext: UIGraphicsPDFRendererContext
    ) {
        rendererContext.beginPage()
        UIColor.white.setFill()
        rendererContext.cgContext.fill(pageBounds)
        rendererContext.cgContext.saveGState()
        applyFitTransform(for: pdfObject.frame, to: rendererContext.cgContext)
        draw(.pdf(pdfObject), assets: assets, in: rendererContext.cgContext)
        for annotation in annotations where annotation.bounds.intersects(pdfObject.frame) {
            draw(annotation, assets: assets, in: rendererContext.cgContext)
        }
        rendererContext.cgContext.restoreGState()
    }

    private func applyFitTransform(for bounds: CanvasRect, to context: CGContext) {
        let padding = 40.0
        let availableWidth = pageBounds.width - padding * 2
        let availableHeight = pageBounds.height - padding * 2
        let scale = min(availableWidth / max(bounds.size.width, 1), availableHeight / max(bounds.size.height, 1))
        let fittedWidth = bounds.size.width * scale
        let fittedHeight = bounds.size.height * scale
        context.translateBy(
            x: (pageBounds.width - fittedWidth) / 2,
            y: (pageBounds.height - fittedHeight) / 2
        )
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
    }

    private func draw(_ object: CanvasObject, assets: [AssetID: Data], in context: CGContext) {
        switch object {
        case let .stroke(stroke):
            drawStroke(stroke, in: context)
        case let .shape(shape):
            drawShape(shape, in: context)
        case let .text(text):
            drawText(text)
        case let .image(image):
            drawImage(image, data: assets[image.assetID], in: context)
        case let .pdf(pdf):
            drawPDF(pdf, data: assets[pdf.assetID], in: context)
        }
    }

    private func drawStroke(_ stroke: Stroke, in context: CGContext) {
        guard let first = stroke.samples.first else { return }
        context.setStrokeColor(stroke.style.color.uiColor.cgColor)
        context.setLineWidth(stroke.style.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: first.point.cgPoint)
        stroke.samples.dropFirst().forEach { context.addLine(to: $0.point.cgPoint) }
        context.strokePath()
    }

    private func drawShape(_ shape: RecognizedShape, in context: CGContext) {
        guard let first = shape.points.first else { return }
        context.setStrokeColor(shape.style.color.uiColor.cgColor)
        context.setLineWidth(shape.style.width)
        context.move(to: first.cgPoint)
        shape.points.dropFirst().forEach { context.addLine(to: $0.cgPoint) }
        if [.rectangle, .square, .circle, .ellipse, .triangle].contains(shape.kind) {
            context.closePath()
        }
        context.strokePath()
    }

    private func drawText(_ text: TextBlock) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = text.alignment.nsTextAlignment
        NSString(string: text.text).draw(
            in: text.frame.cgRect,
            withAttributes: [
                .font: text.uiFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawImage(_ imageObject: ImageObject, data: Data?, in context: CGContext) {
        guard let data, let image = UIImage(data: data)?.cgImage else {
            drawPlaceholder(imageObject.frame, label: "Image", in: context)
            return
        }
        context.saveGState()
        let centerX = imageObject.frame.minX + imageObject.frame.size.width / 2
        let centerY = imageObject.frame.minY + imageObject.frame.size.height / 2
        context.translateBy(x: centerX, y: centerY)
        context.rotate(by: imageObject.rotation)
        context.draw(
            image,
            in: CGRect(
                x: -imageObject.frame.size.width / 2,
                y: -imageObject.frame.size.height / 2,
                width: imageObject.frame.size.width,
                height: imageObject.frame.size.height
            )
        )
        context.restoreGState()
    }

    private func drawPDF(_ pdfObject: PDFObject, data: Data?, in context: CGContext) {
        guard let data,
              let document = PDFDocument(data: data),
              let page = document.page(at: pdfObject.pageIndex) else {
            drawPlaceholder(pdfObject.frame, label: "PDF page \(pdfObject.pageIndex + 1)", in: context)
            return
        }
        let sourceBounds = page.bounds(for: .mediaBox)
        context.saveGState()
        context.translateBy(x: pdfObject.frame.minX, y: pdfObject.frame.maxY)
        context.scaleBy(
            x: pdfObject.frame.size.width / sourceBounds.width,
            y: -pdfObject.frame.size.height / sourceBounds.height
        )
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }

    private func drawPlaceholder(_ frame: CanvasRect, label: String, in context: CGContext) {
        context.setStrokeColor(UIColor.systemGray3.cgColor)
        context.stroke(frame.cgRect)
        NSString(string: label).draw(
            at: CGPoint(x: frame.minX + 12, y: frame.minY + 12),
            withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.secondaryLabel]
        )
    }
}

private extension CanvasPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

private extension CanvasRect {
    var cgRect: CGRect { CGRect(x: minX, y: minY, width: size.width, height: size.height) }
}

private extension InkColor {
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
}

private extension TextAlignment {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}
