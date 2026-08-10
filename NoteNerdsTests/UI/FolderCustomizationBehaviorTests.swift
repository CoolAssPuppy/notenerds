import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class FolderCustomizationBehaviorTests: XCTestCase {
    func testEveryCuratedFolderSymbolExists() {
        for symbol in FolderSystemSymbol.allCases {
            XCTAssertNotNil(UIImage(systemName: symbol.rawValue), symbol.rawValue)
        }
    }

    func testFolderNameAndSystemIconChangeTogether() throws {
        let model = makeModel()
        let purple = FolderIconColor(red: 0.45, green: 0.2, blue: 0.8, alpha: 1)
        let folder = try model.library.createFolder(
            named: "New folder",
            in: nil,
            at: DomainFixtures.fixedDate
        )

        model.editFolder(
            folder.id,
            name: "Work",
            icon: .systemSymbol(.briefcase),
            iconColor: purple
        )

        let edited = try XCTUnwrap(model.library.folder(id: folder.id))
        XCTAssertEqual(edited.name, "Work")
        XCTAssertEqual(edited.icon, .systemSymbol(.briefcase))
        XCTAssertEqual(edited.iconColor, purple)
        XCTAssertGreaterThan(edited.modifiedAt, DomainFixtures.fixedDate)
    }

    func testBlankFolderNameLeavesTheExistingNameAndIconUnchanged() throws {
        let folder = Folder(
            name: "Work",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate,
            icon: .systemSymbol(.briefcase),
            iconColor: FolderIconColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1)
        )
        var library = LibraryState(folders: [folder])

        XCTAssertThrowsError(
            try library.editFolder(
                folder.id,
                name: "   ",
                icon: .emoji(try FolderEmoji("📁")),
                iconColor: nil,
                at: DomainFixtures.fixedDate.addingTimeInterval(30)
            )
        )

        XCTAssertEqual(library.folder(id: folder.id), folder)
    }

    func testEmojiRequiresExactlyOneEmojiCharacter() throws {
        for validEmoji in ["📁", "👨‍👩‍👧‍👦", "🇵🇹", "👍🏽", "1️⃣"] {
            XCTAssertEqual(try FolderEmoji(validEmoji).value, validEmoji)
        }
        for invalidEmoji in ["", " ", "A", "A\u{FE0F}", "1", "📁 Work", "📁📌"] {
            XCTAssertThrowsError(try FolderEmoji(invalidEmoji))
        }
    }

    func testEmojiRejectsOneCharacterWithExcessiveCombiningMarks() {
        let oversizedEmoji = "\u{1F4C1}" + String(repeating: "\u{0301}", count: 100)

        XCTAssertThrowsError(try FolderEmoji(oversizedEmoji))
    }

    func testLegacyFolderWithoutAnIconUsesTheStandardFolderSymbol() throws {
        let folder = Folder(
            name: "Legacy",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(folder)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "icon")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let restored = try decoder.decode(Folder.self, from: legacyData)

        XCTAssertEqual(restored.icon, .systemSymbol(.folder))
        XCTAssertNil(restored.iconColor)
    }

    func testPresentInvalidFolderAppearanceIsRejected() throws {
        let folder = Folder(
            name: "Invalid",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(folder)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var invalidIcon = original
        invalidIcon["icon"] = ["unknown": [:]]
        var invalidColor = original
        invalidColor["iconColor"] = ["red": "bad", "green": 0, "blue": 0, "alpha": 1]
        var outOfRangeColor = original
        outOfRangeColor["iconColor"] = ["red": 2, "green": 0, "blue": 0, "alpha": 1]
        var nullIcon = original
        nullIcon["icon"] = NSNull()

        XCTAssertThrowsError(try decoder.decode(
            Folder.self,
            from: JSONSerialization.data(withJSONObject: invalidIcon)
        ))
        XCTAssertThrowsError(try decoder.decode(
            Folder.self,
            from: JSONSerialization.data(withJSONObject: invalidColor)
        ))
        XCTAssertThrowsError(try decoder.decode(
            Folder.self,
            from: JSONSerialization.data(withJSONObject: outOfRangeColor)
        ))
        XCTAssertThrowsError(try decoder.decode(
            Folder.self,
            from: JSONSerialization.data(withJSONObject: nullIcon)
        ))
    }

    func testStoredFolderImageMustBeADecodableSmallPNG() throws {
        let invalidPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])

        XCTAssertThrowsError(try FolderIconPNG(data: invalidPNG)) { error in
            XCTAssertEqual(error as? FolderIconError, .invalidPNG)
        }
    }

    func testPNGAndSVGImportsBecomeSmallPNGFolderIcons() async throws {
        let importer = FolderIconImporter()
        let pngURL = try writePNG(width: 320, height: 160)
        let svgURL = try writeSVG(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="32" height="16" viewBox="0 0 32 16">
              <rect width="32" height="16" rx="4" fill="#5B4BFF"/>
            </svg>
            """
        )

        let icons = try await [
            importer.importIcon(at: pngURL),
            importer.importIcon(at: svgURL)
        ]

        for icon in icons {
            guard case let .customPNG(customPNG) = icon else {
                return XCTFail("Expected a normalized PNG icon")
            }
            XCTAssertLessThanOrEqual(customPNG.data.count, FolderIconPNG.maximumByteCount)
            let image = try XCTUnwrap(UIImage(data: customPNG.data))
            XCTAssertEqual(image.size, CGSize(width: 96, height: 96))
        }
    }

    func testFolderIconImportRejectsUnsafeSVG() async throws {
        let unsafeURLs = try [
            writeSVG(
                """
                <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
                  <script>alert('no')</script>
                </svg>
                """
            ),
            writeSVG(
                """
                <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
                  <video src="file:///does-not-exist"></video>
                </svg>
                """
            ),
            writeSVG(
                """
                <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
                  <meta http-equiv="refresh" content="0;url=https://example.invalid">
                </svg>
                """
            )
        ]
        let htmlEscapeURL = try writeSVG(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"></svg>
            </body><img src="https://example.invalid/pixel">
            """
        )
        for unsafeURL in unsafeURLs {
            await XCTAssertThrowsErrorAsync(try await FolderIconImporter().importIcon(at: unsafeURL)) { error in
                XCTAssertEqual(error as? FolderIconImportError, .unsafeSVG)
            }
        }
        await XCTAssertThrowsErrorAsync(try await FolderIconImporter().importIcon(at: htmlEscapeURL)) { error in
            XCTAssertEqual(error as? FolderIconImportError, .invalidImage)
        }
    }

    func testFolderIconImportRejectsOversizedInput() async throws {
        let oversizedURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).png")
        let oversizedSVGURL = try writeSVG(
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><desc>"
                + String(repeating: "a", count: 300_000)
                + "</desc></svg>"
        )
        try Data(repeating: 0x00, count: 33).write(to: oversizedURL)

        await XCTAssertThrowsErrorAsync(
            try await FolderIconImporter(maximumInputByteCount: 32).importIcon(at: oversizedURL)
        ) { error in
            XCTAssertEqual(error as? FolderIconImportError, .fileTooLarge)
        }
        await XCTAssertThrowsErrorAsync(try await FolderIconImporter().importIcon(at: oversizedSVGURL)) { error in
            XCTAssertEqual(error as? FolderIconImportError, .fileTooLarge)
        }
    }

    func testFolderSymbolsColorsAndCustomImagesPersistAfterRestart() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "library.json")
        let repository = LocalLibraryRepository(fileURL: fileURL)
        let model = AppModel(repository: repository, automaticallyRestore: false)
        let work = try model.library.createFolder(
            named: "Work",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let art = try model.library.createFolder(
            named: "Art",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let purple = FolderIconColor(red: 0.55, green: 0.3, blue: 0.9, alpha: 1)
        let importedIcon = try await FolderIconImporter().importIcon(at: writePNG(width: 160, height: 160))

        model.editFolder(work.id, name: work.name, icon: .systemSymbol(.briefcase), iconColor: purple)
        model.editFolder(art.id, name: art.name, icon: importedIcon, iconColor: nil)
        await model.libraryPersistenceTask?.value
        let restored = try await repository.load()

        XCTAssertEqual(restored.folder(id: work.id)?.icon, .systemSymbol(.briefcase))
        XCTAssertEqual(restored.folder(id: work.id)?.iconColor, purple)
        XCTAssertEqual(restored.folder(id: art.id)?.icon, importedIcon)
    }

    private func makeModel() -> AppModel {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "library.json")
        return AppModel(
            repository: LocalLibraryRepository(fileURL: fileURL),
            automaticallyRestore: false
        )
    }

    private func writePNG(width: Int, height: Int) throws -> URL {
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    private func writeSVG(_ source: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).svg")
        try Data(source.utf8).write(to: url)
        return url
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (any Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
