import Foundation

enum RadialPalettePage: Equatable {
    case root
    case drawingTools
    case colors
    case widths
    case eraserModes
    case precisionEraserWidths

    var parent: RadialPalettePage? {
        switch self {
        case .root:
            nil
        case .precisionEraserWidths:
            .eraserModes
        case .drawingTools, .colors, .widths, .eraserModes:
            .root
        }
    }
}

enum RadialPaletteAction: Equatable {
    case open(RadialPalettePage)
    case tool(CanvasTool)
    case width(ToolWidth)
    case color(InkColor)
    case customColor
    case eraserMode(EraserMode)
    case undo
    case redo
    case selection(CanvasEditingAction)

    var destination: RadialPalettePage? {
        switch self {
        case let .open(page):
            page
        case .eraserMode(.precision):
            .precisionEraserWidths
        case .tool, .width, .color, .customColor, .eraserMode(.stroke),
             .undo, .redo, .selection:
            nil
        }
    }
}

struct RadialPaletteItem: Equatable, Identifiable {
    let id: String
    let label: String
    let symbol: String
    let action: RadialPaletteAction
}

struct RadialPaletteItemPlacement: Equatable {
    let ringIndex: Int
    let indexInRing: Int
    let itemCountInRing: Int
    let radius: Double
}

enum RadialPalettePresentation {
    static let maximumItemCount = CanvasInkChoice.allCases.count + 1
    private static let maximumItemsPerRing = 6

    static func items(for page: RadialPalettePage) -> [RadialPaletteItem] {
        switch page {
        case .root:
            rootItems
        case .drawingTools:
            CanvasToolbarPresentation.specializedDrawingTools.map(toolItem)
        case .colors:
            colorItems + [customColorItem]
        case .widths, .precisionEraserWidths:
            ToolWidth.allCases.map(widthItem)
        case .eraserModes:
            eraserItems
        }
    }

    static func ringCount(for itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return min(3, Int(ceil(Double(itemCount) / Double(maximumItemsPerRing))))
    }

    static func placement(for index: Int, itemCount: Int) -> RadialPaletteItemPlacement {
        let counts = itemCountsByRing(for: itemCount)
        var remainingIndex = index
        for (ringIndex, count) in counts.enumerated() {
            if remainingIndex < count {
                return RadialPaletteItemPlacement(
                    ringIndex: ringIndex,
                    indexInRing: remainingIndex,
                    itemCountInRing: count,
                    radius: radii(for: counts.count)[ringIndex]
                )
            }
            remainingIndex -= count
        }
        return RadialPaletteItemPlacement(ringIndex: 0, indexInRing: 0, itemCountInRing: 1, radius: 80)
    }

    static func maximumRadius(for itemCount: Int) -> Double {
        let count = ringCount(for: itemCount)
        return radii(for: count).last ?? 0
    }

    private static let rootItems = [
        RadialPaletteItem(
            id: "writing-tools",
            label: "Writing tools",
            symbol: "pencil.tip",
            action: .open(.drawingTools)
        ),
        RadialPaletteItem(
            id: "eraser",
            label: "Eraser",
            symbol: "eraser",
            action: .open(.eraserModes)
        ),
        RadialPaletteItem(id: "lasso", label: "Lasso", symbol: "lasso", action: .tool(.lasso)),
        RadialPaletteItem(id: "undo", label: "Undo", symbol: "arrow.uturn.backward", action: .undo),
        RadialPaletteItem(id: "redo", label: "Redo", symbol: "arrow.uturn.forward", action: .redo),
        RadialPaletteItem(
            id: "width",
            label: "Width",
            symbol: "lineweight",
            action: .open(.widths)
        ),
        RadialPaletteItem(
            id: "color",
            label: "Color",
            symbol: "circle.fill",
            action: .open(.colors)
        )
    ]

    private static let eraserItems = [
        RadialPaletteItem(
            id: "object-eraser",
            label: "Object eraser",
            symbol: "eraser.line.dashed",
            action: .eraserMode(.stroke)
        ),
        RadialPaletteItem(
            id: "pixel-eraser",
            label: "Pixel eraser",
            symbol: "eraser",
            action: .eraserMode(.precision)
        )
    ]

    private static var colorItems: [RadialPaletteItem] {
        CanvasInkChoice.allCases.map { choice in
            RadialPaletteItem(
                id: "color-\(choice.label.lowercased())",
                label: choice.label,
                symbol: "circle.fill",
                action: .color(choice.color)
            )
        }
    }

    private static let customColorItem = RadialPaletteItem(
        id: "custom-color",
        label: "Custom color",
        symbol: "eyedropper",
        action: .customColor
    )

    private static func toolItem(_ tool: CanvasTool) -> RadialPaletteItem {
        RadialPaletteItem(
            id: "tool-\(tool.rawValue)",
            label: tool.label,
            symbol: tool.symbol,
            action: .tool(tool)
        )
    }

    private static func widthItem(_ width: ToolWidth) -> RadialPaletteItem {
        RadialPaletteItem(
            id: "width-\(width.rawValue)",
            label: width.label,
            symbol: "lineweight",
            action: .width(width)
        )
    }

    private static func itemCountsByRing(for itemCount: Int) -> [Int] {
        let count = ringCount(for: itemCount)
        guard count > 0 else { return [] }
        let baseCount = itemCount / count
        let remainder = itemCount % count
        return (0..<count).map { baseCount + ($0 < remainder ? 1 : 0) }
    }

    private static func radii(for ringCount: Int) -> [Double] {
        switch ringCount {
        case 1: [80]
        case 2: [70, 124]
        case 3: [60, 112, 164]
        default: []
        }
    }
}
