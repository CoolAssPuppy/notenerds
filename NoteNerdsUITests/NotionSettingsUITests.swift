import XCTest

@MainActor
final class NotionSettingsUITests: XCTestCase {
    func testSettingsExplainsWhenNotionIsNotConfigured() {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library", "-force-notion-unavailable"]
        application.launch()

        application.buttons["More"].firstMatch.tap()
        application.buttons["App settings"].tap()

        XCTAssertTrue(application.navigationBars["Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            application.staticTexts["Notion is unavailable in this build"]
                .waitForExistence(timeout: 2)
        )
    }
}
