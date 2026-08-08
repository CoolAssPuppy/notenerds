import CoreGraphics

enum CanvasToolbarAction: Equatable {
    case drawing
    case width
    case color
    case eraser
    case lasso
    case text
    case undo
    case redo
    case zoomToContent
    case minimap
    case changePaper
    case importContent
    case layers
    case home
}

enum CanvasToolbarPresentation {
    static func verticalColumnCount(isExpanded: Bool) -> Int {
        isExpanded ? 2 : 1
    }

    static func actions(isExpanded: Bool) -> [CanvasToolbarAction] {
        let essentials: [CanvasToolbarAction] = [.drawing, .width, .color, .eraser]
        guard isExpanded else { return essentials }
        return essentials + [
            .lasso, .text, .undo, .redo,
            .zoomToContent, .minimap, .changePaper, .importContent, .layers, .home
        ]
    }

    static func chevronSymbol(orientation: CanvasToolbarOrientation) -> String {
        orientation == .vertical ? "chevron.down" : "chevron.right"
    }

    static func chevronRotation(isExpanded: Bool) -> Double {
        isExpanded ? 180 : 0
    }
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
