import Foundation

protocol NotionHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse)
    func download(
        for request: URLRequest,
        maximumByteCount: Int
    ) async throws -> (Data, HTTPURLResponse)
}

extension NotionHTTPTransport {
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        var inMemoryRequest = request
        inMemoryRequest.httpBody = try Data(contentsOf: fileURL)
        return try await data(for: inMemoryRequest)
    }

    func download(
        for request: URLRequest,
        maximumByteCount: Int
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard data.count <= maximumByteCount else { throw NotionAPIError.payloadTooLarge }
        return (data, response)
    }
}

protocol NotionSleeper: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

struct URLSessionNotionTransport: NotionHTTPTransport {
    let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NotionAPIError.invalidResponse
        }
        return (data, http)
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else {
            throw NotionAPIError.invalidResponse
        }
        return (data, http)
    }

    func download(
        for request: URLRequest,
        maximumByteCount: Int
    ) async throws -> (Data, HTTPURLResponse) {
        let (fileURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NotionAPIError.invalidResponse
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.int64Value <= Int64(maximumByteCount) else {
            throw NotionAPIError.payloadTooLarge
        }
        return (try Data(contentsOf: fileURL, options: .mappedIfSafe), http)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }
}

struct TaskNotionSleeper: NotionSleeper {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

enum NotionAPIError: Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidFilename
    case invalidContentType
    case emptyFile
    case invalidResponse
    case repeatedCursor
    case paginationLimit
    case duplicateNotebookRows
    case duplicateManagedSections
    case payloadTooLarge
    case httpStatus(Int)
}

struct NotionPageSummary: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL?
}

struct NotionDestination: Codable, Equatable, Sendable {
    let parentPageID: String?
    let databaseID: String
    let dataSourceID: String

    init(parentPageID: String? = nil, databaseID: String, dataSourceID: String) {
        self.parentPageID = parentPageID
        self.databaseID = databaseID
        self.dataSourceID = dataSourceID
    }
}

struct NotionPageBinding: Codable, Equatable, Sendable {
    let pageID: String
    let url: URL?
}

struct NotionNotebookRemoteFiles: Equatable, Sendable {
    let nativeUploadID: String
    let pdfUploadID: String
}

enum NotionJSONValue: Encodable, Equatable, Sendable {
    case object([String: NotionJSONValue])
    case array([NotionJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

enum NotionDatabaseSchema {
    static let propertyNames = [
        "Name", "Folder", "Folder ID", "Notebook ID", "Modified", "Trash Date",
        "Canvas Count", "Tags", "Favorite", "Schema Version", "Content Hash",
        "Native Notebook", "PDF", "Sync Status"
    ]

    static let properties: [String: NotionJSONValue] = [
        "Name": emptySchema("title"),
        "Folder": emptySchema("rich_text"),
        "Folder ID": emptySchema("rich_text"),
        "Notebook ID": emptySchema("rich_text"),
        "Modified": emptySchema("date"),
        "Trash Date": emptySchema("date"),
        "Canvas Count": .object(["number": .object(["format": .string("number")])]),
        "Tags": emptySchema("multi_select"),
        "Favorite": emptySchema("checkbox"),
        "Schema Version": .object(["number": .object(["format": .string("number")])]),
        "Content Hash": emptySchema("rich_text"),
        "Native Notebook": emptySchema("files"),
        "PDF": emptySchema("files"),
        "Sync Status": .object([
            "select": .object([
                "options": .array([
                    option("Complete", color: "green"),
                    option("Uploading", color: "yellow"),
                    option("Action needed", color: "red"),
                    option("In Trash", color: "gray")
                ])
            ])
        ])
    ]

    private static func emptySchema(_ name: String) -> NotionJSONValue {
        .object([name: .object([:])])
    }

    private static func option(_ name: String, color: String) -> NotionJSONValue {
        .object(["name": .string(name), "color": .string(color)])
    }
}
