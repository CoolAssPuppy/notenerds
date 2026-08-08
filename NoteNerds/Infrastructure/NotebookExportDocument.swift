import SwiftUI
import UniformTypeIdentifiers

struct NotebookExportDocument: @unchecked Sendable, FileDocument {
    static let nativeType = UTType(exportedAs: "com.prashant.notenerds.notebook")
    static let readableContentTypes: [UTType] = [.pdf, .png, nativeType]

    let wrapper: FileWrapper

    init(data: Data) {
        wrapper = FileWrapper(regularFileWithContents: data)
    }

    init(wrapper: FileWrapper) {
        self.wrapper = wrapper
    }

    init(configuration: ReadConfiguration) throws {
        wrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper
    }
}
