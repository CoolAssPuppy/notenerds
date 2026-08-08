import XCTest

@MainActor
final class RadialPaletteUITests: XCTestCase {
    func testExpandedToolbarShowsEverySpecializedWritingToolDirectly() {
        XCUIDevice.shared.orientation = .portrait
        let application = XCUIApplication()
        application.launchArguments = ["-ui-testing", "-reset-library"]
        application.launch()
        application.buttons["New notebook"].tap()
        application.buttons["Show more tools"].tap()

        for tool in [
            "Ballpoint", "Fineliner", "Mechanical pencil", "Pencil", "Marker",
            "Highlighter", "Brush", "Calligraphy pen", "Handwriting to text"
        ] {
            XCTAssertTrue(application.buttons[tool].exists)
        }
    }

    func testLastSpecializedToolCanBeReachedAndSelectedInBothToolbarPositions() {
        for orientation in ["vertical", "horizontal"] {
            let application = XCUIApplication()
            application.launchArguments = [
                "-ui-testing", "-reset-library", "-canvasToolbarOrientation", orientation
            ]
            application.launch()
            application.buttons["New notebook"].tap()
            application.buttons["Show more tools"].tap()

            let tools = application.scrollViews["Expanded tools"]
            let handwriting = application.buttons["Handwriting to text"]
            XCTAssertTrue(tools.waitForExistence(timeout: 2))
            for _ in 0..<4 where !handwriting.isHittable {
                if orientation == "vertical" {
                    tools.swipeUp()
                } else {
                    tools.swipeLeft()
                }
            }

            XCTAssertTrue(handwriting.exists)
            handwriting.tap()
            XCTAssertEqual(
                application.buttons["Drawing tools"].value as? String,
                "Handwriting to text"
            )
            application.terminate()
        }
    }

    func testColorAndWidthStayInsideTheRadialInteractionUntilChosen() {
        let colorApplication = makeApplication()
        colorApplication.launch()
        colorApplication.buttons["New notebook"].tap()

        colorApplication.buttons["Color"].tap()
        XCTAssertTrue(colorApplication.buttons["Black"].waitForExistence(timeout: 2))
        XCTAssertTrue(colorApplication.buttons["Orange"].exists)
        XCTAssertTrue(colorApplication.buttons["Purple"].exists)
        XCTAssertTrue(colorApplication.descendants(matching: .any)["Radial custom color"].exists)
        XCTAssertFalse(colorApplication.buttons["Undo"].exists)
        XCTAssertTrue(colorApplication.otherElements["Quick tools"].exists)
        colorApplication.buttons["Back"].tap()
        XCTAssertTrue(colorApplication.buttons["Redo"].waitForExistence(timeout: 2))
        XCTAssertTrue(colorApplication.buttons["Color"].exists)
        XCTAssertFalse(colorApplication.buttons["Purple"].exists)
        colorApplication.buttons["Color"].tap()
        colorApplication.buttons["Purple"].tap()
        XCTAssertTrue(colorApplication.otherElements["Quick tools"].waitForNonExistence(timeout: 2))

        let widthApplication = makeApplication()
        widthApplication.launch()
        widthApplication.buttons["New notebook"].tap()
        widthApplication.buttons["Width"].tap()
        for width in ["Extra fine", "Fine", "Medium", "Bold", "Extra bold"] {
            XCTAssertTrue(widthApplication.buttons[width].exists)
        }
        widthApplication.buttons["Bold"].tap()
        XCTAssertEqual(widthApplication.buttons["Stroke width"].value as? String, "Bold")
    }

    func testWritingToolsAndPrecisionEraserUseNestedRadialChoices() {
        let toolsApplication = makeApplication()
        toolsApplication.launch()
        toolsApplication.buttons["New notebook"].tap()

        toolsApplication.buttons["Writing tools"].tap()
        for tool in [
            "Ballpoint", "Fineliner", "Mechanical pencil", "Pencil", "Marker",
            "Highlighter", "Brush", "Calligraphy pen", "Handwriting to text"
        ] {
            XCTAssertTrue(toolsApplication.buttons[tool].exists)
        }
        toolsApplication.buttons["Brush"].tap()
        XCTAssertEqual(toolsApplication.buttons["Drawing tools"].value as? String, "Brush")

        let eraserApplication = makeApplication()
        eraserApplication.launch()
        eraserApplication.buttons["New notebook"].tap()
        eraserApplication.otherElements["Quick tools"].buttons["Eraser"].tap()
        XCTAssertTrue(eraserApplication.buttons["Object eraser"].waitForExistence(timeout: 2))
        XCTAssertTrue(eraserApplication.buttons["Pixel eraser"].exists)
        eraserApplication.buttons["Pixel eraser"].tap()
        XCTAssertTrue(eraserApplication.buttons["Fine"].waitForExistence(timeout: 2))
        XCTAssertTrue(eraserApplication.otherElements["Quick tools"].exists)
        eraserApplication.buttons["Fine"].tap()
        XCTAssertEqual(eraserApplication.buttons["Eraser"].value as? String, "Precision")
        XCTAssertEqual(eraserApplication.buttons["Stroke width"].value as? String, "Fine")
    }

    private func makeApplication() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let application = XCUIApplication()
        application.launchArguments = [
            "-ui-testing",
            "-reset-library",
            "-radial-menu-origin",
            "380",
            "500"
        ]
        return application
    }
}
