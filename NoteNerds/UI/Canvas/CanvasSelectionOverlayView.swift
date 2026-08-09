import UIKit

@MainActor
final class CanvasSelectionOverlayView: UIView, UIGestureRecognizerDelegate {
    private let objects: [CanvasObject]
    private let spatialIndex: CanvasSpatialIndex
    private let isLassoEnabled: Bool
    private let onTransform: (Set<ObjectID>, SelectionTransform, CanvasPoint) -> Void
    private let onDelete: (Set<ObjectID>) -> Void
    private let onPaste: ([CanvasObject]) -> Void
    private let onMoveToLayer: (Set<ObjectID>, LayerID) -> Void
    private let onEditText: (TextBlock) -> Void
    private let shapePlacementKind: RecognizedShapeKind?
    private let onPlaceShape: (CanvasPoint) -> Void
    private let onSelectionChanged: (Bool) -> Void
    private(set) var selectedIDs: Set<ObjectID> = []
    private var lassoPoints: [CanvasPoint] = []
    private var isMovingSelection = false
    private let outlineLayers = CanvasSelectionOutlineLayers()
    var hasSelection: Bool { !selectedIDs.isEmpty }

    init(
        frame: CGRect,
        objects: [CanvasObject],
        isLassoEnabled: Bool,
        onTransform: @escaping (Set<ObjectID>, SelectionTransform, CanvasPoint) -> Void,
        onDelete: @escaping (Set<ObjectID>) -> Void,
        onPaste: @escaping ([CanvasObject]) -> Void,
        onMoveToLayer: @escaping (Set<ObjectID>, LayerID) -> Void,
        onEditText: @escaping (TextBlock) -> Void,
        shapePlacementKind: RecognizedShapeKind?,
        onPlaceShape: @escaping (CanvasPoint) -> Void,
        onSelectionChanged: @escaping (Bool) -> Void
    ) {
        self.objects = objects
        spatialIndex = CanvasSpatialIndex(objects: objects)
        self.isLassoEnabled = isLassoEnabled
        self.onTransform = onTransform
        self.onDelete = onDelete
        self.onPaste = onPaste
        self.onMoveToLayer = onMoveToLayer
        self.onEditText = onEditText
        self.shapePlacementKind = shapePlacementKind
        self.onPlaceShape = onPlaceShape
        self.onSelectionChanged = onSelectionChanged
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        outlineLayers.add(to: layer)
        refreshOutlines()
        configureGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isLassoEnabled, shapePlacementKind == nil else { return true }
        let hitRegion = CanvasRect(x: point.x - 18, y: point.y - 18, width: 36, height: 36)
        return !spatialIndex.objects(in: hitRegion).isEmpty
    }

