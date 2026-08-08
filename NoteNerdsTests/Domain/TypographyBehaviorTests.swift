import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class TypographyBehaviorTests: XCTestCase {
    func testFontCatalogContainsEveryFontAvailableToTheApp() {
        let installedNames = Set(UIFont.familyNames.flatMap(UIFont.fontNames(forFamilyName:)))

        let catalogNames = Set(SystemFontCatalog.availableFonts.map(\.postScriptName))

        XCTAssertEqual(catalogNames, installedNames)
        XCTAssertEqual(SystemFontCatalog.availableFonts, SystemFontCatalog.availableFonts.sorted())
    }

    func testEscapeCancelsInlineTextEditing() throws {
        let cancellation = expectation(description: "Escape cancels inline text editing")
        let editor = InlineCanvasTextEditor(
            session: .new(layerID: LayerID(), insertionPoint: CanvasPoint(x: 100, y: 100)),
            onCommit: { _ in XCTFail("Escape must not commit text") },
            onCancel: { cancellation.fulfill() }
        )
        let textView = try XCTUnwrap(editor.descendantTextView)
        let escapeCommand = try XCTUnwrap(
            textView.keyCommands?.first { $0.input == UIKeyCommand.inputEscape }
        )

        _ = textView.perform(escapeCommand.action, with: escapeCommand)

        wait(for: [cancellation], timeout: 1)
    }
}

private extension UIView {
    var descendantTextView: UITextView? {
        if let textView = self as? UITextView { return textView }
        return subviews.lazy.compactMap(\.descendantTextView).first
    }
}
