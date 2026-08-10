import Foundation

struct NotionAPIClient: Sendable {
    private static let baseURL = URL(string: "https://api.notion.com/v1")!
    private static let notionVersion = "2026-03-11"
    private static let maximumPaginationRequests = 1_000
    private static let maximumResponseByteCount = 20 * 1_024 * 1_024

    private let accessToken: String
    let transport: any NotionHTTPTransport
    private let sleeper: any NotionSleeper
    private let maximumRetryCount: Int
    private let requestRateLimiter: NotionRequestRateLimiter
    private let retryJitter: @Sendable (ClosedRange<TimeInterval>) -> TimeInterval

    init(
        accessToken: String,
        transport: any NotionHTTPTransport = URLSessionNotionTransport(),
        sleeper: any NotionSleeper = TaskNotionSleeper(),
        maximumRetryCount: Int = 4,
        requestRateLimiter: NotionRequestRateLimiter = NotionRequestRateLimiter(),
        retryJitter: @escaping @Sendable (ClosedRange<TimeInterval>) -> TimeInterval = {
            Double.random(in: $0)
        }
    ) {
        self.accessToken = accessToken
        self.transport = transport
        self.sleeper = sleeper
        self.maximumRetryCount = max(0, maximumRetryCount)
        self.requestRateLimiter = requestRateLimiter
        self.retryJitter = retryJitter
    }

    func searchPages(query: String?) async throws -> [NotionPageSummary] {
        var pages: [NotionPageSummary] = []
        var cursor: String?
        var seenCursors: Set<String> = []
        var requestCount = 0
        repeat {
            guard requestCount < Self.maximumPaginationRequests else {
                throw NotionAPIError.paginationLimit
            }
            let body = searchBody(query: query, cursor: cursor)
            let request = try makeRequest(path: "search", method: "POST", body: body)
            let data = try await send(request)
            let response = try JSONDecoder().decode(SearchResponse.self, from: data)
            pages.append(contentsOf: response.results.map(\.summary))
            requestCount += 1
            guard response.hasMore else { cursor = nil; continue }
            guard let next = response.nextCursor, !next.isEmpty else {
                throw NotionAPIError.invalidResponse
            }
            guard seenCursors.insert(next).inserted else {
                throw NotionAPIError.repeatedCursor
            }
            cursor = next
        } while cursor != nil
        return pages
    }

    func createDatabase(parentPageID: String) async throws -> NotionDestination {
        guard UUID(uuidString: parentPageID) != nil else { throw NotionAPIError.invalidIdentifier }
        let title = Self.richText("Note Nerds")
        let body: NotionJSONValue = .object([
            "parent": .object(["type": .string("page_id"), "page_id": .string(parentPageID)]),
            "title": .array([title]),
            "is_inline": .bool(false),
            "initial_data_source": .object([
                "properties": .object(NotionDatabaseSchema.properties)
            ])
        ])
        let request = try makeRequest(path: "databases", method: "POST", body: body)
        let data = try await send(request)
        let response = try JSONDecoder().decode(DatabaseResponse.self, from: data)
        guard UUID(uuidString: response.id) != nil,
              let source = response.dataSources.first,
              UUID(uuidString: source.id) != nil else {
            throw NotionAPIError.invalidResponse
        }
        return NotionDestination(
            parentPageID: parentPageID,
            databaseID: response.id,
            dataSourceID: source.id
        )
    }

