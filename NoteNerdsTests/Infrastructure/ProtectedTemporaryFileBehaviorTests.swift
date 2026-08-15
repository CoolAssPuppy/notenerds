import XCTest
@testable import NoteNerds

final class ProtectedTemporaryFileBehaviorTests: XCTestCase {
    func testWritesAUUIDNamedFileWithCompleteProtection() throws {
        let url = try ProtectedTemporaryFile.write(Data("secret".utf8), pathExtension: "pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let values = try url.resourceValues(forKeys: [.fileProtectionKey])

        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertNotEqual(url.deletingPathExtension().lastPathComponent, "export")
        XCTAssertNotNil(UUID(uuidString: url.deletingPathExtension().lastPathComponent))
        XCTAssertEqual(try Data(contentsOf: url), Data("secret".utf8))
        XCTAssertNotEqual(values.fileProtection, URLFileProtection.none)
        XCTAssertNotEqual(values.fileProtection, .completeUnlessOpen)
    }
}
