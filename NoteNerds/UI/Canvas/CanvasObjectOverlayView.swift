import PDFKit
import UIKit

final class CanvasObjectOverlayView: UIView {
    let objects: [CanvasObject]
    let assets: [AssetID: Data]
    private let spatialIndex: CanvasSpatialIndex

    init(frame: CGRect, objects: [CanvasObject], assets: [AssetID: Data]) {
        self.objects = objects
        self.assets = assets
        spatialIndex = CanvasSpatialIndex(objects: objects)
        super.init(frame: frame)
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let visibleBounds = CanvasRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        for object in spatialIndex.objects(in: visibleBounds) {
            draw(object, in: context)
        }
    }

    private func draw(_ object: CanvasObject, in context: CGContext) {
        switch object {
        case .stroke: return
        case let .shape(shape): draw(shape, in: context)
        case let .text(text): draw(text)
        case let .image(image): draw(image, in: context)
        case let .pdf(pdf): draw(pdf, in: context)
        }
    }

    private func draw(_ shape: RecognizedShape, in context: CGContext) {
        guard let first = shape.points.first else { return }
        context.setStrokeColor(shape.style.color.uiColor.cgColor)
        context.setLineWidth(shape.style.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: first.cgPoint)
        for point in shape.points.dropFirst() { context.addLine(to: point.cgPoint) }
        if [.rectangle, .square, .circle, .ellipse, .triangle].contains(shape.kind) { context.closePath() }
        context.strokePath()
    }

    private func draw(_ text: TextBlock) {
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

    private func draw(_ imageObject: ImageObject, in context: CGContext) {
        guard let data = assets[imageObject.assetID], let image = UIImage(data: data)?.cgImage else {
            drawPlaceholder(frame: imageObject.frame, label: "Image", in: context)
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

    private func draw(_ pdfObject: PDFObject, in context: CGContext) {
        guard let data = assets[pdfObject.assetID],
              let document = PDFDocument(data: data),
              let page = document.page(at: pdfObject.pageIndex) else {
            drawPlaceholder(frame: pdfObject.frame, label: "PDF \(pdfObject.pageIndex + 1)", in: context)
            return
        }
        let mediaBounds = page.bounds(for: .mediaBox)
        context.saveGState()
        context.translateBy(x: pdfObject.frame.minX, y: pdfObject.frame.maxY)
        context.scaleBy(
            x: pdfObject.frame.size.width / mediaBounds.width,
            y: -pdfObject.frame.size.height / mediaBounds.height
        )
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }

    private func drawPlaceholder(frame: CanvasRect, label: String, in context: CGContext) {
        UIColor.secondarySystemBackground.setFill()
        context.fill(frame.cgRect)
        context.setStrokeColor(UIColor.separator.cgColor)
        context.stroke(frame.cgRect)
        NSString(string: label).draw(
            at: CGPoint(x: frame.minX + 16, y: frame.minY + 16),
            withAttributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: UIColor.secondaryLabel
            ]
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
