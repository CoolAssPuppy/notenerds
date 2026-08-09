import XCTest

@MainActor
final class ShapeToolbarUITests: XCTestCase {
    func testCompactLassoSelectsInkOnAnInkOnlyCanvas() {
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
