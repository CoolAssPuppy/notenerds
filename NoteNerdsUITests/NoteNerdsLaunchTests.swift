import XCTest
@MainActor
final class NoteNerdsLaunchTests: XCTestCase {
    func testApplicationLaunchesIntoLibrary() {
        let application = makeApplication()
        application.launch()
        let didShowLibraryTitle = application.staticTexts["Note Nerds"].waitForExistence(timeout: 3)
        XCTAssertTrue(didShowLibraryTitle)
    }

    func testCreateNotebookAndAddCanvasWorkflow() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        XCTAssertTrue(application.staticTexts["Untitled notebook"].waitForExistence(timeout: 3))
        application.buttons["New canvas"].tap()
        application.buttons["Create"].tap()
        XCTAssertEqual(application.buttons["Canvas browser"].value as? String, "2 of 2")
        application.buttons["Library"].tap()
        XCTAssertTrue(application.buttons["Notebook, Untitled notebook"].waitForExistence(timeout: 2))
    }

    func testCreateFolderWorkflow() {
        let application = makeApplication()
        application.launch()

        application.buttons["New folder"].tap()

        XCTAssertTrue(application.buttons["Folder, New folder"].waitForExistence(timeout: 2))
    }

    func testFoldersStayInSidebarAndDetailShowsNotebookPreviewsOnly() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()
        application.buttons["New folder"].tap()

        let folder = application.buttons["Folder, New folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 2))
        XCTAssertLessThan(folder.frame.maxX, application.frame.width * 0.35)

        folder.tap()
        application.buttons["New notebook"].tap()
        application.buttons["Library"].tap()

        let notebook = application.buttons["Notebook, Untitled notebook"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 2))
        XCTAssertTrue(folder.exists)
        XCTAssertLessThan(folder.frame.maxX, notebook.frame.minX)

        application.buttons["Hide Sidebar"].tap()
        XCTAssertTrue(folder.waitForNonExistence(timeout: 2))
        application.buttons["Show Sidebar"].tap()
        XCTAssertTrue(folder.waitForExistence(timeout: 2))
    }

    func testCanvasBrowserShowsCanvasThumbnails() {
        let application = makeApplication()
        application.launch()

        application.buttons["New notebook"].tap()
        application.buttons["New canvas"].tap()
        application.buttons["Create"].tap()
        application.buttons["Canvas browser"].tap()

        XCTAssertTrue(application.buttons["Canvas thumbnail, Canvas 1"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Canvas thumbnail, Canvas 2"].exists)
    }

    func testMultipleLibraryItemsCanMoveToTrashTogether() {
        let application = makeApplication()
        application.launch()
        application.buttons["New folder"].tap()
        application.buttons["New notebook"].tap()
        application.buttons["Library"].tap()

        application.buttons["More"].tap()
        application.buttons["Select"].tap()
        application.buttons["Folder, New folder"].tap()
        application.buttons["Notebook, Untitled notebook"].tap()
        application.buttons["More"].tap()
        application.buttons["Move selected to Trash"].tap()

        XCTAssertTrue(application.buttons["Folder, New folder"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Notebook, Untitled notebook"].waitForNonExistence(timeout: 2))
    }

    func testWritingToolEraserHistoryAndSelectionControls() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["More"].firstMatch.tap()
        application.buttons["Draw with finger"].tap()
        application.buttons["Drawing tools"].tap()
        application.buttons["Highlighter"].tap()
        XCTAssertEqual(application.buttons["Drawing tools"].value as? String, "Highlighter")

        let canvas = application.scrollViews["Infinite canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 2))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.45)).press(
            forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.55))
        )
        let strokeAppeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS '1 ink stroke'"),
            object: canvas
        )
        XCTAssertEqual(XCTWaiter.wait(for: [strokeAppeared], timeout: 3), .completed)
        application.buttons["Undo"].tap()
        application.buttons["Redo"].tap()
        application.buttons["Eraser"].tap()
        application.buttons["Object eraser"].tap()
        XCTAssertEqual(application.buttons["Drawing tools"].value as? String, "Highlighter")
        canvas.tap()
        application.buttons["Lasso"].tap()
        application.buttons["Selection actions"].tap()
        XCTAssertTrue(application.buttons["Convert handwriting to text"].exists)
    }

    func testTypedTextCanBeFoundAndOpenedFromLibrarySearch() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Add text"].tap()
        let editor = application.textViews["Canvas text editor"]
        XCTAssertEqual(application.buttons["Add text"].value as? String, "Selected")
        XCTAssertFalse(editor.exists)
        let canvas = application.scrollViews["Infinite canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.35)).tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertLessThan(editor.frame.height, 80)
        XCTAssertTrue(application.buttons["Font"].exists)
        XCTAssertFalse(application.navigationBars["Add text"].exists)
        editor.tap()
        editor.typeText("Quarterly pricing review")
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Professional inline text"
        attachment.lifetime = .keepAlways
        add(attachment)
        application.buttons["Finish text editing"].tap()
        application.buttons["Library"].tap()
        application.buttons["Library search button"].tap()
        let search = application.textFields["Library search"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("pricing")

        let result = application.buttons["Typed text in Untitled notebook"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.tap()
        XCTAssertTrue(application.scrollViews["Infinite canvas"].waitForExistence(timeout: 2))
    }

    func testExistingTextReopensInlineOnTheCanvas() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Add text"].tap()
        let canvas = application.scrollViews["Infinite canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.35)).tap()
        let editor = application.textViews["Canvas text editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.typeText("Existing note")
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Inline canvas text editor"
        attachment.lifetime = .keepAlways
        add(attachment)
        application.buttons["Finish text editing"].tap()

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.39)).tap()

        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        XCTAssertEqual(editor.value as? String, "Existing note")
        XCTAssertFalse(application.navigationBars["Edit text"].exists)
    }

    func testReturnCommitsInlineText() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Add text"].tap()
        let canvas = application.scrollViews["Infinite canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.35)).tap()

        let editor = application.textViews["Canvas text editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.typeText("Return commits this text\n")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 2))
        XCTAssertTrue((canvas.value as? String)?.contains("1 other objects") == true)
    }

    func testCommittedTextRemainsVisibleOnCanvas() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Add text"].tap()
        let canvas = application.scrollViews["Infinite canvas"]
        let insertion = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.35))
        let textFrame = CGRect(
            x: canvas.frame.minX + canvas.frame.width * 0.55,
            y: canvas.frame.minY + canvas.frame.height * 0.35,
            width: 260,
            height: 44
        )
        let beforeScreenshot = application.screenshot()
        let pixelsBeforeEditing = beforeScreenshot.image.darkPixelCount(in: textFrame)

        insertion.tap()
        let editor = application.textViews["Canvas text editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 2))
        editor.typeText("Visible canvas text\n")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 2))

        let afterScreenshot = application.screenshot()
        let pixelsAfterCommit = afterScreenshot.image.darkPixelCount(in: textFrame)
        let attachment = XCTAttachment(screenshot: afterScreenshot)
        attachment.name = "Committed canvas text"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(pixelsAfterCommit, pixelsBeforeEditing + 40)
    }

    func testDeletedNotebookCanBeRestoredFromTrash() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Library"].tap()
        application.buttons["More"].tap()
        application.buttons["Select"].tap()
        application.buttons["Notebook, Untitled notebook"].tap()
        application.buttons["More"].tap()
        application.buttons["Move selected to Trash"].tap()
        application.staticTexts["Trash"].tap()
        let trashedNotebook = application.buttons["Notebook, Untitled notebook"]
        XCTAssertTrue(trashedNotebook.waitForExistence(timeout: 2))
        application.buttons["More"].tap()
        application.buttons["Select"].tap()
        trashedNotebook.tap()
        application.buttons["More"].tap()
        application.buttons["Restore selected"].tap()
        application.staticTexts["My Notebooks"].tap()
        XCTAssertTrue(application.buttons["Notebook, Untitled notebook"].waitForExistence(timeout: 2))
    }

    func testNotebookDragsFromPreviewIntoFolderAndTrash() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()
        application.buttons["New folder"].tap()
        application.buttons["New notebook"].tap()
        application.buttons["Library"].tap()
        let folder = application.buttons["Folder, New folder"]
        let rootNotebook = application.buttons["Notebook, Untitled notebook"]
        XCTAssertTrue(folder.waitForExistence(timeout: 2))
        XCTAssertTrue(rootNotebook.waitForExistence(timeout: 2))
        rootNotebook.press(forDuration: 1, thenDragTo: folder)
        folder.tap()
        let folderNotebook = application.buttons["Notebook, Untitled notebook"]
        XCTAssertTrue(folderNotebook.waitForExistence(timeout: 2))
        folderNotebook.press(forDuration: 1, thenDragTo: application.staticTexts["Trash"])
        application.staticTexts["Trash"].tap()
        let trashedNotebook = application.buttons["Notebook, Untitled notebook"]
        XCTAssertTrue(trashedNotebook.waitForExistence(timeout: 2))
        XCTAssertTrue((trashedNotebook.value as? String)?.contains("Dashed outline") == true)
    }

    func testLibraryVisualLayoutInLandscape() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()

        application.buttons["New folder"].tap()
        application.buttons["New notebook"].tap()
        application.buttons["Library"].tap()

        XCTAssertTrue(application.staticTexts["Note Nerds"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Library landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCanvasMoreMenuVisualLayout() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["More"].firstMatch.tap()

        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Canvas More menu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCanvasVisualLayoutUsesGroupedIconControls() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()

        XCTAssertTrue(application.buttons["Drawing tools"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Stroke width"].exists)
        XCTAssertTrue(application.buttons["Eraser"].exists)
        XCTAssertTrue(application.buttons["Canvas browser"].exists)
        XCTAssertTrue(application.buttons["New canvas"].exists)
        XCTAssertTrue(application.buttons["Share"].exists)

        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Canvas grouped icon controls"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testOrganizationActionsStayInTheLibrarySidebar() {
        let application = makeApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        application.launch()
        let newFolder = application.buttons["New folder"]
        let newNotebook = application.buttons["New notebook"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 2))
        XCTAssertTrue(newNotebook.exists)
        XCTAssertLessThan(newFolder.frame.maxX, application.frame.width * 0.3)
        XCTAssertGreaterThan(newNotebook.frame.minX, application.frame.width * 0.5)
        XCTAssertLessThan(newFolder.frame.midY, application.frame.height * 0.5)
        XCTAssertLessThan(newNotebook.frame.midY, application.frame.height * 0.2)

        application.buttons["More"].tap()
        XCTAssertTrue(application.buttons["Select"].exists)
        XCTAssertTrue(application.buttons["Sort"].exists)
        XCTAssertTrue(application.buttons["App settings"].exists)
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Apple standard library sidebar"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNotebookUsesStandardNavigationAndEditingGroups() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()

        XCTAssertTrue(application.navigationBars["Untitled notebook"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Library"].exists)
        XCTAssertTrue(application.buttons["Canvas browser"].exists)
        XCTAssertTrue(application.buttons["New canvas"].exists)
        XCTAssertTrue(application.buttons["Share"].exists)
        XCTAssertTrue(application.buttons["More"].exists)
        XCTAssertFalse(application.buttons["Quick tools"].exists)

        let drawingTools = application.buttons["Drawing tools"]
        let eraser = application.buttons["Eraser"]
        let lasso = application.buttons["Lasso"]
        let addText = application.buttons["Add text"]
        XCTAssertTrue(drawingTools.exists)
        XCTAssertLessThan(drawingTools.frame.midY, eraser.frame.midY)
        XCTAssertLessThan(eraser.frame.midY, lasso.frame.midY)
        XCTAssertLessThan(lasso.frame.midY, addText.frame.midY)

        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Apple standard notebook editor"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNotebookTitleEditsInPlaceWithoutADialog() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()

        application.buttons["Notebook title, Untitled notebook"].tap()
        let titleField = application.textFields["Notebook title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        XCTAssertEqual(application.alerts.count, 0)
        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: titleField
        )
        XCTAssertEqual(XCTWaiter.wait(for: [focusExpectation], timeout: 2), .completed)

        titleField.typeText("Project Atlas\n")

        XCTAssertTrue(titleField.waitForNonExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Notebook title, Project Atlas"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Canvas browser"].exists)
        XCTAssertEqual(application.alerts.count, 0)
        application.buttons["Library"].tap()
        XCTAssertTrue(application.buttons["Notebook, Project Atlas"].waitForExistence(timeout: 2))
    }

    func testCanvasToolsHonorTheHorizontalAppSetting() {
        let application = makeApplication(additionalArguments: ["-canvasToolbarOrientation", "horizontal"])
        application.launch()
        application.buttons["New notebook"].tap()

        let drawingTools = application.buttons["Drawing tools"]
        let strokeWidth = application.buttons["Stroke width"]
        XCTAssertTrue(drawingTools.waitForExistence(timeout: 2))
        XCTAssertTrue(strokeWidth.exists)
        XCTAssertEqual(drawingTools.frame.midY, strokeWidth.frame.midY, accuracy: 2)
        XCTAssertGreaterThan(strokeWidth.frame.midX, drawingTools.frame.midX)
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = "Horizontal canvas tools"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDrawingOptionsUseVisualAppleStyleInspectors() {
        let application = makeApplication()
        application.launch()
        application.buttons["New notebook"].tap()

        application.buttons["Drawing tools"].tap()
        let ballpoint = application.buttons["Ballpoint"]
        let fineliner = application.buttons["Fineliner"]
        let mechanicalPencil = application.buttons["Mechanical pencil"]
        XCTAssertTrue(ballpoint.exists)
        XCTAssertEqual(ballpoint.frame.midY, fineliner.frame.midY, accuracy: 2)
        XCTAssertEqual(fineliner.frame.midY, mechanicalPencil.frame.midY, accuracy: 2)
        let toolsAttachment = XCTAttachment(screenshot: application.screenshot())
        toolsAttachment.name = "Apple writing tools inspector"
        toolsAttachment.lifetime = .keepAlways
        add(toolsAttachment)
        application.scrollViews["Infinite canvas"].tap()

        application.buttons["Ink color"].tap()
        XCTAssertTrue(application.buttons["Black"].exists)
        XCTAssertTrue(application.buttons["Orange"].exists)
        XCTAssertTrue(application.buttons["Green"].exists)
        XCTAssertTrue(application.buttons["Purple"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["Custom color"].exists)
        let colorAttachment = XCTAttachment(screenshot: application.screenshot())
        colorAttachment.name = "Apple color inspector"
        colorAttachment.lifetime = .keepAlways
        add(colorAttachment)

        application.scrollViews["Infinite canvas"].tap()
        application.buttons["Stroke width"].tap()
        for width in ["Extra fine", "Fine", "Medium", "Bold", "Extra bold"] {
            XCTAssertTrue(application.buttons[width].exists)
        }
        let widthAttachment = XCTAttachment(screenshot: application.screenshot())
        widthAttachment.name = "Apple thickness inspector"
        widthAttachment.lifetime = .keepAlways
        add(widthAttachment)

        application.scrollViews["Infinite canvas"].tap()
        application.buttons["Eraser"].tap()
        XCTAssertTrue(application.buttons["Object eraser"].exists)
        XCTAssertTrue(application.buttons["Pixel eraser"].exists)
        application.buttons["Pixel eraser"].tap()
        for width in ["Extra fine", "Fine", "Medium", "Bold", "Extra bold"] {
            XCTAssertTrue(application.buttons[width].exists)
        }
        let eraserAttachment = XCTAttachment(screenshot: application.screenshot())
        eraserAttachment.name = "Apple eraser inspector"
        eraserAttachment.lifetime = .keepAlways
        add(eraserAttachment)
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApplication().launch()
        }
    }

    private func makeApplication(additionalArguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"] + additionalArguments
        return application
    }
}

private extension UIImage {
    func darkPixelCount(in pointRect: CGRect) -> Int {
        guard let source = cgImage else { return 0 }
        let horizontalScale = CGFloat(source.width) / size.width
        let verticalScale = CGFloat(source.height) / size.height
        let pixelRect = CGRect(
            x: pointRect.minX * horizontalScale,
            y: pointRect.minY * verticalScale,
            width: pointRect.width * horizontalScale,
            height: pointRect.height * verticalScale
        ).integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let cropped = source.cropping(to: pixelRect), pixelRect.width > 0, pixelRect.height > 0 else { return 0 }
        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels.count { $0 < 96 }
    }
}
