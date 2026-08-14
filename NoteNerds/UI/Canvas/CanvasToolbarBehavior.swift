import CoreGraphics

enum CanvasToolbarAction: Equatable {
    case drawing
    case width
    case color
    case eraser
    case lasso
    case text
    case shapes
    case undo
    case redo
    case layers
}

enum CanvasToolbarPresentation {
    static let isChevronPinned = true
    static let specializedDrawingTools: [CanvasTool] = [
        .ballpoint, .fineliner, .mechanicalPencil, .pencil,
        .marker, .highlighter, .brush, .calligraphyPen, .handwritingToText
    ]

    static func verticalColumnCount(isExpanded: Bool) -> Int {
        1
    }

    /// Whether the drawing tool, eraser, and lasso buttons should read as the
    /// chosen tool.
    ///
    /// Placing text or a shape takes over the canvas, and the pen the person
    /// will come back to is not the pen they are using. Showing it selected
    /// says the wrong thing about what a tap will do next.
    static func isDrawingToolHighlighted(
        isTextToolActive: Bool,
        shapeKind: RecognizedShapeKind?
    ) -> Bool {
        !isTextToolActive && shapeKind == nil
    }

    static func actions(isExpanded: Bool) -> [CanvasToolbarAction] {
        let essentials: [CanvasToolbarAction] = [.drawing, .width, .color, .eraser, .lasso]
        guard isExpanded else { return essentials }
        return essentials + [.text, .shapes, .undo, .redo, .layers]
    }

    static func chevronSymbol(orientation: CanvasToolbarOrientation) -> String {
        orientation == .vertical ? "chevron.down" : "chevron.right"
    }

    static func chevronRotation(isExpanded: Bool) -> Double {
        isExpanded ? 180 : 0
    }

    static func scrollAxis(orientation: CanvasToolbarOrientation) -> CanvasToolbarScrollAxis {
        orientation == .vertical ? .vertical : .horizontal
    }

    static func maximumExpandedLength(orientation: CanvasToolbarOrientation) -> Double {
        orientation == .vertical ? 280 : 500
    }
}

enum CanvasToolbarScrollAxis: Equatable {
    case vertical
    case horizontal
}

enum CanvasToolbarDock: Equatable {
    case top
    case left
    case right

    var orientation: CanvasToolbarOrientation {
        self == .top ? .horizontal : .vertical
    }

    var isOnLeft: Bool {
        self != .right
    }
}

enum CanvasToolbarDocking {
    static func destination(for location: CGPoint, in size: CGSize) -> CanvasToolbarDock {
        if location.y <= min(220, size.height * 0.3) { return .top }
        return location.x < size.width / 2 ? .left : .right
    }
}
