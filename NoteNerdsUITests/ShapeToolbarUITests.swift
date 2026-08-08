import XCTest

@MainActor
final class ShapeToolbarUITests: XCTestCase {
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
