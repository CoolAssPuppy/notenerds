import CoreGraphics

struct DailyPlannerLayout: Equatable {
    let contentArea: CGRect
    let freeformArea: CGRect
    let todayArea: CGRect
    let parkingLotArea: CGRect
    let todayRuleYs: [CGFloat]
}

struct WeeklyPlannerSection: Equatable {
    let title: String
    let frame: CGRect
}

enum PlannerPageLayout {
    static let pageSize = CGSize(width: 768, height: 1_024)
    static let canvasPageOrigin = CGPoint(x: 9_216, y: 9_216)

    static func daily(in bounds: CGRect) -> DailyPlannerLayout {
        let contentArea = bounds.insetBy(dx: pageInset(for: bounds), dy: pageInset(for: bounds))
        let freeformHeight = contentArea.height / 3
        let freeformArea = CGRect(
            x: contentArea.minX,
            y: contentArea.minY,
            width: contentArea.width,
            height: freeformHeight
        )
        let lowerArea = CGRect(
            x: contentArea.minX,
            y: freeformArea.maxY,
            width: contentArea.width,
            height: contentArea.height - freeformHeight
        )
        let columnWidth = lowerArea.width / 2
        let todayArea = CGRect(
            x: lowerArea.minX,
            y: lowerArea.minY,
            width: columnWidth,
            height: lowerArea.height
        )
        let parkingLotArea = CGRect(
            x: todayArea.maxX,
            y: lowerArea.minY,
            width: columnWidth,
            height: lowerArea.height
        )
        let headerHeight = min(52, max(28, lowerArea.height * 0.08))
        let rowHeight = (todayArea.height - headerHeight) / 10
        let todayRuleYs = (1...10).map { todayArea.minY + headerHeight + rowHeight * CGFloat($0) }
        return DailyPlannerLayout(
            contentArea: contentArea,
            freeformArea: freeformArea,
            todayArea: todayArea,
            parkingLotArea: parkingLotArea,
            todayRuleYs: todayRuleYs
        )
    }

    static func weekly(in bounds: CGRect) -> [WeeklyPlannerSection] {
        let titles = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Weekend"]
        let contentArea = bounds.insetBy(dx: pageInset(for: bounds), dy: pageInset(for: bounds))
        let sectionSize = CGSize(width: contentArea.width / 2, height: contentArea.height / 3)
        return titles.enumerated().map { index, title in
            WeeklyPlannerSection(
                title: title,
                frame: CGRect(
                    x: contentArea.minX + CGFloat(index % 2) * sectionSize.width,
                    y: contentArea.minY + CGFloat(index / 2) * sectionSize.height,
                    width: sectionSize.width,
                    height: sectionSize.height
                )
            )
        }
    }

    private static func pageInset(for bounds: CGRect) -> CGFloat {
        min(48, max(16, min(bounds.width, bounds.height) * 0.05))
    }
}

enum PlannerRegionCatalog {
    static func regions(for paperType: PaperType) -> [CanvasRegion] {
        let pageBounds = CGRect(origin: PlannerPageLayout.canvasPageOrigin, size: PlannerPageLayout.pageSize)
        switch paperType {
        case .dailyPlanner:
            let layout = PlannerPageLayout.daily(in: pageBounds)
            return [
                CanvasRegion(id: "freeform", title: "Freeform", frame: canvasRect(layout.freeformArea)),
                CanvasRegion(id: "today", title: "Today", frame: canvasRect(layout.todayArea)),
                CanvasRegion(id: "parking-lot", title: "Parking lot", frame: canvasRect(layout.parkingLotArea))
            ]
        case .weeklyPlanner:
            return PlannerPageLayout.weekly(in: pageBounds).map { section in
                CanvasRegion(
                    id: section.title.lowercased(),
                    title: section.title,
                    frame: canvasRect(section.frame)
                )
            }
        default:
            return []
        }
    }

    private static func canvasRect(_ frame: CGRect) -> CanvasRect {
        CanvasRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }
}

enum PlannerViewportPolicy {
    static let reflowsDocumentOnRotation = false

    static func initialZoom(for viewportSize: CGSize) -> CGFloat {
        let usableWidth = max(1, viewportSize.width - 32)
        return min(1, usableWidth / PlannerPageLayout.pageSize.width)
    }
}

enum PlannerRegionContentPolicy {
    static func region(containing point: CanvasPoint, in regions: [CanvasRegion]) -> CanvasRegion? {
        regions.first { region in
            point.x >= region.frame.minX
                && point.x <= region.frame.maxX
                && point.y >= region.frame.minY
                && point.y <= region.frame.maxY
        }
    }

    static func constrainedFrame(_ frame: CanvasRect, to region: CanvasRect?) -> CanvasRect {
        guard let region else { return frame }
        let width = min(frame.size.width, region.size.width)
        let height = min(frame.size.height, region.size.height)
        return CanvasRect(
            x: min(max(frame.minX, region.minX), region.maxX - width),
            y: min(max(frame.minY, region.minY), region.maxY - height),
            width: width,
            height: height
        )
    }

    static func constrainedStroke(_ stroke: Stroke, to region: CanvasRect?) -> Stroke {
        guard let region else { return stroke }
        var constrained = stroke
        constrained.samples = stroke.samples.map { sample in
            var updated = sample
            updated.point = CanvasPoint(
                x: min(max(sample.point.x, region.minX), region.maxX),
                y: min(max(sample.point.y, region.minY), region.maxY)
            )
            return updated
        }
        return constrained
    }
}
