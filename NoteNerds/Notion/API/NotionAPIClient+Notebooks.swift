import Foundation

extension NotionAPIClient {
    func findNotebookPage(
        dataSourceID: String,
        notebookID: String
    ) async throws -> NotionPageBinding? {
        guard UUID(uuidString: dataSourceID) != nil,
              UUID(uuidString: notebookID) != nil else {
            throw NotionAPIError.invalidIdentifier
        }
        let body: NotionJSONValue = .object([
            "page_size": .number(2),
            "filter": .object([
                "property": .string("Notebook ID"),
                "rich_text": .object(["equals": .string(notebookID)])
            ])
        ])
        let request = try makeRequest(
            path: "data_sources/\(dataSourceID)/query",
            method: "POST",
            body: body
        )
        let data = try await send(request)
        let response = try JSONDecoder().decode(NotebookQueryResponse.self, from: data)
        guard !response.hasMore, response.results.count <= 1 else {
            throw NotionAPIError.duplicateNotebookRows
        }
        return response.results.first.map { NotionPageBinding(pageID: $0.id, url: $0.url) }
    }

    func createNotebookPage(
        dataSourceID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) async throws -> NotionPageBinding {
        guard UUID(uuidString: dataSourceID) != nil,
              Self.areValid(files: files) else {
            throw NotionAPIError.invalidIdentifier
        }
        let properties = try NotionPageProperties.make(snapshot: snapshot, files: files)
        let body: NotionJSONValue = .object([
            "parent": .object([
                "type": .string("data_source_id"),
                "data_source_id": .string(dataSourceID)
            ]),
            "properties": .object(properties)
        ])
        let request = try makeRequest(path: "pages", method: "POST", body: body)
        let data = try await send(request)
        let response = try JSONDecoder().decode(NotebookPageResponse.self, from: data)
        guard UUID(uuidString: response.id) != nil else { throw NotionAPIError.invalidResponse }
        return NotionPageBinding(pageID: response.id, url: response.url)
    }

    func updateNotebookPage(
        pageID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) async throws -> NotionPageBinding {
        guard UUID(uuidString: pageID) != nil,
              Self.areValid(files: files) else {
            throw NotionAPIError.invalidIdentifier
        }
        let properties = try NotionPageProperties.make(snapshot: snapshot, files: files)
        let request = try makeRequest(
            path: "pages/\(pageID)",
            method: "PATCH",
            body: .object(["properties": .object(properties)])
        )
        let response = try JSONDecoder().decode(
            NotebookPageResponse.self,
            from: try await send(request)
        )
        guard response.id == pageID else { throw NotionAPIError.invalidResponse }
        return NotionPageBinding(pageID: response.id, url: response.url)
    }

    func trashNotebookPage(pageID: String) async throws {
        guard UUID(uuidString: pageID) != nil else {
            throw NotionAPIError.invalidIdentifier
        }
        let request = try makeRequest(
            path: "pages/\(pageID)",
            method: "PATCH",
            body: .object(["in_trash": .bool(true)])
        )
        let response = try JSONDecoder().decode(
            TrashedNotebookPageResponse.self,
            from: try await send(request)
        )
        guard response.id == pageID, response.inTrash else {
            throw NotionAPIError.invalidResponse
        }
    }

    private static func areValid(files: NotionNotebookRemoteFiles) -> Bool {
        [files.nativeUploadID, files.pdfUploadID]
            .compactMap { $0 }
            .allSatisfy { UUID(uuidString: $0) != nil }
    }
}

private struct NotebookQueryResponse: Decodable {
    let results: [NotebookPageResponse]
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
    }
}

private struct NotebookPageResponse: Decodable {
    let id: String
    let url: URL?
}

private struct TrashedNotebookPageResponse: Decodable {
    let id: String
    let inTrash: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case inTrash = "in_trash"
    }
}
