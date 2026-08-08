import XCTest

@MainActor
final class LayerPanelUITests: XCTestCase {
    func testLayersPanelCreatesAndSwitchesTheEditingLayer() {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"]
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Show more tools"].tap()

        let expandedTools = application.scrollViews["Expanded tools"]
        for _ in 0..<5 where !application.buttons["Layers"].isHittable {
            expandedTools.swipeUp()
        }
        XCTAssertTrue(application.buttons["Layers"].isHittable)
        application.buttons["Layers"].tap()

        let firstLayer = application.buttons["Layer 1"]
        XCTAssertTrue(firstLayer.waitForExistence(timeout: 2))
        XCTAssertTrue((firstLayer.value as? String)?.contains("Active") == true)

        application.buttons["New layer"].tap()
        let secondLayer = application.buttons["Layer 2"]
        XCTAssertTrue(secondLayer.waitForExistence(timeout: 2))
        XCTAssertTrue((secondLayer.value as? String)?.contains("Active") == true)

        firstLayer.tap()
        XCTAssertTrue((firstLayer.value as? String)?.contains("Active") == true)
        XCTAssertFalse((secondLayer.value as? String)?.contains("Active") == true)
        XCTAssertTrue(application.buttons["Hide Layer 1"].exists)
    }
}
