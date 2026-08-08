import UIKit

enum PaperRenderer {
    static func patternColor(for paperType: PaperType) -> UIColor {
        guard paperType.hasPattern else { return paperType.backgroundColor }
        let tileSize = paperType.tileSize
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: tileSize, format: format).image { rendererContext in
            drawRepeatingTile(paperType, in: rendererContext.cgContext, bounds: CGRect(origin: .zero, size: tileSize))
        }
        return UIColor(patternImage: image)
    }

    private static func drawRepeatingTile(_ paperType: PaperType, in context: CGContext, bounds: CGRect) {
        guard [.yellowLegalPad, .whiteLegalPad].contains(paperType) else {
            draw(paperType, in: context, bounds: bounds)
            return
        }
        context.saveGState()
        context.setFillColor(paperType.backgroundColor.cgColor)
        context.fill(bounds)
        context.setLineWidth(0.75)
        context.setStrokeColor(paperType.ruleColor.cgColor)
        drawLegalRules(spacing: paperType.spacing, in: context, bounds: bounds)
        context.restoreGState()
    }

    static func draw(_ paperType: PaperType, in context: CGContext, bounds: CGRect) {
        context.saveGState()
        context.setFillColor(paperType.backgroundColor.cgColor)
        context.fill(bounds)
        context.setLineWidth(0.75)
        context.setStrokeColor(paperType.ruleColor.cgColor)

        switch paperType {
        case .blankWhite, .blankCream:
            break
        case .gridLarge, .gridSmall:
            drawGrid(spacing: paperType.spacing, in: context, bounds: bounds)
        case .dotLarge, .dotSmall:
            drawDots(spacing: paperType.spacing, in: context, bounds: bounds)
        case .yellowLegalPad, .whiteLegalPad:
            drawLegalPad(spacing: paperType.spacing, in: context, bounds: bounds)
        }
        context.restoreGState()
    }

    private static func drawGrid(spacing: CGFloat, in context: CGContext, bounds: CGRect) {
        for x in stride(from: bounds.minX + spacing, through: bounds.maxX, by: spacing) {
            context.move(to: CGPoint(x: x, y: bounds.minY))
            context.addLine(to: CGPoint(x: x, y: bounds.maxY))
        }
        for y in stride(from: bounds.minY + spacing, through: bounds.maxY, by: spacing) {
            context.move(to: CGPoint(x: bounds.minX, y: y))
            context.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        context.strokePath()
    }

    private static func drawDots(spacing: CGFloat, in context: CGContext, bounds: CGRect) {
        context.setFillColor(PaperType.dotColor.cgColor)
        for x in stride(from: bounds.minX + spacing, through: bounds.maxX, by: spacing) {
            for y in stride(from: bounds.minY + spacing, through: bounds.maxY, by: spacing) {
                context.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
            }
        }
    }

    private static func drawLegalPad(spacing: CGFloat, in context: CGContext, bounds: CGRect) {
        drawLegalRules(spacing: spacing, in: context, bounds: bounds)
        context.setStrokeColor(PaperType.marginColor.cgColor)
        context.setLineWidth(1)
        let marginX = bounds.minX + min(52, bounds.width * 0.18)
        context.move(to: CGPoint(x: marginX, y: bounds.minY))
        context.addLine(to: CGPoint(x: marginX, y: bounds.maxY))
        context.strokePath()
    }

    private static func drawLegalRules(spacing: CGFloat, in context: CGContext, bounds: CGRect) {
        for y in stride(from: bounds.minY + spacing, through: bounds.maxY, by: spacing) {
            context.move(to: CGPoint(x: bounds.minX, y: y))
            context.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        context.strokePath()
    }
}

extension PaperType {
    var displayName: String {
        switch self {
        case .blankWhite: "Blank white"
        case .blankCream: "Blank cream"
        case .gridLarge: "Grid large"
        case .gridSmall: "Grid small"
        case .dotLarge: "Dot large"
        case .dotSmall: "Dot small"
        case .yellowLegalPad: "Yellow legal pad"
        case .whiteLegalPad: "White legal pad"
        }
    }

    var backgroundColor: UIColor {
        switch self {
        case .blankCream: UIColor(red: 0.98, green: 0.955, blue: 0.875, alpha: 1)
        case .yellowLegalPad: UIColor(red: 1, green: 0.965, blue: 0.69, alpha: 1)
        case .blankWhite, .gridLarge, .gridSmall, .dotLarge, .dotSmall, .whiteLegalPad: .white
        }
    }

    var ruleColor: UIColor {
        switch self {
        case .yellowLegalPad, .whiteLegalPad:
            UIColor(red: 0.25, green: 0.48, blue: 0.72, alpha: 0.32)
        case .gridLarge, .gridSmall:
            UIColor(red: 0.38, green: 0.55, blue: 0.68, alpha: 0.28)
        case .blankWhite, .blankCream, .dotLarge, .dotSmall:
            Self.dotColor
        }
    }

    var spacing: CGFloat {
        switch self {
        case .gridLarge, .dotLarge: 48
        case .gridSmall, .dotSmall: 24
        case .yellowLegalPad: 36
        case .whiteLegalPad: 30
        case .blankWhite, .blankCream: 32
        }
    }

    var tileSize: CGSize {
        switch self {
        case .yellowLegalPad, .whiteLegalPad: CGSize(width: 320, height: spacing)
        default: CGSize(width: spacing, height: spacing)
        }
    }

    fileprivate var hasPattern: Bool {
        ![.blankWhite, .blankCream].contains(self)
    }

    fileprivate static let dotColor = UIColor(red: 0.28, green: 0.4, blue: 0.5, alpha: 0.42)
    static let marginColor = UIColor(red: 0.84, green: 0.24, blue: 0.28, alpha: 0.5)
}
