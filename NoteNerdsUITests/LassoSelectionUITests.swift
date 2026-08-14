import XCTest

@MainActor
final class LassoSelectionUITests: XCTestCase {
    func testLassoGrabsInkAfterTheCanvasIsZoomedIn() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        let canvas = application.scrollViews["Infinite canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.46, dy: 0.46)).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.54, dy: 0.50))
        )
        let strokeAppeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS '1 ink strokes'"),
            object: canvas
        )
        XCTAssertEqual(XCTWaiter.wait(for: [strokeAppeared], timeout: 3), .completed)

        canvas.pinch(withScale: 2.2, velocity: 1.4)
        application.buttons["Lasso"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.30)).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.68))
        )

        XCTAssertEqual(application.buttons["Selection actions"].value as? String, "Selection active")
    }

    func testLassoedInkMovesWhenTheSelectionIsDragged() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        let canvas = application.scrollViews["Infinite canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.30)).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.34))
        )
        let strokeAppeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS '1 ink strokes'"),
            object: canvas
        )
        XCTAssertEqual(XCTWaiter.wait(for: [strokeAppeared], timeout: 3), .completed)
        let canvasFrame = canvas.frame
        let sourceRegion = region(in: canvasFrame, x: 0.26, y: 0.24, width: 0.20, height: 0.16)
        let destinationRegion = region(in: canvasFrame, x: 0.52, y: 0.52, width: 0.20, height: 0.16)
        let inkBeforeMove = screenshotImage(application).darkPixelCount(in: sourceRegion)
        XCTAssertGreaterThan(inkBeforeMove, 0, "The stroke should be drawn in the source region")

        application.buttons["Lasso"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.20)).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.42))
        )
        XCTAssertEqual(application.buttons["Selection actions"].value as? String, "Selection active")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.32)).press(
            forDuration: 0.3,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.61, dy: 0.60)),
            withVelocity: .slow,
            thenHoldForDuration: 0.4
        )

        let moved = screenshotImage(application)
        XCTAssertGreaterThan(
            moved.darkPixelCount(in: destinationRegion),
            0,
            "The ink should arrive where it was dragged"
        )
        XCTAssertEqual(moved.darkPixelCount(in: sourceRegion), 0, "The ink should leave where it started")
    }

    private func region(
        in canvasFrame: CGRect,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        CGRect(
            x: canvasFrame.minX + canvasFrame.width * x,
            y: canvasFrame.minY + canvasFrame.height * y,
            width: canvasFrame.width * width,
            height: canvasFrame.height * height
        )
    }

    private func screenshotImage(_ application: XCUIApplication) -> UIImage {
        XCUIScreen.main.screenshot().image
    }

    private func makeApplication() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"]
        return application
    }
}
