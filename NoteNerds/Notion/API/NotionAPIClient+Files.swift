import Foundation

extension NotionAPIClient {
    private static var singlePartLimit: Int { 20 * 1_024 * 1_024 }
    private static var multipartPartSize: Int { 10 * 1_024 * 1_024 }
    private static var maximumFileSize: Int64 { 5 * 1_024 * 1_024 * 1_024 }

    func uploadFile(
        data: Data,
        filename: String,
        contentType: String
    ) async throws -> String {
        try Self.validateUpload(data: data, filename: filename, contentType: contentType)
        let partCount = data.count <= Self.singlePartLimit
            ? 1
            : Int(ceil(Double(data.count) / Double(Self.multipartPartSize)))
        let upload = try await createFileUpload(
            filename: filename,
            contentType: contentType,
            partCount: partCount
        )
        for partIndex in 0..<partCount {
            let range = Self.partRange(index: partIndex, count: data.count)
            let response = try await sendFilePart(
                uploadID: upload.id,
                part: FilePart(data: data, range: range, filename: filename, contentType: contentType),
                partNumber: partCount == 1 ? nil : partIndex + 1
            )
            guard response.id == upload.id else { throw NotionAPIError.invalidResponse }
            let validStatus = partCount == 1 ? response.status == "uploaded" : response.status == "pending"
            guard validStatus else { throw NotionAPIError.invalidResponse }
        }
        if partCount > 1 {
            let completed = try await completeFileUpload(id: upload.id)
            guard completed.id == upload.id, completed.status == "uploaded" else {
                throw NotionAPIError.invalidResponse
            }
        }
        return upload.id
    }

    private func createFileUpload(
        filename: String,
        contentType: String,
        partCount: Int
    ) async throws -> FileUploadResponse {
        var values: [String: NotionJSONValue] = [
            "mode": .string(partCount == 1 ? "single_part" : "multi_part"),
            "filename": .string(filename),
            "content_type": .string(contentType)
        ]
        if partCount > 1 { values["number_of_parts"] = .number(Double(partCount)) }
        let request = try makeRequest(path: "file_uploads", method: "POST", body: .object(values))
        return try Self.decodeUploadResponse(try await send(request), expectedStatus: "pending")
    }

    private func sendFilePart(
        uploadID: String,
        part: FilePart,
        partNumber: Int?
    ) async throws -> FileUploadResponse {
        let form = try MultipartFormFile(
            fileData: part.data,
            range: part.range,
            filename: part.filename,
            contentType: part.contentType,
            partNumber: partNumber
        )
        var request = makeRequest(
            path: "file_uploads/\(uploadID)/send",
            method: "POST",
            data: Data(),
            contentType: "multipart/form-data; boundary=\(form.boundary)"
        )
        request.httpBody = nil
        defer { try? FileManager.default.removeItem(at: form.url) }
        return try JSONDecoder().decode(
            FileUploadResponse.self,
            from: try await send(request, uploadFileURL: form.url)
        )
    }

    private func completeFileUpload(id: String) async throws -> FileUploadResponse {
        let request = try makeRequest(
            path: "file_uploads/\(id)/complete",
            method: "POST",
            body: .object([:])
        )
        return try JSONDecoder().decode(FileUploadResponse.self, from: try await send(request))
    }

    private static func decodeUploadResponse(
        _ data: Data,
        expectedStatus: String
    ) throws -> FileUploadResponse {
        let response = try JSONDecoder().decode(FileUploadResponse.self, from: data)
        guard UUID(uuidString: response.id) != nil, response.status == expectedStatus else {
            throw NotionAPIError.invalidResponse
        }
        return response
    }

    private static func partRange(index: Int, count: Int) -> Range<Int> {
        let start = index * multipartPartSize
        return start..<min(start + multipartPartSize, count)
    }

    private static func validateUpload(
        data: Data,
        filename: String,
        contentType: String
    ) throws {
        let isSafeName = !filename.isEmpty
            && filename.utf8.count <= 255
            && filename == URL(fileURLWithPath: filename).lastPathComponent
            && !filename.contains("\\")
            && !filename.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        guard isSafeName else { throw NotionAPIError.invalidFilename }
        let pieces = contentType.split(separator: "/", omittingEmptySubsequences: false)
        let allowedCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$&^_.+-"
        let allowed = CharacterSet(charactersIn: allowedCharacters)
        let isSafeType = pieces.count == 2
            && contentType.utf8.count <= 127
            && pieces.allSatisfy { part in
                !part.isEmpty && part.unicodeScalars.allSatisfy(allowed.contains)
        }
        guard isSafeType else { throw NotionAPIError.invalidContentType }
        let supportedExtension = switch contentType.lowercased() {
        case "application/json": "json"
        case "application/pdf": "pdf"
        case "image/png": "png"
        default: ""
        }
        guard !supportedExtension.isEmpty,
              URL(fileURLWithPath: filename).pathExtension.lowercased() == supportedExtension else {
            throw NotionAPIError.invalidContentType
        }
        guard !data.isEmpty else { throw NotionAPIError.emptyFile }
        guard Int64(data.count) <= maximumFileSize else { throw NotionAPIError.payloadTooLarge }
    }
}

private struct FilePart {
    let data: Data
    let range: Range<Int>
    let filename: String
    let contentType: String
}

private struct FileUploadResponse: Decodable {
    let id: String
    let status: String
}

private struct MultipartFormFile {
    let boundary: String
    let url: URL

    init(
        fileData: Data,
        range: Range<Int>,
        filename: String,
        contentType: String,
        partNumber: Int?
    ) throws {
        let boundary = "NoteNerds-\(UUID().uuidString)"
        self.boundary = boundary
        let url = FileManager.default.temporaryDirectory
            .appending(path: "notenerds-upload-\(UUID().uuidString)")
        self.url = url
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw NotionAPIError.invalidResponse
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var header = Data()
        if let partNumber {
            header.appendUTF8("--\(boundary)\r\n")
            header.appendUTF8("Content-Disposition: form-data; name=\"part_number\"\r\n\r\n")
            header.appendUTF8("\(partNumber)\r\n")
        }
        header.appendUTF8("--\(boundary)\r\n")
        header.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        header.appendUTF8("Content-Type: \(contentType)\r\n\r\n")
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: fileData[range])
        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        try handle.synchronize()
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }
}
