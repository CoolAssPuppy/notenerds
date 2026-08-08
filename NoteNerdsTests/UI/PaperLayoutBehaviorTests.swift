import CoreGraphics
import UIKit
import XCTest
@testable import NoteNerds

final class PaperLayoutBehaviorTests: XCTestCase {
    func testDailyPlannerKeepsOneThirdFreeformAndTwoEqualLowerColumns() {
        let bounds = CGRect(origin: .zero, size: PlannerPageLayout.pageSize)

        let layout = PlannerPageLayout.daily(in: bounds)

        XCTAssertEqual(layout.freeformArea.height, layout.contentArea.height / 3, accuracy: 0.001)
        XCTAssertEqual(layout.todayArea.width, layout.parkingLotArea.width, accuracy: 0.001)
        XCTAssertEqual(layout.todayArea.minY, layout.freeformArea.maxY, accuracy: 0.001)
        XCTAssertEqual(layout.todayRuleYs.count, 10)
    }

    func testWeeklyPlannerUsesSixEqualStableSections() throws {
        let bounds = CGRect(origin: .zero, size: PlannerPageLayout.pageSize)

        let sections = PlannerPageLayout.weekly(in: bounds)
        let monday = try XCTUnwrap(sections.first { $0.title == "Monday" })
        let tuesday = try XCTUnwrap(sections.first { $0.title == "Tuesday" })
        let wednesday = try XCTUnwrap(sections.first { $0.title == "Wednesday" })

        XCTAssertEqual(
            sections.map(\.title),
            ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Weekend"]
        )
        XCTAssertEqual(Set(sections.map { $0.frame.width.rounded() }).count, 1)
        XCTAssertEqual(Set(sections.map { $0.frame.height.rounded() }).count, 1)
        XCTAssertEqual(wednesday.frame.minY, monday.frame.maxY, accuracy: 0.001)
        XCTAssertEqual(tuesday.frame.minX, monday.frame.maxX, accuracy: 0.001)
    }

    func testPlannerViewportFitsCompactPortraitWithoutChangingDocumentGeometry() {
        XCTAssertFalse(PlannerViewportPolicy.reflowsDocumentOnRotation)
        XCTAssertEqual(
            PlannerViewportPolicy.initialZoom(for: CGSize(width: 390, height: 844)),
            358 / PlannerPageLayout.pageSize.width,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PlannerViewportPolicy.initialZoom(for: CGSize(width: 1_366, height: 1_024)),
            1,
            accuracy: 0.001
        )
    }

    func testHexagonSizesKeepTheLargePatternTwiceAsWide() {
        XCTAssertEqual(PaperType.hexagonLarge.spacing, PaperType.hexagonSmall.spacing * 2)
    }

    func testPlannerTemplatesExposeStableSemanticCanvasRegions() throws {
        let dailyRegions = PlannerRegionCatalog.regions(for: .dailyPlanner)
        let weeklyRegions = PlannerRegionCatalog.regions(for: .weeklyPlanner)

        XCTAssertEqual(dailyRegions.map(\.id), ["freeform", "today", "parking-lot"])
        XCTAssertEqual(dailyRegions.map(\.title), ["Freeform", "Today", "Parking lot"])
        XCTAssertEqual(
            weeklyRegions.map(\.id),
            ["monday", "tuesday", "wednesday", "thursday", "friday", "weekend"]
        )
        XCTAssertTrue(PlannerRegionCatalog.regions(for: .blankWhite).isEmpty)
        let today = try XCTUnwrap(dailyRegions.first { $0.id == "today" })
        XCTAssertGreaterThan(today.frame.minX, 9_000)
        XCTAssertGreaterThan(today.frame.minY, 9_000)
    }

    func testPlannerPagingUsesHorizontalIntentAndStopsAtTheEnds() {
        XCTAssertEqual(
            PlannerRegionPaging.destinationIndex(
                from: 0,
                regionCount: 3,
                translation: CGSize(width: -70, height: 8),
                predictedTranslation: CGSize(width: -130, height: 10)
            ),
            1
        )
        XCTAssertEqual(
            PlannerRegionPaging.destinationIndex(
                from: 1,
                regionCount: 3,
                translation: CGSize(width: 70, height: 8),
                predictedTranslation: CGSize(width: 130, height: 10)
            ),
            0
        )
        XCTAssertEqual(
            PlannerRegionPaging.destinationIndex(
                from: 1,
                regionCount: 3,
                translation: CGSize(width: 20, height: 90),
                predictedTranslation: CGSize(width: 30, height: 140)
            ),
            1
        )
        XCTAssertEqual(
            PlannerRegionPaging.destinationIndex(
                from: 2,
                regionCount: 3,
                translation: CGSize(width: -100, height: 0),
                predictedTranslation: CGSize(width: -180, height: 0)
            ),
            2
        )
    }

    func testPlannerRegionSelectionIsRetainedPerCanvasAndFallsBackSafely() {
        let firstCanvasID = CanvasID()
        let secondCanvasID = CanvasID()
        let dailyRegions = PlannerRegionCatalog.regions(for: .dailyPlanner)
        var selection = PlannerRegionSelection()

        selection.select(regionID: "parking-lot", for: firstCanvasID)
        selection.select(regionID: "today", for: secondCanvasID)

        XCTAssertEqual(selection.selectedIndex(for: firstCanvasID, in: dailyRegions), 2)
        XCTAssertEqual(selection.selectedIndex(for: secondCanvasID, in: dailyRegions), 1)
        XCTAssertEqual(
            selection.selectedIndex(
                for: firstCanvasID,
                in: PlannerRegionCatalog.regions(for: .weeklyPlanner)
            ),
            0
        )
    }

    @MainActor
    func testPlannerPapersRenderAtTheirCanonicalAspectRatio() throws {
        let size = CGSize(width: 384, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        for paperType in [PaperType.dailyPlanner, .weeklyPlanner] {
            let image = renderer.image { rendererContext in
                PaperRenderer.draw(
                    paperType,
                    in: rendererContext.cgContext,
                    bounds: CGRect(origin: .zero, size: size)
                )
            }
            XCTAssertNotNil(image.pngData())
            let attachment = XCTAttachment(image: image)
            attachment.name = paperType.displayName
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
