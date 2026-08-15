import XCTest
@testable import NoteNerds

final class NotionDownloadHostBehaviorTests: XCTestCase {
    func testAllowsNotionHostedHTTPSFilesAndRejectsEverythingElse() {
        XCTAssertTrue(NotionDownloadHost.isAllowed(url("https://secure.notion-static.com/file")))
        XCTAssertTrue(NotionDownloadHost.isAllowed(url("https://www.notion.so/file")))
        XCTAssertTrue(NotionDownloadHost.isAllowed(url("https://file.notion.so/file")))
        XCTAssertTrue(NotionDownloadHost.isAllowed(url("https://notion-static.com/file")))
        XCTAssertTrue(
            NotionDownloadHost.isAllowed(url("https://prod-files-secure.s3.us-west-2.amazonaws.com/file"))
        )

        XCTAssertFalse(NotionDownloadHost.isAllowed(url("http://secure.notion-static.com/file")))
        XCTAssertFalse(NotionDownloadHost.isAllowed(url("https://example.com/file")))
        XCTAssertFalse(NotionDownloadHost.isAllowed(url("https://evil.notion.so.example.com/file")))
        XCTAssertFalse(NotionDownloadHost.isAllowed(url("https://user:pass@secure.notion-static.com/file")))
        XCTAssertFalse(NotionDownloadHost.isAllowed(url("https://127.0.0.1/file")))
        XCTAssertFalse(NotionDownloadHost.isAllowed(url("https://[::1]/file")))
    }

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }
}
