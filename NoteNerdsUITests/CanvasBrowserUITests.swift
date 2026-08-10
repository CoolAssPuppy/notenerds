import XCTest

@MainActor
final class CanvasBrowserUITests: XCTestCase {
    func testCanvasesHeaderNamesItsNotebookAndSharesOneNavigationBarLevel() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Notebook title, Untitled notebook"].tap()
        let notebookTitle = application.textFields["Notebook title"]
        XCTAssertTrue(notebookTitle.waitForExistence(timeout: 2))
        notebookTitle.typeText("Project Atlas\n")
        application.buttons["Canvases"].tap()

        let expectedTitle = "Canvases for Project Atlas"
        let navigationBar = application.navigationBars[expectedTitle]
        let title = navigationBar.staticTexts[expectedTitle]
        let done = navigationBar.buttons["Done"]

        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(done.exists)
        XCTAssertEqual(title.frame.midY, done.frame.midY, accuracy: 2)
    }

    func testLongPressAndTrailingMenuShareCanvasActionsAndRenameInline() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Canvases"].tap()

        let firstCanvas = application.buttons["Canvas thumbnail, Canvas 1"]
        firstCanvas.press(forDuration: 1)
        assertPrimaryActions(in: application)
        application.buttons["Rename canvas"].tap()

        let nameField = application.textFields["Canvas name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Project ideas\n")

        let renamedCanvas = application.buttons["Canvas thumbnail, Project ideas"]
        XCTAssertTrue(renamedCanvas.waitForExistence(timeout: 2))
        application.buttons["Canvas actions, Project ideas"].tap()
        assertPrimaryActions(in: application)
    }

    func testTrailingMenuDuplicatesCanvasAndChangesPaper() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Canvases"].tap()

        application.buttons["Canvas actions, Canvas 1"].tap()
        application.buttons["Duplicate canvas"].tap()
        let canvasThumbnails = application.buttons.matching(
            NSPredicate(format: "label == 'Canvas thumbnail, Canvas 1'")
        )
        XCTAssertEqual(canvasThumbnails.count, 2)

        application.buttons["Canvas actions, Canvas 1"].firstMatch.tap()
        hittableButton("Change paper", in: application).tap()
        application.buttons["Paper, Dot large"].tap()
        application.buttons["Apply"].tap()
        let paperDescription = application.buttons["Canvas thumbnail, Canvas 1"].firstMatch.value as? String
        XCTAssertTrue(paperDescription?.contains("Dot large") == true)
    }

    private func assertPrimaryActions(in application: XCUIApplication) {
        XCTAssertTrue(application.buttons["Rename canvas"].exists)
        XCTAssertTrue(application.buttons["Duplicate canvas"].exists)
        XCTAssertTrue(application.buttons["Change paper"].exists)
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
