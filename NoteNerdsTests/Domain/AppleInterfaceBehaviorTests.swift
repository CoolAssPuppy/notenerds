import XCTest
@testable import NoteNerds

final class AppleInterfaceBehaviorTests: XCTestCase {
    func testLibrarySymbolsUseStandardAppleMeanings() {
        XCTAssertEqual(LibrarySection.files.rawValue, "My Notebooks")
        XCTAssertEqual(AppSymbol.allNotes, "note.text")
        XCTAssertEqual(AppSymbol.favorites, "star")
        XCTAssertEqual(AppSymbol.recents, "clock")
        XCTAssertEqual(AppSymbol.trash, "trash")
        XCTAssertEqual(AppSymbol.folder, "folder.fill")
        XCTAssertEqual(AppSymbol.notebook, "book.closed.fill")
    }

    func testCommonActionsUseTheSameSymbolsThroughoutTheApp() {
        XCTAssertEqual(AppSymbol.newNotebook, "square.and.pencil")
        XCTAssertEqual(AppSymbol.newFolder, "folder.badge.plus")
        XCTAssertEqual(AppSymbol.search, "magnifyingglass")
        XCTAssertEqual(AppSymbol.share, "square.and.arrow.up")
        XCTAssertEqual(AppSymbol.more, "ellipsis.circle")
        XCTAssertEqual(AppSymbol.back, "chevron.backward")
        XCTAssertEqual(AppSymbol.add, "plus")
    }

    func testLegalPadCanvasUsesOneFixedLeftMarginRule() {
        let contentSize = CGSize(width: 20_000, height: 20_000)

        let yellowRule = PencilCanvasRenderer.marginRuleFrame(for: .yellowLegalPad, contentSize: contentSize)
        let whiteRule = PencilCanvasRenderer.marginRuleFrame(for: .whiteLegalPad, contentSize: contentSize)

        XCTAssertEqual(yellowRule, CGRect(x: 9_551.5, y: 0, width: 1, height: 20_000))
        XCTAssertEqual(whiteRule, yellowRule)
        XCTAssertNil(PencilCanvasRenderer.marginRuleFrame(for: .gridSmall, contentSize: contentSize))
    }
}
