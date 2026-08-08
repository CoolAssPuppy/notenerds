import UIKit

@MainActor
final class CanvasTextPlacementOverlayView: UIView {
    private let textBlocks: [TextBlock]
    private let onPlaceText: (CanvasPoint) -> Void
    private let onEditText: (TextBlock) -> Void

    init(
        frame: CGRect,
        objects: [CanvasObject],
        onPlaceText: @escaping (CanvasPoint) -> Void,
        onEditText: @escaping (TextBlock) -> Void
    ) {
        textBlocks = objects.compactMap { object in
            guard case let .text(textBlock) = object else { return nil }
            return textBlock
        }
        self.onPlaceText = onPlaceText
        self.onEditText = onEditText
        super.init(frame: frame)
        backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    @objc private func didTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        let point = CanvasPoint(x: location.x, y: location.y)
        let hitArea = CanvasRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
        if let textBlock = textBlocks.reversed().first(where: { $0.frame.intersects(hitArea) }) {
            onEditText(textBlock)
        } else {
            onPlaceText(point)
        }
    }
}
