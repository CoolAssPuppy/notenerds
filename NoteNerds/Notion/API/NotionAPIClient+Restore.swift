import Foundation

struct NotionRemoteNotebookFile: Equatable, Sendable {
    let pageID: String
    let notebookID: String
    let contentHash: String
    let url: URL
}

protocol NotionRestoreAPI: Sendable {
    func listNativeNotebookFiles(dataSourceID: String) async throws -> [NotionRemoteNotebookFile]
    func fetchNativeNotebookFile(pageID: String) async throws -> NotionRemoteNotebookFile
    func findLibraryManifestRootBlock(pageID: String) async throws -> String?
    func findManagedFile(rootBlockID: String) async throws -> URL
    func downloadFile(from url: URL, maximumByteCount: Int) async throws -> Data
}

extension NotionAPIClient: NotionRestoreAPI {}

extension NotionAPIClient {
    func fetchNativeNotebookFile(pageID: String) async throws -> NotionRemoteNotebookFile {
        guard UUID(uuidString: pageID) != nil else {
            throw NotionAPIError.invalidIdentifier
        }
        let request = baseRequest(path: "pages/\(pageID)", method: "GET")
        let response = try JSONDecoder().decode(
            RestoreNotebookPage.self,
            from: try await send(request)
        )
        let file = try response.remoteFile
        guard file.pageID == pageID else { throw NotionAPIError.invalidResponse }
        return file
    }

    func listNativeNotebookFiles(dataSourceID: String) async throws -> [NotionRemoteNotebookFile] {
        guard UUID(uuidString: dataSourceID) != nil else {
            throw NotionAPIError.invalidIdentifier
        }
        var files: [NotionRemoteNotebookFile] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        repeat {
            var body: [String: NotionJSONValue] = ["page_size": .number(100)]
            if let cursor { body["start_cursor"] = .string(cursor) }
            let request = try makeRequest(
                path: "data_sources/\(dataSourceID)/query",
                method: "POST",
                body: .object(body)
            )
            let response = try JSONDecoder().decode(
                RestoreNotebookQueryResponse.self,
                from: try await send(request)
            )
            files.append(contentsOf: try response.results.map { try $0.remoteFile })
            cursor = try nextCursor(
                hasMore: response.hasMore,
                next: response.nextCursor,
                seen: &seenCursors
            )
        } while cursor != nil

        guard Set(files.map(\.notebookID)).count == files.count else {
            throw NotionAPIError.duplicateNotebookRows
        }
        return files
    }

    func findManagedFile(rootBlockID: String) async throws -> URL {
        guard UUID(uuidString: rootBlockID) != nil else {
            throw NotionAPIError.invalidIdentifier
        }
        var urls: [URL] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        repeat {
            var query = [URLQueryItem(name: "page_size", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "start_cursor", value: cursor)) }
            let request = try makeRequest(
                path: "blocks/\(rootBlockID)/children",
                method: "GET",
                queryItems: query
            )
            let response = try JSONDecoder().decode(
                RestoreBlockChildrenResponse.self,
                from: try await send(request)
            )
            urls.append(contentsOf: response.results.compactMap(\.downloadURL))
            cursor = try nextCursor(
                hasMore: response.hasMore,
                next: response.nextCursor,
                seen: &seenCursors
            )
        } while cursor != nil
        guard urls.count == 1, let url = urls.first else {
            throw NotionAPIError.invalidResponse
        }
        return url
    }

    func downloadFile(from url: URL, maximumByteCount: Int) async throws -> Data {
        guard NotionDownloadHost.isAllowed(url), maximumByteCount > 0 else {
            throw NotionAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.download(
            for: request,
            maximumByteCount: maximumByteCount
        )
        guard (200..<300).contains(response.statusCode) else {
            throw NotionAPIError.httpStatus(response.statusCode)
        }
        if let contentLength = response.value(forHTTPHeaderField: "Content-Length"),
           let byteCount = Int(contentLength),
           byteCount > maximumByteCount {
            throw NotionAPIError.payloadTooLarge
        }
        guard data.count <= maximumByteCount else { throw NotionAPIError.payloadTooLarge }
        return data
    }

    private func nextCursor(
        hasMore: Bool,
        next: String?,
        seen: inout Set<String>
    ) throws -> String? {
        guard hasMore else { return nil }
        guard let next, !next.isEmpty else { throw NotionAPIError.invalidResponse }
        guard seen.insert(next).inserted else { throw NotionAPIError.repeatedCursor }
        guard seen.count <= 1_000 else { throw NotionAPIError.paginationLimit }
        return next
    }
}

private struct RestoreNotebookQueryResponse: Decodable {
    let results: [RestoreNotebookPage]
    let hasMore: Bool
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

private struct RestoreNotebookPage: Decodable {
    let id: String
    let properties: [String: RestorePageProperty]

    var remoteFile: NotionRemoteNotebookFile {
        get throws {
            guard UUID(uuidString: id) != nil,
                  let notebookProperty = properties["Notebook ID"],
                  let notebookID = notebookProperty.richText?.map(\.plainText).joined(),
                  let normalizedID = UUID(uuidString: notebookID)?.uuidString.lowercased(),
                  let contentHash = properties["Content Hash"]?.richText?.map(\.plainText).joined(),
                  contentHash.count == 64,
                  contentHash.allSatisfy({ $0.isHexDigit }),
                  let file = properties["Native Notebook"]?.files?.first,
                  let url = file.hostedURL,
                  NotionDownloadHost.isAllowed(url) else {
                throw NotionAPIError.invalidResponse
            }
            return NotionRemoteNotebookFile(
                pageID: id,
                notebookID: normalizedID,
                contentHash: contentHash.lowercased(),
                url: url
            )
        }
    }
}

private struct RestorePageProperty: Decodable {
    let richText: [RestoreRichText]?
    let files: [RestoreFile]?

    private enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
        case files
    }
}

private struct RestoreRichText: Decodable {
    let plainText: String

    private enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
    }
}

private struct RestoreFile: Decodable {
    let file: RestoreURLValue?
    let external: RestoreURLValue?

    var hostedURL: URL? { file?.url }
}

private struct RestoreURLValue: Decodable {
    let url: URL
}

private struct RestoreBlockChildrenResponse: Decodable {
    let results: [RestoreBlock]
    let hasMore: Bool
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

private struct RestoreBlock: Decodable {
    let type: String
    let file: RestoreFile?

    var downloadURL: URL? {
        guard type == "file" else { return nil }
        return file?.hostedURL
    }
}
