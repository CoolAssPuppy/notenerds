import XCTest

@MainActor
final class ShapeToolbarUITests: XCTestCase {
    func testHeldHighlighterStaysInkAndKeepsWritingUnderneath() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        let canvas = application.scrollViews["Infinite canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.45)).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.45))
        )
        application.buttons["Drawing tools"].tap()
        XCTAssertTrue(application.buttons["Highlighter"].waitForExistence(timeout: 2))
        application.buttons["Highlighter"].tap()

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.45)).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.45)),
            withVelocity: .default,
            thenHoldForDuration: 0.7
        )

        let highlightRemainedInk = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS '2 ink strokes'"),
            object: canvas
        )
        XCTAssertEqual(XCTWaiter.wait(for: [highlightRemainedInk], timeout: 3), .completed)
        XCTAssertTrue((canvas.value as? String)?.contains("0 other objects") == true)
    }

    func testCompactLassoMovesInkAndPersistsItAfterRelaunch() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()

        XCTAssertTrue(application.buttons["Lasso"].waitForExistence(timeout: 2))
        let canvas = application.scrollViews["Infinite canvas"]
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.42))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.48))
        start.press(forDuration: 0.1, thenDragTo: end)
        let strokeAppeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS '1 ink strokes'"),
            object: canvas
        )
        XCTAssertEqual(XCTWaiter.wait(for: [strokeAppeared], timeout: 3), .completed)

        application.buttons["Lasso"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.38)).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.54))
        )

        XCTAssertEqual(application.buttons["Selection actions"].value as? String, "Selection active")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.45)).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.60))
        )
        application.buttons["Library"].tap()
        XCTAssertTrue(application.buttons["Notebook, Untitled notebook"].waitForExistence(timeout: 3))

        application.terminate()
        application.launchArguments = ["-ui-testing"]
        application.launch()
        application.buttons["Notebook, Untitled notebook"].tap()
        let reopenedCanvas = application.scrollViews["Infinite canvas"]
        XCTAssertTrue(reopenedCanvas.waitForExistence(timeout: 3))
        XCTAssertTrue((reopenedCanvas.value as? String)?.contains("1 ink strokes") == true)
    }

    func testShapeToolCreatesAndSelectsAClassicShapeOnTheCanvas() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Show more tools"].tap()
        application.buttons["Shapes"].tap()

        for shape in ["Line", "Arrow", "Rectangle", "Square", "Circle", "Ellipse", "Triangle"] {
            XCTAssertTrue(application.buttons[shape].exists)
        }

        application.buttons["Rectangle"].tap()
        XCTAssertEqual(application.buttons["Shapes"].value as? String, "Rectangle")
        let canvas = application.scrollViews["Infinite canvas"]
        let insertionPoint = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.42))
        insertionPoint.tap()

        let shapeAppeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS '1 other objects'"),
            object: canvas
        )
        XCTAssertEqual(XCTWaiter.wait(for: [shapeAppeared], timeout: 3), .completed)
        insertionPoint.tap()
        XCTAssertTrue(application.buttons["Selection actions"].waitForExistence(timeout: 2))
    }

    func testExpandedToolbarScrollsWhileChevronRemainsVisible() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Show more tools"].tap()

        let tools = application.scrollViews["Expanded tools"]
        let chevron = application.buttons["Show fewer tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 2))
        XCTAssertTrue(chevron.exists)
        let chevronFrame = chevron.frame

        for _ in 0..<6 where !application.buttons["Layers"].isHittable {
            tools.swipeUp()
        }

        XCTAssertTrue(chevron.exists)
        XCTAssertEqual(chevron.frame.midX, chevronFrame.midX, accuracy: 1)
        XCTAssertEqual(chevron.frame.midY, chevronFrame.midY, accuracy: 1)
        XCTAssertTrue(application.buttons["Layers"].isHittable)
    }

    private func makeApplication() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"]
        return application
    }
}
