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

    func testRootAndColorChoicesRenderAsCompleteConcentricRings() {
        let application = XCUIApplication()
        application.launchArguments = [
            "-ui-testing",
            "-reset-library",
            "-radial-menu-origin",
            "380",
            "500"
        ]
        application.launch()
        application.buttons["New notebook"].tap()

        let quickTools = application.otherElements["Quick tools"]
        let anchor = application.otherElements["Radial menu anchor"]
        let rootLabels = [
            "Writing tools", "Eraser", "Lasso", "Undo", "Redo", "Width", "Color"
        ]
        XCTAssertTrue(anchor.waitForExistence(timeout: 2))
        let rootButtons = rootLabels.map { quickTools.buttons[$0] }
        rootButtons.forEach { XCTAssertTrue($0.waitForExistence(timeout: 2)) }
        assertCompleteRing(elements: rootButtons, around: anchor.frame.center, radius: 96)
        attachScreenshot(from: application, named: "Complete root radial menu")

        quickTools.buttons["Color"].tap()
        let colorLabels = [
            "Black", "Gray", "White", "Brown", "Red", "Orange", "Yellow",
            "Green", "Mint", "Cyan", "Blue", "Indigo", "Purple", "Pink"
        ]
        let colorButtons = colorLabels.map { quickTools.buttons[$0] }
        colorButtons.forEach { XCTAssertTrue($0.waitForExistence(timeout: 2)) }
        let customColor = quickTools.descendants(matching: .any)["Radial custom color"]
        XCTAssertTrue(customColor.waitForExistence(timeout: 2))
        assertConcentricRings(
            elements: colorButtons + [customColor],
            around: anchor.frame.center,
            expectedRadii: [82, 144]
        )
        attachScreenshot(from: application, named: "Concentric color radial menu")
    }

    private func assertCompleteRing(
        elements: [XCUIElement],
        around anchor: CGPoint,
        radius: CGFloat
    ) {
        let angles = elements.map { element -> CGFloat in
            XCTAssertEqual(element.frame.width, element.frame.height, accuracy: 1)
            XCTAssertEqual(distance(from: element.frame.center, to: anchor), radius, accuracy: 3)
            let delta = CGPoint(
                x: element.frame.midX - anchor.x,
                y: element.frame.midY - anchor.y
            )
            let angle = atan2(delta.y, delta.x)
            return angle >= 0 ? angle : angle + 2 * .pi
        }.sorted()
        let expectedStep = 2 * CGFloat.pi / CGFloat(elements.count)
        let wrapped = angles + [angles[0] + 2 * .pi]
        for index in angles.indices {
            XCTAssertEqual(wrapped[index + 1] - wrapped[index], expectedStep, accuracy: 0.03)
        }
    }

    private func assertConcentricRings(
        elements: [XCUIElement],
        around anchor: CGPoint,
        expectedRadii: [CGFloat]
    ) {
        let radii = elements.map { element -> CGFloat in
            XCTAssertEqual(element.frame.width, element.frame.height, accuracy: 1)
            return distance(from: element.frame.center, to: anchor)
        }
        for radius in radii {
            XCTAssertTrue(expectedRadii.contains { abs($0 - radius) <= 3 })
        }
        for expectedRadius in expectedRadii {
            XCTAssertTrue(radii.contains { abs($0 - expectedRadius) <= 3 })
        }
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func attachScreenshot(from application: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
