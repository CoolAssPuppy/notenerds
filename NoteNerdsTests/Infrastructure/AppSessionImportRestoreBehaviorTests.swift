import XCTest
@testable import NoteNerds

@MainActor
final class AppSessionImportRestoreBehaviorTests: XCTestCase {
    func testImportDoesNotTreatARandomDirectoryAsANotebookPackage() {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try? Data("not a notebook".utf8).write(to: directoryURL.appending(path: "notes.txt"))
        let model = AppModel(automaticallyRestore: false)

        model.importExternalFile(at: directoryURL)

        XCTAssertTrue(model.library.notebooks.isEmpty)
        XCTAssertNotNil(model.presentedError)
    }

    func testImportDoesNotTreatAPartialPackageDirectoryAsANotebook() {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try? Data("{}".utf8).write(to: directoryURL.appending(path: "Document.json"))
        let model = AppModel(automaticallyRestore: false)

        model.importExternalFile(at: directoryURL)

        XCTAssertTrue(model.library.notebooks.isEmpty)
        XCTAssertNotNil(model.presentedError)
    }

    func testRestoreRecoversMultipleNotebooksFromLocalDocuments() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let first = Notebook(title: "Alpha", canvases: [Canvas(title: "One")])
        let second = Notebook(title: "Beta", canvases: [Canvas(title: "Two")])
        try await repository.save(LibraryState(notebooks: [first, second]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: first))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: second))

        let session = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await session.restoreLibrary()

        XCTAssertEqual(session.notebook(first.id)?.title, "Alpha")
        XCTAssertEqual(session.notebook(second.id)?.title, "Beta")
        XCTAssertEqual(session.notebook(first.id)?.canvases.map(\.title), ["One"])
        XCTAssertEqual(session.notebook(second.id)?.canvases.map(\.title), ["Two"])
    }
}
