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

        XCTAssertTrue(application.navigationBars["Settings"].waitForExistence(timeout: 0.5))
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

        let databaseRow = application.buttons["Notebook database, Personal Notes"]
        XCTAssertTrue(databaseRow.waitForExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Sync now"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Disconnect Notion"].exists)
        XCTAssertFalse(application.buttons["Restore from Notion"].exists)
        XCTAssertFalse(application.buttons["Try again"].exists)

        databaseRow.tap()
        XCTAssertTrue(application.navigationBars["Choose Notion location"].waitForExistence(timeout: 2))
    }

    func testSuccessfulDestinationSelectionReturnsToSettings() {
        let application = XCUIApplication()
        application.launchArguments = [
            "-ui-testing", "-reset-library", "-force-notion-destination-selection"
        ]
        application.launch()
        openSettings(in: application)

        application.buttons["Notebook database, Choose location"].tap()
        XCTAssertTrue(application.navigationBars["Choose Notion location"].waitForExistence(timeout: 2))

        application.buttons["Product, Create the Note Nerds database here"].tap()

        XCTAssertTrue(application.navigationBars["Settings"].waitForExistence(timeout: 2))
        XCTAssertFalse(application.navigationBars["Choose Notion location"].exists)
        XCTAssertTrue(
            application.buttons["Notebook database, Note Nerds"].waitForExistence(timeout: 2)
        )
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
