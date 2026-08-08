import UIKit

enum HexagonPaperRenderer {
    static func draw(sideLength: CGFloat, in context: CGContext, bounds: CGRect) {
        let horizontalSpacing = sqrt(3) * sideLength
        let verticalSpacing = 1.5 * sideLength
        let rowCount = Int(ceil(bounds.height / verticalSpacing)) + 3
        let columnCount = Int(ceil(bounds.width / horizontalSpacing)) + 3

        for row in -2...rowCount {
            let xOffset = row.isMultiple(of: 2) ? 0 : horizontalSpacing / 2
            for column in -2...columnCount {
                let center = CGPoint(
                    x: bounds.minX + CGFloat(column) * horizontalSpacing + xOffset,
                    y: bounds.minY + CGFloat(row) * verticalSpacing
                )
                addHexagon(centeredAt: center, sideLength: sideLength, to: context)
            }
        }
        context.strokePath()
    }

    private static func addHexagon(
        centeredAt center: CGPoint,
        sideLength: CGFloat,
        to context: CGContext
    ) {
        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3 - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * sideLength,
                y: center.y + sin(angle) * sideLength
            )
            if index == 0 {
                context.move(to: point)
            } else {
                context.addLine(to: point)
            }
        }
        context.closePath()
    }
}
