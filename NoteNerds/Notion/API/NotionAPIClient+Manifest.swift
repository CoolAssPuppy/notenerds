import Foundation

extension NotionAPIClient {
    func createLibraryManifestPage(parentPageID: String) async throws -> NotionPageBinding {
        guard UUID(uuidString: parentPageID) != nil else {
            throw NotionAPIError.invalidIdentifier
        }
        let title: NotionJSONValue = .object([
            "type": .string("text"),
            "text": .object(["content": .string("Note Nerds Library Manifest")])
        ])
        let request = try makeRequest(
            path: "pages",
            method: "POST",
            body: .object([
                "parent": .object([
                    "type": .string("page_id"),
                    "page_id": .string(parentPageID)
                ]),
                "properties": .object([
                    "title": .object([
                        "title": .array([title])
                    ])
                ])
            ])
        )
        let response = try JSONDecoder().decode(
            ManifestPageResponse.self,
            from: try await send(request)
        )
        guard UUID(uuidString: response.id) != nil else { throw NotionAPIError.invalidResponse }
        return NotionPageBinding(pageID: response.id, url: response.url)
    }
}

private struct ManifestPageResponse: Decodable {
    let id: String
    let url: URL?
}
