import PDFKit
import UIKit

@MainActor
final class CanvasObjectOverlayView: UIView {
    init(frame: CGRect, objects: [CanvasObject], assets: [AssetID: Data]) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        objects.compactMap { Self.renderedView(for: $0, assets: assets) }.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private static func renderedView(
        for object: CanvasObject,
        assets: [AssetID: Data]
    ) -> UIView? {
        switch object {
        case .stroke:
            return nil
        case let .shape(shape):
            return CanvasShapeObjectView(shape: shape)
        case let .text(text):
            return textView(for: text)
        case let .image(image):
            return imageView(for: image, assets: assets)
        case let .pdf(pdf):
            return pdfView(for: pdf, assets: assets)
        }
    }

    private static func textView(for text: TextBlock) -> UILabel {
        let label = UILabel(frame: text.frame.cgRect)
        label.backgroundColor = .clear
        label.font = text.uiFont
        label.text = text.text
        label.textColor = .label
        label.textAlignment = text.alignment.nsTextAlignment
        label.numberOfLines = 0
        return label
    }

    private static func imageView(for object: ImageObject, assets: [AssetID: Data]) -> UIView {
        guard let data = assets[object.assetID], let image = UIImage(data: data) else {
            return CanvasObjectPlaceholderView(frame: object.frame.cgRect, label: "Image")
        }
        let imageView = UIImageView(frame: object.frame.cgRect)
        imageView.image = image
        imageView.contentMode = .scaleToFill
        imageView.transform = CGAffineTransform(rotationAngle: object.rotation)
        return imageView
    }

    private static func pdfView(for object: PDFObject, assets: [AssetID: Data]) -> UIView {
        guard let data = assets[object.assetID],
              let document = PDFDocument(data: data),
              let page = document.page(at: object.pageIndex) else {
            return CanvasObjectPlaceholderView(
                frame: object.frame.cgRect,
                label: "PDF \(object.pageIndex + 1)"
            )
        }
        let imageView = UIImageView(frame: object.frame.cgRect)
        imageView.image = page.thumbnail(of: object.frame.cgRect.size, for: .mediaBox)
        imageView.contentMode = .scaleToFill
        return imageView
    }
}

@MainActor
private final class CanvasShapeObjectView: UIView {
    private let points: [CanvasPoint]
    private let style: StrokeStyle
    private let shouldClosePath: Bool

    init(shape: RecognizedShape) {
        let padding = max(shape.style.width, 1)
        let bounds = CanvasRect.enclosing(shape.points)
        points = shape.points.map {
            CanvasPoint(x: $0.x - bounds.minX + padding, y: $0.y - bounds.minY + padding)
        }
        style = shape.style
        shouldClosePath = [.rectangle, .square, .circle, .ellipse, .triangle].contains(shape.kind)
        super.init(frame: CGRect(
            x: bounds.minX - padding,
            y: bounds.minY - padding,
            width: max(bounds.size.width + padding * 2, padding * 2),
            height: max(bounds.size.height + padding * 2, padding * 2)
        ))
        isOpaque = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let first = points.first else { return }
        context.setStrokeColor(style.color.uiColor.cgColor)
        context.setLineWidth(style.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: first.cgPoint)
        points.dropFirst().forEach { context.addLine(to: $0.cgPoint) }
        if shouldClosePath { context.closePath() }
        context.strokePath()
    }
}

@MainActor
private final class CanvasObjectPlaceholderView: UIView {
    private let label: UILabel

    init(frame: CGRect, label text: String) {
        label = UILabel()
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1
        label.text = text
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
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
