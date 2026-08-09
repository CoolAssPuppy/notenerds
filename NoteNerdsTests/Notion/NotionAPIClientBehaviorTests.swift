import XCTest
@testable import NoteNerds

final class NotionAPIClientBehaviorTests: XCTestCase {
    func testProductionTransportDoesNotPersistNotionResponsesCookiesOrCredentials() {
        let configuration = URLSessionNotionTransport().session.configuration

        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.urlCredentialStorage, nil)
    }

    func testOrdinaryAPIResponsesHaveABoundedSize() async throws {
        let transport = StubNotionTransport(responses: [StubNotionTransport.Response(
            status: 200,
            body: Data(repeating: 0, count: 20 * 1_024 * 1_024 + 1),
            headers: [:]
        )])
        let client = NotionAPIClient(accessToken: "token", transport: transport)
        let request = client.baseRequest(path: "search", method: "POST")

        do {
            _ = try await client.send(request)
            XCTFail("Expected an oversized API response to be rejected")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, .payloadTooLarge)
        }
    }

    func testSearchPagesUsesCurrentHeadersAndFollowsPagination() async throws {
        let transport = StubNotionTransport(responses: [
            .json(200, searchResponse(idSuffix: "01", title: "Projects", nextCursor: "next")),
            .json(200, searchResponse(idSuffix: "02", title: "Journal", nextCursor: nil))
        ])
        let client = NotionAPIClient(accessToken: "access-token", transport: transport)

        let pages = try await client.searchPages(query: "notes")
        let requests = await transport.requests

        XCTAssertEqual(pages.map(\.title), ["Projects", "Journal"])
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/search")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2026-03-11")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        }
        XCTAssertNil(try jsonBody(requests[0])["start_cursor"])
        XCTAssertEqual(try jsonBody(requests[1])["start_cursor"] as? String, "next")
        XCTAssertEqual(try jsonBody(requests[0])["query"] as? String, "notes")
        let filter = try XCTUnwrap(try jsonBody(requests[0])["filter"] as? [String: String])
        XCTAssertEqual(filter, ["property": "object", "value": "page"])
    }

    func testPaginationRejectsARepeatedCursor() async throws {
        let transport = StubNotionTransport(responses: [
            .json(200, searchResponse(idSuffix: "01", title: "One", nextCursor: "repeat")),
            .json(200, searchResponse(idSuffix: "02", title: "Two", nextCursor: "repeat"))
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        do {
            _ = try await client.searchPages(query: nil)
            XCTFail("Expected pagination to reject the repeated cursor")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, .repeatedCursor)
        }
    }

    func testRateLimitWaitsForRetryAfterAndRetriesTheSameRequest() async throws {
        let transport = StubNotionTransport(responses: [
            .json(429, #"{"object":"error","code":"rate_limited","message":"Slow down"}"#, headers: [
                "Retry-After": "2"
            ]),
            .json(200, searchResponse(idSuffix: "01", title: "Ready", nextCursor: nil))
        ])
        let sleeper = RecordingNotionSleeper()
        let client = NotionAPIClient(
            accessToken: "token",
            transport: transport,
            sleeper: sleeper,
            maximumRetryCount: 2
        )

        let pages = try await client.searchPages(query: nil)
        let delays = await sleeper.delays
        let requestCount = await transport.requests.count

        XCTAssertEqual(pages.map(\.title), ["Ready"])
        XCTAssertEqual(delays, [2])
        XCTAssertEqual(requestCount, 2)
    }

    func testServiceRetryAddsInjectedJitterToBoundedExponentialDelay() async throws {
        let transport = StubNotionTransport(responses: [
            .json(503, #"{"object":"error","message":"Unavailable"}"#),
            .json(200, searchResponse(idSuffix: "01", title: "Ready", nextCursor: nil))
        ])
        let sleeper = RecordingNotionSleeper()
        let client = NotionAPIClient(
            accessToken: "token",
            transport: transport,
            sleeper: sleeper,
            maximumRetryCount: 1,
            retryJitter: { _ in 0.5 }
        )

        _ = try await client.searchPages(query: nil)
        let delays = await sleeper.delays

        XCTAssertEqual(delays, [1.5])
    }

    func testCreateDatabaseSendsTheCompleteNotebookSchemaAndStoresBothIDs() async throws {
        let databaseID = "11111111-1111-1111-1111-111111111111"
        let dataSourceID = "22222222-2222-2222-2222-222222222222"
        let response = #"""
        {
            "object":"database",
            "id":"\#(databaseID)",
            "data_sources":[{"id":"\#(dataSourceID)","name":"Note Nerds"}]
        }
        """#
        let transport = StubNotionTransport(responses: [.json(200, response)])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let destination = try await client.createDatabase(
            parentPageID: "33333333-3333-3333-3333-333333333333"
        )
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(request)
        let initialSource = try XCTUnwrap(body["initial_data_source"] as? [String: Any])
        let properties = try XCTUnwrap(initialSource["properties"] as? [String: Any])

        XCTAssertEqual(destination.databaseID, databaseID)
        XCTAssertEqual(destination.dataSourceID, dataSourceID)
        XCTAssertEqual(destination.parentPageID, "33333333-3333-3333-3333-333333333333")
        XCTAssertEqual(request.url?.path, "/v1/databases")
        XCTAssertEqual(Set(initialSource.keys), ["properties"])
        XCTAssertEqual(Set(properties.keys), Set(NotionDatabaseSchema.propertyNames))
        XCTAssertNotNil((properties["Name"] as? [String: Any])?["title"])
        XCTAssertNotNil((properties["Folder"] as? [String: Any])?["rich_text"])
        XCTAssertNotNil((properties["Modified"] as? [String: Any])?["date"])
        XCTAssertNotNil((properties["Canvas Count"] as? [String: Any])?["number"])
        XCTAssertNotNil((properties["Tags"] as? [String: Any])?["multi_select"])
        XCTAssertNotNil((properties["Favorite"] as? [String: Any])?["checkbox"])
        XCTAssertNotNil((properties["Native Notebook"] as? [String: Any])?["files"])
        XCTAssertNotNil((properties["PDF"] as? [String: Any])?["files"])
        XCTAssertNotNil((properties["Sync Status"] as? [String: Any])?["select"])
    }

    func testNotebookLookupUsesStableIDAndRejectsDuplicateRows() async throws {
        let pageID = "44444444-4444-4444-4444-444444444444"
        // swiftlint:disable:next line_length
        let response = #"{"results":[{"object":"page","id":"\#(pageID)","url":"https://www.notion.so/page"}],"has_more":false,"next_cursor":null}"#
        let transport = StubNotionTransport(responses: [.json(200, response)])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let page = try await client.findNotebookPage(
            dataSourceID: "55555555-5555-5555-5555-555555555555",
            notebookID: "66666666-6666-6666-6666-666666666666"
        )
        let lookupRequests = await transport.allRequests()
        let request = try XCTUnwrap(lookupRequests.first)
        let body = try jsonBody(request)
        let filter = try XCTUnwrap(body["filter"] as? [String: Any])
        let richText = try XCTUnwrap(filter["rich_text"] as? [String: String])

        XCTAssertEqual(page?.pageID, pageID)
        XCTAssertEqual(request.url?.path, "/v1/data_sources/55555555-5555-5555-5555-555555555555/query")
        XCTAssertEqual(filter["property"] as? String, "Notebook ID")
        XCTAssertEqual(richText["equals"], "66666666-6666-6666-6666-666666666666")

        // swiftlint:disable:next line_length
        let duplicateResponse = #"{"results":[{"id":"11111111-1111-1111-1111-111111111111"},{"id":"22222222-2222-2222-2222-222222222222"}],"has_more":false,"next_cursor":null}"#
        let duplicateClient = NotionAPIClient(
            accessToken: "token",
            transport: StubNotionTransport(responses: [.json(200, duplicateResponse)])
        )
        do {
            _ = try await duplicateClient.findNotebookPage(
                dataSourceID: "55555555-5555-5555-5555-555555555555",
                notebookID: "66666666-6666-6666-6666-666666666666"
            )
            XCTFail("Expected duplicate notebook rows to be rejected")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, .duplicateNotebookRows)
        }
    }

    func testCreateNotebookPageWritesEveryRowPropertyAndUploadedFile() async throws {
        let pageID = "77777777-7777-7777-7777-777777777777"
        let transport = StubNotionTransport(responses: [
            .json(200, #"{"object":"page","id":"\#(pageID)","url":"https://www.notion.so/notebook"}"#)
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)
        let snapshot = try notionSnapshot()
        let files = NotionNotebookRemoteFiles(
            nativeUploadID: "88888888-8888-8888-8888-888888888888",
            pdfUploadID: "99999999-9999-9999-9999-999999999999"
        )

        let page = try await client.createNotebookPage(
            dataSourceID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            snapshot: snapshot,
            files: files
        )
        let createRequests = await transport.allRequests()
        let request = try XCTUnwrap(createRequests.first)
        let body = try jsonBody(request)
        let parent = try XCTUnwrap(body["parent"] as? [String: String])
        let properties = try XCTUnwrap(body["properties"] as? [String: Any])

        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(request.url?.path, "/v1/pages")
        XCTAssertEqual(parent["type"], "data_source_id")
        XCTAssertEqual(parent["data_source_id"], "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        XCTAssertEqual(try titleText(properties, name: "Name"), "Project Atlas")
        XCTAssertEqual(try richText(properties, name: "Folder"), "Projects")
        XCTAssertEqual(try richText(properties, name: "Folder ID"), snapshot.row.folderID)
        XCTAssertEqual(try richText(properties, name: "Notebook ID"), snapshot.row.notebookID)
        XCTAssertEqual(try richText(properties, name: "Content Hash"), snapshot.row.contentHash)
        XCTAssertEqual(try number(properties, name: "Canvas Count"), 2)
        XCTAssertEqual(try number(properties, name: "Schema Version"), 4)
        XCTAssertEqual(try checkbox(properties, name: "Favorite"), true)
        XCTAssertEqual(try select(properties, name: "Sync Status"), "Complete")
        XCTAssertEqual(try multiSelect(properties, name: "Tags"), ["planning", "work，personal"])
        XCTAssertEqual(
            try fileUploadID(properties, name: "Native Notebook"),
            "88888888-8888-8888-8888-888888888888"
        )
        XCTAssertEqual(
            try fileUploadID(properties, name: "PDF"),
            "99999999-9999-9999-9999-999999999999"
        )
    }

    func testPermanentAppDeletionMovesTheBoundNotebookPageToNotionTrash() async throws {
        let pageID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let transport = StubNotionTransport(responses: [
            .json(200, #"{"object":"page","id":"\#(pageID)","in_trash":true}"#)
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        try await client.trashNotebookPage(pageID: pageID)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(request)

        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/v1/pages/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        XCTAssertEqual(body["in_trash"] as? Bool, true)
        XCTAssertEqual(Set(body.keys), ["in_trash"])
    }

    func testUpdateNotebookPageReplacesPropertiesWithoutChangingItsParent() async throws {
        let pageID = "10101010-1010-1010-1010-101010101010"
        let transport = StubNotionTransport(responses: [
            .json(200, #"{"object":"page","id":"\#(pageID)","url":"https://www.notion.so/notebook"}"#)
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)
        let snapshot = try notionSnapshot()
        let files = NotionNotebookRemoteFiles(
            nativeUploadID: "20202020-2020-2020-2020-202020202020",
            pdfUploadID: "30303030-3030-3030-3030-303030303030"
        )

        let page = try await client.updateNotebookPage(
            pageID: pageID,
            snapshot: snapshot,
            files: files
        )
        let requests = await transport.allRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(request)

        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/v1/pages/\(pageID)")
        XCTAssertNil(body["parent"])
        let properties = try XCTUnwrap(body["properties"] as? [String: Any])
        XCTAssertEqual(try richText(properties, name: "Folder"), "Projects")
        XCTAssertEqual(try richText(properties, name: "Content Hash"), snapshot.row.contentHash)
        XCTAssertEqual(
            try fileUploadID(properties, name: "Native Notebook"),
            files.nativeUploadID
        )
    }

    private func searchResponse(
        idSuffix: String,
        title: String,
        nextCursor: String?
    ) -> String {
        let id = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA\(idSuffix)"
        let cursor = nextCursor.map { "\"\($0)\"" } ?? "null"
        return #"""
        {
            "object":"list",
            "results":[{
                "object":"page",
                "id":"\#(id)",
                "url":"https://www.notion.so/\#(id)",
                "properties":{"Name":{"type":"title","title":[{"plain_text":"\#(title)"}]}}
            }],
            "has_more":\#(nextCursor == nil ? "false" : "true"),
            "next_cursor":\#(cursor)
        }
        """#
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func notionSnapshot() throws -> NotionNotebookSnapshot {
        let folder = Folder(
            id: FolderID(rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!),
            name: "Projects",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        var notebook = DomainFixtures.notebook(title: "Project Atlas")
        notebook.parentFolderID = folder.id
        notebook.tags = ["work,personal", "planning"]
        notebook.isFavorite = true
        notebook.canvases.append(
            Canvas(title: "Canvas 2", createdAt: DomainFixtures.fixedDate, modifiedAt: DomainFixtures.fixedDate)
        )
        return try NotionNotebookMapper.snapshot(
            for: notebook,
            in: LibraryState(folders: [folder], notebooks: [notebook]),
            contentHash: String(repeating: "d", count: 64)
        )
    }

    private func titleText(_ properties: [String: Any], name: String) throws -> String {
        let property = try XCTUnwrap(properties[name] as? [String: Any])
        let values = try XCTUnwrap(property["title"] as? [[String: Any]])
        return try textContent(values)
    }

    private func richText(_ properties: [String: Any], name: String) throws -> String {
        let property = try XCTUnwrap(properties[name] as? [String: Any])
        let values = try XCTUnwrap(property["rich_text"] as? [[String: Any]])
        return try textContent(values)
    }

    private func textContent(_ values: [[String: Any]]) throws -> String {
        let text = try XCTUnwrap(values.first?["text"] as? [String: String])
        return try XCTUnwrap(text["content"])
    }

    private func number(_ properties: [String: Any], name: String) throws -> Int {
        let property = try XCTUnwrap(properties[name] as? [String: Any])
        return try XCTUnwrap(property["number"] as? Int)
    }

    private func checkbox(_ properties: [String: Any], name: String) throws -> Bool {
        let property = try XCTUnwrap(properties[name] as? [String: Any])
        return try XCTUnwrap(property["checkbox"] as? Bool)
    }

    private func select(_ properties: [String: Any], name: String) throws -> String {
        let property = try XCTUnwrap(properties[name] as? [String: Any])
        let select = try XCTUnwrap(property["select"] as? [String: String])
        return try XCTUnwrap(select["name"])
    }

    private func multiSelect(_ properties: [String: Any], name: String) throws -> [String] {
        let property = try XCTUnwrap(properties[name] as? [String: Any])
        let values = try XCTUnwrap(property["multi_select"] as? [[String: String]])
        return values.compactMap { $0["name"] }
    }

    private func fileUploadID(_ properties: [String: Any], name: String) throws -> String {
        let property = try XCTUnwrap(properties[name] as? [String: Any])
        let files = try XCTUnwrap(property["files"] as? [[String: Any]])
        let upload = try XCTUnwrap(files.first?["file_upload"] as? [String: String])
        return try XCTUnwrap(upload["id"])
    }
}

private actor StubNotionTransport: NotionHTTPTransport {
    struct Response: Sendable {
        let status: Int
        let body: Data
        let headers: [String: String]

        static func json(_ status: Int, _ body: String, headers: [String: String] = [:]) -> Response {
            Response(status: status, body: Data(body.utf8), headers: headers)
        }
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        return (response.body, http)
    }

    func allRequests() -> [URLRequest] {
        requests
    }
}

private actor RecordingNotionSleeper: NotionSleeper {
    private(set) var delays: [TimeInterval] = []

    func sleep(seconds: TimeInterval) async throws {
        delays.append(seconds)
    }
}
