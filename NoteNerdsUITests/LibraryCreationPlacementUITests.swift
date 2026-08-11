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

        application.staticTexts["Favorites"].tap()
        XCTAssertTrue(searchButton.waitForExistence(timeout: 2))
        XCTAssertFalse(searchField.exists)
        application.staticTexts["My Notebooks"].tap()
        XCTAssertTrue(application.navigationBars["My Notebooks"].waitForExistence(timeout: 2))
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Library creation controls"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNewSubfolderAppearsAndCannotCreateGrandchild() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        application.buttons["New folder"].tap()
        let folder = application.buttons["Folder, New folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 2))
        folder.tap()

        XCTAssertTrue(application.navigationBars["New folder"].waitForExistence(timeout: 2))
        let newSubfolder = application.buttons["New subfolder"]
        XCTAssertTrue(newSubfolder.waitForExistence(timeout: 2))
        newSubfolder.tap()
        let childFolder = application.buttons["Subfolder, New folder"]
        XCTAssertTrue(childFolder.waitForExistence(timeout: 2))
        childFolder.tap()
        XCTAssertTrue(newSubfolder.waitForNonExistence(timeout: 2))
        XCTAssertTrue(application.buttons["New notebook"].exists)
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

    func testSidebarFoldersStayAlphabeticalWhenNotebookSortUsesTime() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        application.buttons["New folder"].tap()
        renameFolder("Folder, New folder", appending: " Alpha", in: application)
        application.buttons["New folder"].tap()
        renameFolder("Folder, New folder", appending: " zebra", in: application)

        let alphaFolder = application.buttons["Folder, New folder Alpha"]
        let zebraFolder = application.buttons["Folder, New folder zebra"]
        XCTAssertTrue(alphaFolder.waitForExistence(timeout: 2))
        XCTAssertTrue(zebraFolder.waitForExistence(timeout: 2))
        XCTAssertLessThan(alphaFolder.frame.minY, zebraFolder.frame.minY)
    }

    func testFolderEditorChangesTheNameSymbolAndColorTogether() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        application.buttons["New folder"].tap()
        let folder = application.buttons["Folder, New folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 2))
        folder.press(forDuration: 1)
        application.buttons["Edit folder"].tap()

        XCTAssertTrue(application.navigationBars["Edit folder"].waitForExistence(timeout: 2))
        let nameField = application.textFields["Folder name"]
        XCTAssertTrue(nameField.exists)
        let iconType = application.segmentedControls["Folder icon type"]
        XCTAssertTrue(iconType.exists)
        iconType.buttons["Image"].tap()
        XCTAssertTrue(application.buttons["Choose PNG or SVG"].exists)
        iconType.buttons["Symbol"].tap()
        XCTAssertTrue(application.buttons["Briefcase"].exists)
        let purpleColor = application.buttons["Purple"]
        XCTAssertTrue(purpleColor.exists)
        XCTAssertGreaterThanOrEqual(purpleColor.frame.width, 44)
        XCTAssertGreaterThanOrEqual(purpleColor.frame.height, 44)

        nameField.tap()
        nameField.typeText(" Work")
        application.buttons["Briefcase"].tap()
        purpleColor.tap()
        application.buttons["Save"].tap()

        let editedFolder = application.buttons["Folder, New folder Work"]
        XCTAssertTrue(editedFolder.waitForExistence(timeout: 2))
        XCTAssertTrue((editedFolder.value as? String)?.contains("Briefcase") == true)
    }

    func testFolderEditorSavesOneEmoji() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        application.buttons["New folder"].tap()
        let folder = application.buttons["Folder, New folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 2))
        folder.press(forDuration: 1)
        application.buttons["Edit folder"].tap()
        application.segmentedControls["Folder icon type"].buttons["Emoji"].tap()
        let emoji = "\u{1F4C1}"
        let emojiField = application.textFields["Emoji"]
        emojiField.tap()
        emojiField.typeText(emoji)
        application.buttons["Save"].tap()

        XCTAssertTrue((folder.value as? String)?.contains(emoji) == true)
    }

    func testMoveMenuNamesNestedDestinationsByTheirFolderPath() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        application.buttons["New folder"].tap()
        application.buttons["Folder, New folder"].tap()
        application.buttons["New subfolder"].tap()
        application.staticTexts["My Notebooks"].tap()
        application.buttons["New notebook"].tap()
        application.buttons["Library"].tap()
        application.buttons["Select"].tap()
        application.buttons["Notebook, Untitled notebook"].tap()
        application.buttons["Move"].tap()

        XCTAssertTrue(application.buttons["New folder"].exists)
        let nestedDestination = application.buttons["New folder / New folder"]
        XCTAssertTrue(nestedDestination.exists)
        nestedDestination.tap()
        XCTAssertTrue(application.buttons["Select"].waitForExistence(timeout: 2))
        XCTAssertFalse(application.buttons["Move"].exists)
    }

    func testFolderSelectionReportsItsStateToVoiceOver() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        application.buttons["New folder"].tap()
        let folder = application.buttons["Folder, New folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 2))
        application.buttons["Select"].tap()

        XCTAssertTrue((folder.value as? String)?.contains("Not selected") == true)
        folder.tap()
        XCTAssertTrue((folder.value as? String)?.contains("Selected") == true)
    }

    private func makeApplication() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"]
        return application
    }

    private func renameFolder(_ accessibilityLabel: String, appending suffix: String, in application: XCUIApplication) {
        let folder = application.buttons[accessibilityLabel]
        XCTAssertTrue(folder.waitForExistence(timeout: 2))
        folder.press(forDuration: 1)
        application.buttons["Edit folder"].tap()
        let nameField = application.textFields["Folder name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText(suffix)
        application.buttons["Save"].tap()
    }
}
