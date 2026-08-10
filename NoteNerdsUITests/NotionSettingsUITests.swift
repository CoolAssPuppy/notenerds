import XCTest

@MainActor
final class NotionSettingsUITests: XCTestCase {
    func testSettingsKeepsPaperDefaultAndRemovesObsoleteToolbarPlacementControls() {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library", "-force-notion-unavailable"]
        application.launch()

        openSettings(in: application)

        XCTAssertTrue(application.buttons["Default paper"].waitForExistence(timeout: 2))
        XCTAssertFalse(application.staticTexts["Editing tools"].exists)
        XCTAssertFalse(application.switches["Vertical tools on left"].exists)
    }

    func testSettingsExplainsWhenNotionIsNotConfigured() {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library", "-force-notion-unavailable"]
        application.launch()

        openSettings(in: application)

        XCTAssertTrue(application.navigationBars["Settings"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            application.staticTexts["Notion is unavailable in this build"]
                .waitForExistence(timeout: 2)
        )
    }

    func testSettingsShowsAnICloudSyncIssue() {
        let application = XCUIApplication()
        application.launchArguments = [
            "-ui-testing", "-reset-library", "-force-notion-unavailable", "-force-sync-issue"
        ]
        application.launch()

        openSettings(in: application)

        XCTAssertTrue(
            application.staticTexts["This change is saved locally and is waiting for iCloud sync."]
                .waitForExistence(timeout: 2)
        )
    }

    func testConnectedNotionShowsSyncAndDisconnectWithoutRestore() {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library", "-force-notion-connected"]
        application.launch()

        openSettings(in: application)

        XCTAssertTrue(application.buttons["Sync now"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Disconnect Notion"].exists)
        XCTAssertFalse(application.buttons["Restore from Notion"].exists)
        XCTAssertFalse(application.buttons["Try again"].exists)
    }

    func testFailedNotionShowsRetryAndDisconnectWithoutRestore() {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library", "-force-notion-failure"]
        application.launch()

        openSettings(in: application)

        XCTAssertTrue(application.buttons["Try again"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Disconnect Notion"].exists)
        XCTAssertFalse(application.buttons["Restore from Notion"].exists)
        XCTAssertFalse(application.buttons["Sync now"].exists)
    }

    private func openSettings(in application: XCUIApplication) {
        let settings = application.buttons["Settings"]
        if !settings.exists {
            application.buttons["Note Nerds"].tap()
        }
        settings.tap()
    }
}
