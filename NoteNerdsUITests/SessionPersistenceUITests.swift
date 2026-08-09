import XCTest

@MainActor
final class SessionPersistenceUITests: XCTestCase {
    func testImmediateDrawingAfterAddingCanvasCannotOverwriteEarlierCanvas() {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"]
        application.launch()

        application.buttons["New notebook"].tap()
        enableFingerDrawing(in: application)
        application.buttons["New canvas"].tap()
        application.buttons["Create"].tap()

        let canvas = application.scrollViews["Infinite canvas"]
        drawStroke(on: canvas, from: CGVector(dx: 0.30, dy: 0.35), to: CGVector(dx: 0.46, dy: 0.41))
        waitForStrokeCount(1, on: canvas)
        drawStroke(on: canvas, from: CGVector(dx: 0.36, dy: 0.50), to: CGVector(dx: 0.55, dy: 0.58))
        waitForStrokeCount(2, on: canvas)

        application.buttons["Notebook title, Untitled notebook"].tap()
        let titleField = application.textFields["Notebook title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.typeText("Canvas safety\n")
        application.buttons["New canvas"].tap()
        application.buttons["Create"].tap()

        drawStroke(on: canvas, from: CGVector(dx: 0.60, dy: 0.40), to: CGVector(dx: 0.74, dy: 0.48))
        waitForStrokeCount(1, on: canvas)
        XCTAssertEqual(application.buttons["Canvas browser"].value as? String, "3 of 3")

        openCanvas("Canvas 2", in: application)
        waitForStrokeCount(2, on: canvas)
        openCanvas("Canvas 3", in: application)
        waitForStrokeCount(1, on: canvas)

        application.buttons["Library"].tap()
        XCTAssertTrue(application.buttons["Notebook, Canvas safety"].waitForExistence(timeout: 2))
        application.buttons["Notebook, Canvas safety"].tap()

        XCTAssertEqual(application.buttons["Canvas browser"].value as? String, "3 of 3")
        waitForStrokeCount(1, on: canvas)
        openCanvas("Canvas 2", in: application)
        waitForStrokeCount(2, on: canvas)
    }

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

    private func enableFingerDrawing(in application: XCUIApplication) {
        application.buttons["Drawing tools"].tap()
        let drawWithFinger = application.switches["Draw with finger"]
        XCTAssertTrue(drawWithFinger.waitForExistence(timeout: 2))
        drawWithFinger.tap()
        application.buttons["Ballpoint"].tap()
    }

    private func drawStroke(on canvas: XCUIElement, from start: CGVector, to end: CGVector) {
        canvas.coordinate(withNormalizedOffset: start).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: end)
        )
    }

    private func waitForStrokeCount(_ count: Int, on canvas: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "\(count) ink stroke"),
            object: canvas
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    private func openCanvas(_ name: String, in application: XCUIApplication) {
        application.buttons["Canvas browser"].tap()
        let thumbnail = application.buttons["Canvas thumbnail, \(name)"]
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 2))
        thumbnail.tap()
    }
}
