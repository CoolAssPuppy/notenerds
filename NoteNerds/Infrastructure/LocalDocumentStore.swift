import Foundation

enum LocalDocumentStoreError: Error, Equatable {
    case notebookNotFound
}

actor LocalDocumentStore {
    private let rootURL: URL
    private let serializer = NativeDocumentSerializer()
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func save(_ package: NativeNotebookPackage) throws {
        try createDirectories()
        let encoded = try serializer.encode(package)
        try encoded.write(to: snapshotURL(for: package.notebook.id), options: [.atomic, .completeFileProtection])
        let journalURL = journalURL(for: package.notebook.id)
        if fileManager.fileExists(atPath: journalURL.path()) {
            try fileManager.removeItem(at: journalURL)
        }
    }

    func load(notebookID: NotebookID) throws -> NativeNotebookPackage {
        let url = snapshotURL(for: notebookID)
        guard fileManager.fileExists(atPath: url.path()) else { throw LocalDocumentStoreError.notebookNotFound }
        return try serializer.decode(Data(contentsOf: url))
    }

    func append(_ operation: DocumentOperation, notebookID: NotebookID) throws {
        try createDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        var encoded = try encoder.encode(operation)
        encoded.append(0x0A)
        let url = journalURL(for: notebookID)
        if fileManager.fileExists(atPath: url.path()) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: encoded)
            try handle.synchronize()
            try handle.close()
        } else {
            try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    func recover(notebookID: NotebookID) throws -> NativeNotebookPackage {
        var package = try load(notebookID: notebookID)
        let url = journalURL(for: notebookID)
        guard fileManager.fileExists(atPath: url.path()) else { return package }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let lines = data.split(separator: 0x0A)
        for (index, line) in lines.enumerated() {
            do {
                let operation = try decoder.decode(DocumentOperation.self, from: Data(line))
                try operation.apply(to: &package.notebook)
            } catch where index == lines.count - 1 && data.last != 0x0A {
                break
            }
        }
        return package
    }

    private func createDirectories() throws {
        try fileManager.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: journalsURL, withIntermediateDirectories: true)
    }

    private var snapshotsURL: URL { rootURL.appending(path: "Snapshots", directoryHint: .isDirectory) }
    private var journalsURL: URL { rootURL.appending(path: "Journals", directoryHint: .isDirectory) }

    private func snapshotURL(for notebookID: NotebookID) -> URL {
        snapshotsURL.appending(path: "\(notebookID.rawValue.uuidString).notenerds.json")
    }

    private func journalURL(for notebookID: NotebookID) -> URL {
        journalsURL.appending(path: "\(notebookID.rawValue.uuidString).journal")
    }
}
