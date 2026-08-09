import XCTest

@MainActor
final class PlannerRegionPagerUITests: XCTestCase {
    func testDailyPlannerPageControlChangesRegionsAndKeepsSelectionAfterRotation() {
        let application = XCUIApplication()
        application.launchArguments = [
            "-ui-testing",
            "-reset-library",
            "-force-phone-planner-pager",
            "-disable-simulator-finger-drawing"
        ]
        XCUIDevice.shared.orientation = .portrait
        application.launch()

        application.buttons["New notebook"].tap()
        application.buttons["New canvas"].tap()
        choosePaper("Daily planner", in: application)
        application.buttons["Create"].tap()

        let pageControl = application.pageIndicators["Planner sections"]
        XCTAssertTrue(pageControl.waitForExistence(timeout: 3))
        XCTAssertEqual(pageControl.value as? String, "1 of 3, Freeform")

        pageControl.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(pageControl.value as? String, "2 of 3, Today")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(pageControl.value as? String, "2 of 3, Today")

        pageControl.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(pageControl.value as? String, "3 of 3, Parking lot")
    }

    func testPlannerPaperAndTextRemainOnTheLastViewedCanvasAfterRelaunch() {
        let application = XCUIApplication()
        application.launchArguments = [
            "-ui-testing",
            "-reset-library"
        ]
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["New canvas"].tap()
        choosePaper("Daily planner", in: application)
        application.buttons["Create"].tap()

        let canvas = application.scrollViews["Infinite canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 2))
        XCTAssertTrue((canvas.value as? String)?.contains("Paper: Daily planner") == true)

        application.buttons["Show more tools"].tap()
        application.buttons["Add text"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.58)).tap()
        let editor = application.textViews["Canvas text editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.typeText("Planner text remains visible\n")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 2))
        XCTAssertTrue((canvas.value as? String)?.contains("Text: Planner text remains visible") == true)

        application.buttons["Library"].tap()
        application.terminate()
        application.launchArguments = ["-ui-testing"]
        application.launch()
        application.buttons["Notebook, Untitled notebook"].tap()

        XCTAssertEqual(application.buttons["Canvas browser"].value as? String, "2 of 2")
        XCTAssertTrue((canvas.value as? String)?.contains("Paper: Daily planner") == true)
        XCTAssertTrue((canvas.value as? String)?.contains("Text: Planner text remains visible") == true)
    }

    private func choosePaper(_ name: String, in application: XCUIApplication) {
        let paperButton = application.buttons["Paper, \(name)"]
        let gallery = application.scrollViews.firstMatch
        for _ in 0..<6 where !paperButton.exists {
            gallery.swipeUp()
        }
        XCTAssertTrue(paperButton.waitForExistence(timeout: 2))
        paperButton.tap()
    }
}
