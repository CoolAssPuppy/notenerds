import XCTest

@MainActor
final class LibraryCreationPlacementUITests: XCTestCase {
    func testCreationControlsAndTitlesFollowTheirContent() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        let folderHeading = application.staticTexts["Folders"]
        let newFolder = application.buttons["New folder"]
        XCTAssertTrue(folderHeading.waitForExistence(timeout: 3))
        XCTAssertTrue(newFolder.exists)
        XCTAssertGreaterThan(newFolder.frame.midX, folderHeading.frame.maxX)
        XCTAssertLessThan(abs(newFolder.frame.midY - folderHeading.frame.midY), 24)

        XCTAssertTrue(application.navigationBars["My Notebooks"].exists)
        let searchButton = application.buttons["Library search button"]
        let newNotebook = application.buttons["New notebook"]
        XCTAssertTrue(searchButton.exists)
        XCTAssertTrue(newNotebook.exists)
        XCTAssertGreaterThan(newNotebook.frame.midX, searchButton.frame.midX)
        XCTAssertLessThan(newNotebook.frame.midY, application.frame.height * 0.2)

        searchButton.tap()
        let searchField = application.textFields["Library search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        XCTAssertTrue(searchButton.waitForNonExistence(timeout: 2))
        XCTAssertGreaterThan(newNotebook.frame.midX, searchField.frame.midX)
        let expandedAttachment = XCTAttachment(screenshot: application.screenshot())
        expandedAttachment.name = "Expanded library search"
        expandedAttachment.lifetime = .keepAlways
        add(expandedAttachment)

        application.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 2))
        XCTAssertFalse(searchField.exists)
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Library creation controls"
        attachment.lifetime = .keepAlways
        add(attachment)

        newFolder.tap()
        let folder = application.buttons["Folder, New folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 2))
        folder.tap()

        XCTAssertTrue(application.navigationBars["New folder"].waitForExistence(timeout: 2))
        XCTAssertTrue(newNotebook.exists)
    }

    func testFolderSortAndGlobalSwipeableCanvasStack() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        application.buttons["New folder"].tap()
        application.buttons["Folder, New folder"].tap()
        let sort = application.buttons["Sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 2))
        sort.tap()
        for option in ["A-Z", "Z-A", "Time (recent)", "Time (oldest)"] {
            XCTAssertTrue(application.buttons[option].exists)
        }
        application.buttons["Time (recent)"].tap()

        application.buttons["New notebook"].tap()
        for _ in 0..<2 {
            application.buttons["New canvas"].tap()
            application.buttons["Create"].tap()
        }
        application.buttons["Library"].tap()
        application.staticTexts["My Notebooks"].tap()

        XCTAssertTrue(application.buttons["Notebook, Untitled notebook"].waitForExistence(timeout: 2))
        let preview = application.descendants(matching: .any)["Canvas previews"]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        XCTAssertEqual(preview.value as? String, "Canvas 1 of 3")
        preview.swipeLeft()
        let secondCanvas = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Canvas 2 of 3"),
            object: preview
        )
        XCTAssertEqual(XCTWaiter.wait(for: [secondCanvas], timeout: 2), .completed)
        XCTAssertGreaterThan(
            application.staticTexts.matching(
                NSPredicate(format: "label == 'now' OR label ENDSWITH 'ago'")
            ).count,
            0
        )
    }

    private func makeApplication() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"]
        return application
    }
}