    func send(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            do {
                try await requestRateLimiter.acquire()
                let (data, response) = try await transport.data(for: request)
                guard data.count <= Self.maximumResponseByteCount else {
                    throw NotionAPIError.payloadTooLarge
                }
                if (200..<300).contains(response.statusCode) { return data }
                guard attempt < maximumRetryCount, Self.isRetryable(response.statusCode) else {
                    throw Self.responseError(status: response.statusCode, data: data)
                }
                let delay = retryDelay(response: response, attempt: attempt)
                try await sleeper.sleep(seconds: delay)
            } catch let error as NotionAPIError {
                throw error
            } catch {
                guard attempt < maximumRetryCount else { throw error }
                try await sleeper.sleep(seconds: exponentialDelay(attempt: attempt))
            }
            attempt += 1
        }
    }

    func send(_ request: URLRequest, uploadFileURL: URL) async throws -> Data {
        var attempt = 0
        while true {
            do {
                try await requestRateLimiter.acquire()
                let (data, response) = try await transport.upload(
                    for: request,
                    fromFile: uploadFileURL
                )
                guard data.count <= Self.maximumResponseByteCount else {
                    throw NotionAPIError.payloadTooLarge
                }
                if (200..<300).contains(response.statusCode) { return data }
                guard attempt < maximumRetryCount, Self.isRetryable(response.statusCode) else {
                    throw Self.responseError(status: response.statusCode, data: data)
                }
                try await sleeper.sleep(
                    seconds: retryDelay(response: response, attempt: attempt)
                )
            } catch let error as NotionAPIError {
                throw error
            } catch {
                guard attempt < maximumRetryCount else { throw error }
                try await sleeper.sleep(seconds: exponentialDelay(attempt: attempt))
            }
            attempt += 1
        }
    }

    func makeRequest(
        path: String,
        method: String,
        body: NotionJSONValue
    ) throws -> URLRequest {
        let url = Self.baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.notionVersion, forHTTPHeaderField: "Notion-Version")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(body)
        return request
    }

    func makeRequest(
        path: String,
        method: String,
        data: Data,
        contentType: String
    ) -> URLRequest {
        var request = baseRequest(path: path, method: method)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }

    func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem]
    ) throws -> URLRequest {
        var request = baseRequest(path: path, method: method)
        guard var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else {
            throw NotionAPIError.invalidResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw NotionAPIError.invalidResponse }
        request.url = url
        return request
    }

    func baseRequest(path: String, method: String) -> URLRequest {
        let url = Self.baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.notionVersion, forHTTPHeaderField: "Notion-Version")
        return request
    }

    private func searchBody(query: String?, cursor: String?) -> NotionJSONValue {
        var body: [String: NotionJSONValue] = [
            "page_size": .number(100),
            "filter": .object(["property": .string("object"), "value": .string("page")])
        ]
        if let query, !query.isEmpty { body["query"] = .string(query) }
        if let cursor { body["start_cursor"] = .string(cursor) }
        return .object(body)
    }

    private static func richText(_ content: String) -> NotionJSONValue {
        .object([
            "type": .string("text"),
            "text": .object(["content": .string(content)])
        ])
    }

    private static func isRetryable(_ status: Int) -> Bool {
        status == 429 || [500, 502, 503, 504].contains(status)
    }

    private static func responseError(status: Int, data: Data) -> NotionAPIError {
        guard let response = try? JSONDecoder().decode(NotionErrorResponse.self, from: data),
              let code = bounded(response.code, maximumCount: 200),
              let message = bounded(response.message, maximumCount: 1_000) else {
            return .httpStatus(status)
        }
        return .rejected(
            status: status,
            code: code,
            message: message,
            requestID: bounded(response.requestID, maximumCount: 200)
        )
    }

    private static func bounded(_ value: String?, maximumCount: Int) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return String(value.prefix(maximumCount))
    }

    private func retryDelay(response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if response.statusCode == 429,
           let value = response.value(forHTTPHeaderField: "Retry-After"),
           let delay = TimeInterval(value), delay >= 0 {
            return min(delay, 120)
        }
        return exponentialDelay(attempt: attempt)
    }

    private func exponentialDelay(attempt: Int) -> TimeInterval {
        let base = min(pow(2, Double(attempt)), 30)
        return min(base + retryJitter(0...base), 30)
    }
}

private struct NotionErrorResponse: Decodable {
    let code: String?
    let message: String?
    let requestID: String?

    private enum CodingKeys: String, CodingKey {
        case code, message
        case requestID = "request_id"
    }
}

private struct SearchResponse: Decodable {
    let results: [SearchResult]
    let hasMore: Bool
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

private struct SearchResult: Decodable {
    let id: String
    let url: URL?
    let properties: [String: PageProperty]

    var summary: NotionPageSummary {
        let title = properties.values.first(where: { $0.type == "title" })?
            .title?.first?.plainText ?? "Untitled"
        return NotionPageSummary(id: id, title: title, url: url)
    }
}

private struct PageProperty: Decodable {
    let type: String
    let title: [PageRichText]?
}

private struct PageRichText: Decodable {
    let plainText: String

    private enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
    }
}

private struct DatabaseResponse: Decodable {
    let id: String
    let dataSources: [DataSource]

    private enum CodingKeys: String, CodingKey {
        case id
        case dataSources = "data_sources"
    }

    struct DataSource: Decodable {
        let id: String
    }
}
