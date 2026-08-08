import XCTest

@MainActor
final class RadialMenuPlacementUITests: XCTestCase {
    func testRadialMenuAnchorMatchesTheRequestedVisibleCanvasPoint() {
        let application = XCUIApplication()
        application.launchArguments = [
            "-ui-testing",
            "-reset-library",
            "-radial-menu-origin",
            "312",
            "420"
        ]
        application.launch()
        application.buttons["New notebook"].tap()

        let canvas = application.scrollViews["Infinite canvas"]
        let anchor = application.otherElements["Radial menu anchor"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 2))
        XCTAssertTrue(anchor.waitForExistence(timeout: 2))
        XCTAssertEqual(anchor.frame.midX, canvas.frame.minX + 312, accuracy: 2)
        XCTAssertEqual(anchor.frame.midY, canvas.frame.minY + 420, accuracy: 2)
    }
}
