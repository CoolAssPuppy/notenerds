import XCTest

@MainActor
final class PaperSelectionUITests: XCTestCase {
    private let paperNames = [
        "Blank white", "Blank cream", "Grid large", "Grid small",
        "Dot large", "Dot small", "Hexagon small", "Hexagon large",
        "Yellow legal pad", "White legal pad", "Daily planner", "Weekly planner"
    ]

    func testDefaultNewCanvasAndExistingCanvasUseThePaperGallery() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        application.buttons["More"].tap()
        application.buttons["App settings"].tap()
        application.buttons["Default paper"].tap()
        assertPaperGallery(in: application)
        let galleryScreenshot = XCTAttachment(screenshot: application.screenshot())
        galleryScreenshot.name = "Paper gallery"
        galleryScreenshot.lifetime = .keepAlways
        add(galleryScreenshot)
        application.buttons["Paper, Yellow legal pad"].tap()
        application.navigationBars["Paper"].buttons["Done"].tap()
        application.navigationBars["Settings"].buttons["Done"].tap()

        application.buttons["New notebook"].tap()
        let legalCanvasScreenshot = XCTAttachment(screenshot: application.screenshot())
        legalCanvasScreenshot.name = "Yellow legal canvas"
        legalCanvasScreenshot.lifetime = .keepAlways
        add(legalCanvasScreenshot)
        application.buttons["Canvas browser"].tap()
        let firstCanvas = application.buttons["Canvas thumbnail, Canvas 1"]
        XCTAssertTrue(firstCanvas.waitForExistence(timeout: 2))
        XCTAssertTrue((firstCanvas.value as? String)?.contains("Yellow legal pad") == true)
        application.navigationBars["Canvases"].buttons["Done"].tap()

        application.buttons["New canvas"].tap()
        assertPaperGallery(in: application)
        application.buttons["Paper, Grid small"].tap()
        application.buttons["Create"].tap()
        application.buttons["Canvas browser"].tap()
        let secondCanvas = application.buttons["Canvas thumbnail, Canvas 2"]
        XCTAssertTrue(secondCanvas.waitForExistence(timeout: 2))
        XCTAssertTrue((secondCanvas.value as? String)?.contains("Grid small") == true)

        firstCanvas.press(forDuration: 1)
        hittableButton("Change paper", in: application).tap()
        assertPaperGallery(in: application)
        application.buttons["Paper, Dot large"].tap()
        application.buttons["Apply"].tap()
        XCTAssertTrue((firstCanvas.value as? String)?.contains("Dot large") == true)
    }

    private func assertPaperGallery(in application: XCUIApplication) {
        XCTAssertTrue(application.navigationBars["Paper"].waitForExistence(timeout: 2))
        let gallery = application.scrollViews.firstMatch
        for paperName in paperNames {
            for _ in 0..<4 where !application.buttons["Paper, \(paperName)"].exists {
                gallery.swipeUp()
            }
            XCTAssertTrue(application.buttons["Paper, \(paperName)"].exists)
        }
    }

    private func hittableButton(_ label: String, in application: XCUIApplication) -> XCUIElement {
        let matches = application.buttons.matching(NSPredicate(format: "label == %@", label))
        for index in 0..<matches.count {
            let candidate = matches.element(boundBy: index)
            if candidate.isHittable { return candidate }
        }
        return matches.firstMatch
    }

    private func makeApplication() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"]
        return application
    }
}