    func copySelection() {
        let selectedObjects = objects.filter { selectedIDs.contains($0.id) }
        guard !selectedObjects.isEmpty,
              let data = try? JSONEncoder().encode(SelectionClipboardPayload(objects: selectedObjects)) else { return }
        var item: [String: Any] = ["com.strategicnerds.notenerds.selection": data]
        let text = selectedObjects.compactMap(\.textValue).map(\.text).joined(separator: "\n")
        if !text.isEmpty { item["public.utf8-plain-text"] = text }
        UIPasteboard.general.items = [item]
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    func pasteSelection() {
        guard let data = UIPasteboard.general.data(forPasteboardType: "com.strategicnerds.notenerds.selection"),
              data.count <= 100 * 1_024 * 1_024,
              let payload = try? JSONDecoder().decode(SelectionClipboardPayload.self, from: data) else { return }
        onPaste(payload.pasted(offset: CanvasPoint(x: 24, y: 24)))
    }

    func duplicateSelection() {
        let selectedObjects = objects.filter { selectedIDs.contains($0.id) }
        onPaste(SelectionClipboardPayload(objects: selectedObjects).pasted(offset: CanvasPoint(x: 24, y: 24)))
    }

    func deleteSelection() {
        guard !selectedIDs.isEmpty else { return }
        onDelete(selectedIDs)
        selectedIDs = []
        onSelectionChanged(false)
        refreshOutlines()
    }

    func selectAllObjects() {
        selectedIDs = Set(objects.map(\.id))
        onSelectionChanged(!selectedIDs.isEmpty)
        refreshOutlines()
    }

    func moveSelection(to layerID: LayerID) {
        guard !selectedIDs.isEmpty else { return }
        onMoveToLayer(selectedIDs, layerID)
    }

    func selectedStrokes() -> [Stroke] {
        objects.compactMap { object in
            guard selectedIDs.contains(object.id), case let .stroke(stroke) = object else { return nil }
            return stroke
        }
    }

    private var selectionBounds: CanvasRect? {
        let selected = objects.filter { selectedIDs.contains($0.id) }
        guard let first = selected.first else { return nil }
        return selected.dropFirst().reduce(first.bounds) { bounds, object in
            CanvasRect.enclosing([
                bounds.origin,
                CanvasPoint(x: bounds.maxX, y: bounds.maxY),
                object.bounds.origin,
                CanvasPoint(x: object.bounds.maxX, y: object.bounds.maxY)
            ])
        }
    }

    private func refreshOutlines() {
        outlineLayers.update(
            selectionBounds: selectionBounds?.cgRect,
            handlePoints: selectionBounds.map(handlePoints) ?? [],
            lassoPoints: lassoPoints.map(\.cgPoint)
        )
    }

    private func configureGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(didRotate(_:)))
        [tap, doubleTap, pan, pinch, rotation].forEach {
            $0.delegate = self
            addGestureRecognizer($0)
        }
    }

    @objc private func didTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        if let object = objects.reversed().first(where: {
            $0.bounds.cgRect.insetBy(dx: -12, dy: -12).contains(point)
        }) {
            selectedIDs = [object.id]
            onSelectionChanged(true)
            refreshOutlines()
            UISelectionFeedbackGenerator().selectionChanged()
        } else if shapePlacementKind != nil {
            onPlaceShape(CanvasPoint(x: point.x, y: point.y))
        } else if isLassoEnabled {
            selectedIDs = []
            onSelectionChanged(false)
            refreshOutlines()
        }
    }

    @objc private func didPan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            isMovingSelection = selectionBounds?.cgRect.insetBy(dx: -12, dy: -12).contains(location) == true
            if !isMovingSelection && isLassoEnabled {
                selectedIDs = []
                lassoPoints = [CanvasPoint(x: location.x, y: location.y)]
                refreshOutlines()
            }
        case .changed where !isMovingSelection && isLassoEnabled:
            lassoPoints.append(CanvasPoint(x: location.x, y: location.y))
            refreshOutlines()
        case .ended where isMovingSelection:
            guard let bounds = selectionBounds else { return }
            let translation = recognizer.translation(in: self)
            sendTransform(
                SelectionTransform(
                    scaleX: 1,
                    scaleY: 1,
                    rotation: 0,
                    translation: CanvasPoint(x: translation.x, y: translation.y)
                ),
                bounds: bounds
            )
        case .ended where isLassoEnabled:
            completeLasso()
        case .cancelled:
            lassoPoints = []
            refreshOutlines()
        default:
            break
        }
    }

    private func completeLasso() {
        guard lassoPoints.count >= 3 else {
            lassoPoints = []
            refreshOutlines()
            return
        }
        let path = LassoPath(points: lassoPoints)
        selectedIDs = Set(objects.filter(path.selects).map(\.id))
        lassoPoints = []
        onSelectionChanged(!selectedIDs.isEmpty)
        refreshOutlines()
        if !selectedIDs.isEmpty { UISelectionFeedbackGenerator().selectionChanged() }
    }

    @objc private func didDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        guard let object = objects.reversed().first(where: {
            $0.bounds.cgRect.insetBy(dx: -12, dy: -12).contains(point)
        }), case let .text(text) = object else { return }
        onEditText(text)
    }

    @objc private func didPinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .ended, let bounds = selectionBounds else { return }
        sendTransform(
            SelectionTransform(
                scaleX: recognizer.scale,
                scaleY: recognizer.scale,
                rotation: 0,
                translation: .zero
            ),
            bounds: bounds
        )
    }

    @objc private func didRotate(_ recognizer: UIRotationGestureRecognizer) {
        guard recognizer.state == .ended, let bounds = selectionBounds else { return }
        sendTransform(
            SelectionTransform(scaleX: 1, scaleY: 1, rotation: recognizer.rotation, translation: .zero),
            bounds: bounds
        )
    }

    private func sendTransform(_ transform: SelectionTransform, bounds: CanvasRect) {
        let center = CanvasPoint(
            x: bounds.minX + bounds.size.width / 2,
            y: bounds.minY + bounds.size.height / 2
        )
        onTransform(selectedIDs, transform, center)
    }

    private func handlePoints(for bounds: CanvasRect) -> [CGPoint] {
        [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY)
        ]
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UIPinchGestureRecognizer || gestureRecognizer is UIRotationGestureRecognizer
    }
}

private extension CanvasRect {
    var cgRect: CGRect { CGRect(x: minX, y: minY, width: size.width, height: size.height) }
}

private extension CanvasPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

private extension CanvasObject {
    var textValue: TextBlock? {
        guard case let .text(text) = self else { return nil }
        return text
    }
}
