import XCTest

@MainActor
final class SessionPersistenceUITests: XCTestCase {
    func testNotebookAndCanvasTextSurviveApplicationRelaunch() {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"]
        application.launch()

        application.buttons["New notebook"].tap()
        application.buttons["Show more tools"].tap()
        application.buttons["Add text"].tap()
        let canvas = application.scrollViews["Infinite canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.35)).tap()
        let editor = application.textViews["Canvas text editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.typeText("Saved between sessions\n")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 2))
        application.buttons["Library"].tap()
        XCTAssertTrue(application.buttons["Notebook, Untitled notebook"].waitForExistence(timeout: 2))

        application.terminate()
        application.launchArguments = ["-ui-testing"]
        application.launch()

        XCTAssertTrue(application.buttons["Notebook, Untitled notebook"].waitForExistence(timeout: 3))
        application.buttons["Notebook, Untitled notebook"].tap()
        let reopenedCanvas = application.scrollViews["Infinite canvas"]
        XCTAssertTrue(reopenedCanvas.waitForExistence(timeout: 3))
        XCTAssertTrue((reopenedCanvas.value as? String)?.contains("Saved between sessions") == true)
        application.buttons["Library"].tap()
        application.buttons["Library search button"].tap()
        let search = application.textFields["Library search"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("Saved between sessions")
        XCTAssertTrue(application.buttons["Typed text in Untitled notebook"].waitForExistence(timeout: 3))
    }
}
