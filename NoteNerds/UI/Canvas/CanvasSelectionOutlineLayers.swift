import UIKit

@MainActor
final class CanvasLassoOutlineLayer: CAShapeLayer {
    override init() {
        super.init()
        fillColor = UIColor.clear.cgColor
        strokeColor = UIColor.tintColor.cgColor
        lineWidth = 3
        lineDashPattern = [7, 5]
        lineCap = .round
        lineJoin = .round
        isHidden = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(points: [CGPoint]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let first = points.first, points.count > 1 else {
            path = nil
            isHidden = true
            return
        }
        let outline = UIBezierPath()
        outline.move(to: first)
        for point in points.dropFirst() { outline.addLine(to: point) }
        path = outline.cgPath
        isHidden = false
    }
}

@MainActor
final class CanvasSelectionOutlineLayers {
    private let selectionBorder = CAShapeLayer()
    private let selectionHandles = CAShapeLayer()
    private let lassoOutline = CanvasLassoOutlineLayer()
    var isSelectionVisible: Bool { !selectionBorder.isHidden && !selectionHandles.isHidden }
    var isLassoVisible: Bool { !lassoOutline.isHidden }
    var selectionPathBounds: CGRect? { selectionBorder.path?.boundingBox }
    var lassoPathBounds: CGRect? { lassoOutline.path?.boundingBox }

    init() {
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.strokeColor = UIColor.tintColor.cgColor
        selectionBorder.lineWidth = 2
        selectionBorder.lineDashPattern = [7, 5]
        selectionHandles.fillColor = UIColor.systemBackground.cgColor
        selectionHandles.strokeColor = UIColor.tintColor.cgColor
        selectionHandles.lineWidth = 2
    }

    func add(to parent: CALayer) {
        parent.addSublayer(selectionBorder)
        parent.addSublayer(selectionHandles)
        parent.addSublayer(lassoOutline)
    }

    func update(selectionBounds: CGRect?, handlePoints: [CGPoint], lassoPoints: [CGPoint]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateSelection(bounds: selectionBounds, handlePoints: handlePoints)
        CATransaction.commit()
        lassoOutline.update(points: lassoPoints)
    }

    private func updateSelection(bounds: CGRect?, handlePoints: [CGPoint]) {
        guard let bounds else {
            selectionBorder.path = nil
            selectionBorder.isHidden = true
            selectionHandles.path = nil
            selectionHandles.isHidden = true
            return
        }
        selectionBorder.path = UIBezierPath(rect: bounds.insetBy(dx: -6, dy: -6)).cgPath
        selectionBorder.isHidden = false
        let handles = UIBezierPath()
        for point in handlePoints {
            handles.append(UIBezierPath(ovalIn: CGRect(
                x: point.x - 6,
                y: point.y - 6,
                width: 12,
                height: 12
            )))
        }
        selectionHandles.path = handles.cgPath
        selectionHandles.isHidden = false
    }
}
