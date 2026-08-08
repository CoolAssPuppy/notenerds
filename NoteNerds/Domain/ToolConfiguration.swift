import Foundation

enum ToolWidth: String, Codable, CaseIterable, Sendable {
    case extraFine
    case thin
    case medium
    case thick
    case extraBold

    var points: Double {
        switch self {
        case .extraFine: 0.75
        case .thin: 1.5
        case .medium: 3
        case .thick: 6
        case .extraBold: 10
        }
    }

    var label: String {
        switch self {
        case .extraFine: "Extra fine"
        case .thin: "Fine"
        case .medium: "Medium"
        case .thick: "Bold"
        case .extraBold: "Extra bold"
        }
    }
}

enum EraserMode: String, Codable, CaseIterable, Sendable {
    case stroke
    case precision
}

enum CanvasTool: String, Codable, CaseIterable, Sendable {
    case ballpoint
    case fineliner
    case mechanicalPencil
    case pencil
    case marker
    case highlighter
    case brush
    case calligraphyPen
    case eraser
    case lasso
    case handwritingToText
}

struct ToolConfiguration: Codable, Hashable, Sendable {
    var tool: CanvasTool
    var width: ToolWidth
    var color: InkColor
    var eraserMode: EraserMode = .stroke

    static let favoriteOne = ToolConfiguration(tool: .ballpoint, width: .medium, color: .black)
    static let favoriteTwo = ToolConfiguration(
        tool: .highlighter,
        width: .thick,
        color: InkColor(red: 0.95, green: 0.78, blue: 0.2, alpha: 0.45)
    )
}

struct ToolPaletteState: Codable, Hashable, Sendable {
    private(set) var current: ToolConfiguration
    private var configurations: [CanvasTool: ToolConfiguration]

    init() {
        configurations = Dictionary(uniqueKeysWithValues: CanvasTool.allCases.map { tool in
            (tool, ToolConfiguration(tool: tool, width: .medium, color: Self.defaultColor(for: tool)))
        })
        current = configurations[.ballpoint] ?? .favoriteOne
    }

    mutating func select(_ tool: CanvasTool) {
        configurations[current.tool] = current
        current = configurations[tool]
            ?? ToolConfiguration(tool: tool, width: .medium, color: Self.defaultColor(for: tool))
    }

    mutating func setWidth(_ width: ToolWidth) {
        current.width = width
        configurations[current.tool] = current
    }

    mutating func setColor(_ color: InkColor) {
        current.color = color
        configurations[current.tool] = current
    }

    mutating func setEraserMode(_ mode: EraserMode) {
        current.eraserMode = mode
        configurations[current.tool] = current
    }

    private static func defaultColor(for tool: CanvasTool) -> InkColor {
        tool == .highlighter
            ? InkColor(red: 0.95, green: 0.78, blue: 0.2, alpha: 0.45)
            : .black
    }
}
