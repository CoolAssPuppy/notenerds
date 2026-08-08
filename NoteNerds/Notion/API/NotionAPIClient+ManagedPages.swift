import Foundation

extension NotionAPIClient {
    func findLibraryManifestRootBlock(pageID: String) async throws -> String? {
        try Self.validateID(pageID)
        let roots = try await listBlockChildren(blockID: pageID)
        let candidates = roots.filter {
            $0.type == "toggle"
                && $0.hasChildren
                && $0.text == NotionLibraryManifestPageBuilder.title
        }
        var matches: [String] = []
        for candidate in candidates {
            let children = try await listBlockChildren(blockID: candidate.id)
            if children.contains(where: {
                $0.type == "code" && $0.text == NotionLibraryManifestPageBuilder.marker
            }) {
                matches.append(candidate.id)
            }
        }
        guard matches.count <= 1 else { throw NotionAPIError.duplicateManagedSections }
        return matches.first
    }

    func findManagedRootBlock(pageID: String, notebookID: String) async throws -> String? {
        try Self.validateID(pageID)
        try Self.validateID(notebookID)
        let roots = try await listBlockChildren(blockID: pageID)
        let candidates = roots.filter {
            $0.type == "toggle"
                && $0.hasChildren
                && $0.text == NotionManagedPageBuilder.title
        }
        var matches: [String] = []
        for candidate in candidates {
            let children = try await listBlockChildren(blockID: candidate.id)
            let hasMarker = children.contains {
                $0.type == "code" && $0.text == NotionManagedPageBuilder.marker
            }
            let hasNotebookID = children.contains {
                $0.type == "paragraph" && $0.text == "Notebook ID: \(notebookID)"
            }
            if hasMarker && hasNotebookID { matches.append(candidate.id) }
        }
        guard matches.count <= 1 else { throw NotionAPIError.duplicateManagedSections }
        return matches.first
    }

    func replaceManagedPage(
        pageID: String,
        oldRootID: String?,
        plan: NotionManagedPagePlan
    ) async throws -> String {
        try Self.validateID(pageID)
        if let oldRootID { try Self.validateID(oldRootID) }
        let newRootID = try await appendRoot(plan.root, to: pageID)
        do {
            for batch in plan.children.chunked(maximumCount: 100) {
                try await appendChildren(batch, to: newRootID)
            }
        } catch {
            try? await deleteBlock(id: newRootID)
            throw error
        }
        if let oldRootID { try await deleteBlock(id: oldRootID) }
        return newRootID
    }

    private func listBlockChildren(blockID: String) async throws -> [BlockSummary] {
        var blocks: [BlockSummary] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        repeat {
            var query = [URLQueryItem(name: "page_size", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "start_cursor", value: cursor)) }
            let request = try makeRequest(
                path: "blocks/\(blockID)/children",
                method: "GET",
                queryItems: query
            )
            let response = try JSONDecoder().decode(BlockListResponse.self, from: try await send(request))
            blocks.append(contentsOf: response.results.map(\.summary))
            guard response.hasMore else { cursor = nil; continue }
            guard let next = response.nextCursor, !next.isEmpty else {
                throw NotionAPIError.invalidResponse
            }
            guard seenCursors.insert(next).inserted else { throw NotionAPIError.repeatedCursor }
            cursor = next
        } while cursor != nil
        return blocks
    }

    private func appendRoot(_ root: NotionJSONValue, to pageID: String) async throws -> String {
        let response = try await append(children: [root], to: pageID)
        guard response.results.count == 1,
              let id = response.results.first?.id,
              UUID(uuidString: id) != nil else {
            throw NotionAPIError.invalidResponse
        }
        return id
    }

    private func appendChildren(_ children: [NotionJSONValue], to blockID: String) async throws {
        let response = try await append(children: children, to: blockID)
        guard !response.results.isEmpty else { throw NotionAPIError.invalidResponse }
    }

    private func append(
        children: [NotionJSONValue],
        to blockID: String
    ) async throws -> AppendBlockResponse {
        let request = try makeRequest(
            path: "blocks/\(blockID)/children",
            method: "PATCH",
            body: .object(["children": .array(children)])
        )
        return try JSONDecoder().decode(AppendBlockResponse.self, from: try await send(request))
    }

    private func deleteBlock(id: String) async throws {
        let request = baseRequest(path: "blocks/\(id)", method: "DELETE")
        let response = try JSONDecoder().decode(DeleteBlockResponse.self, from: try await send(request))
        guard response.id == id, response.isInTrash else { throw NotionAPIError.invalidResponse }
    }

    private static func validateID(_ id: String) throws {
        guard UUID(uuidString: id) != nil else { throw NotionAPIError.invalidIdentifier }
    }
}

private struct BlockListResponse: Decodable {
    let results: [BlockResponse]
    let hasMore: Bool
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

private struct BlockResponse: Decodable {
    let id: String
    let type: String
    let hasChildren: Bool
    let toggle: BlockText?
    let code: BlockText?
    let paragraph: BlockText?

    var summary: BlockSummary {
        BlockSummary(
            id: id,
            type: type,
            hasChildren: hasChildren,
            text: (toggle ?? code ?? paragraph)?.richText.map(\.plainText).joined() ?? ""
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, toggle, code, paragraph
        case hasChildren = "has_children"
    }
}

private struct BlockText: Decodable {
    let richText: [BlockRichText]

    private enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

private struct BlockRichText: Decodable {
    let plainText: String

    private enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
    }
}

private struct BlockSummary {
    let id: String
    let type: String
    let hasChildren: Bool
    let text: String
}

private struct AppendBlockResponse: Decodable {
    let results: [Result]

    struct Result: Decodable {
        let id: String
    }
}

private struct DeleteBlockResponse: Decodable {
    let id: String
    let isInTrash: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case isInTrash = "in_trash"
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> [[Element]] {
        stride(from: 0, to: count, by: maximumCount).map {
            Array(self[$0..<Swift.min($0 + maximumCount, count)])
        }
    }
}
