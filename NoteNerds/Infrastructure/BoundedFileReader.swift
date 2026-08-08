import Foundation

enum BoundedFileReaderError: Error, Equatable {
    case fileTooLarge
    case unsupportedFile
}

struct BoundedFileReader: Sendable {
    private let maximumByteCount: Int

    init(maximumByteCount: Int = 512 * 1_024 * 1_024) {
        self.maximumByteCount = maximumByteCount
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
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}
