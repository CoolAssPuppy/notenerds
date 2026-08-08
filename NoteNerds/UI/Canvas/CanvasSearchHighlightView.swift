import UIKit

final class CanvasSearchHighlightView: UIView {
    private let strokes: [Stroke]

    init(frame: CGRect, strokes: [Stroke]) {
        self.strokes = strokes
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.28).cgColor)
        for stroke in strokes {
            let bounds = stroke.bounds
            context.fill(CGRect(
                x: bounds.minX - 10,
                y: bounds.minY - 10,
                width: bounds.size.width + 20,
                height: bounds.size.height + 20
            ))
        }
    }
}
