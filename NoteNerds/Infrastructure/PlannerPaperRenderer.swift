import UIKit

enum PlannerPaperRenderer {
    private static let inkColor = UIColor(red: 0.19, green: 0.27, blue: 0.32, alpha: 0.72)
    private static let lineColor = UIColor(red: 0.32, green: 0.43, blue: 0.49, alpha: 0.24)

    static func drawDaily(in context: CGContext, bounds: CGRect) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        let layout = PlannerPageLayout.daily(in: bounds)
        drawDots(in: layout.freeformArea.insetBy(dx: 8, dy: 8), context: context)
        strokeDivider(from: layout.freeformArea.minX, to: layout.freeformArea.maxX,
                      at: layout.freeformArea.maxY, context: context)
        strokeVerticalDivider(in: layout.contentArea, x: layout.todayArea.maxX,
                              from: layout.todayArea.minY, context: context)
        drawHeader("Today", in: layout.todayArea, context: context)
        drawTodayRows(layout, context: context)
        drawHeader("Parking lot", in: layout.parkingLotArea, context: context)
        drawGrid(in: parkingGridArea(layout.parkingLotArea), context: context)
    }

    static func drawWeekly(in context: CGContext, bounds: CGRect) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        for section in PlannerPageLayout.weekly(in: bounds) {
            context.setStrokeColor(lineColor.cgColor)
            context.setLineWidth(1)
            context.stroke(section.frame)
            drawHeader(section.title, in: section.frame, context: context)
        }
    }

    private static func drawTodayRows(_ layout: DailyPlannerLayout, context: CGContext) {
        let numberWidth = max(24, layout.todayArea.width * 0.1)
        for (index, yPosition) in layout.todayRuleYs.enumerated() {
            drawText(
                "\(index + 1)",
                in: CGRect(
                    x: layout.todayArea.minX + 4,
                    y: yPosition - 22,
                    width: numberWidth,
                    height: 20
                ),
                font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            )
            context.setStrokeColor(lineColor.cgColor)
            context.setLineWidth(0.75)
            context.move(to: CGPoint(x: layout.todayArea.minX + numberWidth, y: yPosition))
            context.addLine(to: CGPoint(x: layout.todayArea.maxX - 12, y: yPosition))
            context.strokePath()
        }
    }

    private static func drawHeader(_ title: String, in area: CGRect, context: CGContext) {
        let fontSize = min(20, max(11, area.width * 0.055))
        drawText(
            title,
            in: CGRect(x: area.minX + 12, y: area.minY + 8, width: area.width - 24, height: 28),
            font: .systemFont(ofSize: fontSize, weight: .semibold)
        )
    }

    private static func drawText(_ text: String, in frame: CGRect, font: UIFont) {
        text.draw(
            in: frame,
            withAttributes: [
                .font: font,
                .foregroundColor: inkColor
            ]
        )
    }

    private static func drawDots(in area: CGRect, context: CGContext) {
        let spacing = max(12, min(18, area.width / 36))
        context.setFillColor(lineColor.withAlphaComponent(0.5).cgColor)
        for x in stride(from: area.minX + spacing, through: area.maxX, by: spacing) {
            for y in stride(from: area.minY + spacing, through: area.maxY, by: spacing) {
                context.fillEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
            }
        }
    }

    private static func drawGrid(in area: CGRect, context: CGContext) {
        let spacing = max(14, min(22, area.width / 14))
        context.setStrokeColor(lineColor.cgColor)
        context.setLineWidth(0.6)
        for x in stride(from: area.minX, through: area.maxX, by: spacing) {
            context.move(to: CGPoint(x: x, y: area.minY))
            context.addLine(to: CGPoint(x: x, y: area.maxY))
        }
        for y in stride(from: area.minY, through: area.maxY, by: spacing) {
            context.move(to: CGPoint(x: area.minX, y: y))
            context.addLine(to: CGPoint(x: area.maxX, y: y))
        }
        context.strokePath()
    }

    private static func parkingGridArea(_ area: CGRect) -> CGRect {
        let headerHeight = min(52, max(28, area.height * 0.08))
        return CGRect(
            x: area.minX + 12,
            y: area.minY + headerHeight,
            width: area.width - 24,
            height: area.height - headerHeight - 12
        )
    }

    private static func strokeDivider(
        from minX: CGFloat,
        to maxX: CGFloat,
        at yPosition: CGFloat,
        context: CGContext
    ) {
        context.setStrokeColor(lineColor.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: minX, y: yPosition))
        context.addLine(to: CGPoint(x: maxX, y: yPosition))
        context.strokePath()
    }

    private static func strokeVerticalDivider(
        in area: CGRect,
        x: CGFloat,
        from minY: CGFloat,
        context: CGContext
    ) {
        context.setStrokeColor(lineColor.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: minY))
        context.addLine(to: CGPoint(x: x, y: area.maxY))
        context.strokePath()
    }
}
