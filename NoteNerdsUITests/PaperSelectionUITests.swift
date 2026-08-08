import XCTest

@MainActor
final class PaperSelectionUITests: XCTestCase {
    private let paperNames = [
        "Blank white", "Blank cream", "Grid large", "Grid small",
        "Dot large", "Dot small", "Yellow legal pad", "White legal pad"
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
        application.buttons["Done"].tap()

        application.buttons["New notebook"].tap()
        let legalCanvasScreenshot = XCTAttachment(screenshot: application.screenshot())
        legalCanvasScreenshot.name = "Yellow legal canvas"
        legalCanvasScreenshot.lifetime = .keepAlways
        add(legalCanvasScreenshot)
        application.buttons["Canvas browser"].tap()
        let firstCanvas = application.buttons["Canvas thumbnail, Canvas 1"]
        XCTAssertTrue(firstCanvas.waitForExistence(timeout: 2))
        XCTAssertTrue((firstCanvas.value as? String)?.contains("Yellow legal pad") == true)
        application.buttons["Done"].tap()

        application.buttons["New canvas"].tap()
        assertPaperGallery(in: application)
        application.buttons["Paper, Grid small"].tap()
        application.buttons["Create"].tap()
        application.buttons["Canvas browser"].tap()
        let secondCanvas = application.buttons["Canvas thumbnail, Canvas 2"]
        XCTAssertTrue(secondCanvas.waitForExistence(timeout: 2))
        XCTAssertTrue((secondCanvas.value as? String)?.contains("Grid small") == true)

        firstCanvas.press(forDuration: 1)
        application.buttons["Change paper"].tap()
        assertPaperGallery(in: application)
        application.buttons["Paper, Dot large"].tap()
        application.buttons["Apply"].tap()
        XCTAssertTrue((firstCanvas.value as? String)?.contains("Dot large") == true)
    }

    private func assertPaperGallery(in application: XCUIApplication) {
        XCTAssertTrue(application.navigationBars["Paper"].waitForExistence(timeout: 2))
        for paperName in paperNames {
            XCTAssertTrue(application.buttons["Paper, \(paperName)"].exists)
        }
    }

    private func makeApplication() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library", "-defaultPaperType", "blankWhite"]
        return application
    }
}
