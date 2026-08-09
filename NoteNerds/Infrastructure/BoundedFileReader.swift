import Foundation

enum BoundedFileReaderError: Error, Equatable {
    case fileTooLarge
    case unsupportedFile
}

struct BoundedFileReader: Sendable {
    private let maximumByteCount: Int
    private let readData: @Sendable (URL) throws -> Data

    init(
        maximumByteCount: Int = 512 * 1_024 * 1_024,
        readData: @escaping @Sendable (URL) throws -> Data = {
            try Data(contentsOf: $0, options: .mappedIfSafe)
        }
    ) {
        self.maximumByteCount = maximumByteCount
        self.readData = readData
    }

    func read(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw BoundedFileReaderError.unsupportedFile
        }
        guard let byteCount = values.fileSize, byteCount <= maximumByteCount else {
            throw BoundedFileReaderError.fileTooLarge
        }
        let data = try readData(url)
        guard data.count <= maximumByteCount else {
            throw BoundedFileReaderError.fileTooLarge
        }
        return data
    }

    func readIfPresent(from url: URL) throws -> Data? {
        do {
            return try read(from: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
