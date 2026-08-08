import XCTest
@testable import NoteNerds

final class NotionRestoreAPIBehaviorTests: XCTestCase {
    func testListsEveryNativeNotebookFileAcrossDataSourcePages() async throws {
        let firstURL = "https://secure.notion-static.com/first.notenerds"
        let secondURL = "https://secure.notion-static.com/second.notenerds"
        let transport = RestoreAPITransport(responses: [
            // swiftlint:disable:next line_length
            .json(200, queryResponse(page: "11111111-1111-1111-1111-111111111111", notebook: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", fileURL: firstURL, cursor: "next")),
            // swiftlint:disable:next line_length
            .json(200, queryResponse(page: "22222222-2222-2222-2222-222222222222", notebook: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", fileURL: secondURL, cursor: nil))
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let files = try await client.listNativeNotebookFiles(
            dataSourceID: "33333333-3333-3333-3333-333333333333"
        )
        let requests = await transport.requests

        XCTAssertEqual(files.map(\.notebookID), [
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        ])
        XCTAssertEqual(files.map(\.url.absoluteString), [firstURL, secondURL])
        XCTAssertEqual(files.map(\.contentHash), [
            String(repeating: "a", count: 64),
            String(repeating: "b", count: 64)
        ])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/v1/data_sources/33333333-3333-3333-3333-333333333333/query")
        XCTAssertEqual(try jsonBody(requests[1])["start_cursor"] as? String, "next")
    }

    func testFindsManifestAttachmentAndDownloadsWithoutSendingNotionToken() async throws {
        let rootID = "44444444-4444-4444-4444-444444444444"
        let fileURL = "https://secure.notion-static.com/library-manifest.json"
        let transport = RestoreAPITransport(responses: [
            // swiftlint:disable:next line_length
            .json(200, #"{"results":[{"id":"55555555-5555-5555-5555-555555555555","type":"file","file":{"type":"file","file":{"url":"\#(fileURL)"}}}],"has_more":false,"next_cursor":null}"#),
            .data(200, Data("manifest".utf8), headers: ["Content-Length": "8"])
        ])
        let client = NotionAPIClient(accessToken: "private-token", transport: transport)

        let remoteURL = try await client.findManagedFile(rootBlockID: rootID)
        let downloaded = try await client.downloadFile(from: remoteURL, maximumByteCount: 100)
        let requests = await transport.requests

        XCTAssertEqual(downloaded, Data("manifest".utf8))
        XCTAssertEqual(requests[0].url?.path, "/v1/blocks/\(rootID)/children")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer private-token")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[1].url?.absoluteString, fileURL)
    }

    func testFetchesTheLatestNotebookPageBeforeUsingItsTemporaryFileURL() async throws {
        let pageID = "66666666-6666-6666-6666-666666666666"
        let notebookID = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        let freshURL = "https://secure.notion-static.com/fresh.notenerds"
        let transport = RestoreAPITransport(responses: [
            .json(200, pageResponse(
                page: pageID,
                notebook: notebookID,
                fileURL: freshURL,
                contentHash: String(repeating: "c", count: 64)
            ))
        ])
        let client = NotionAPIClient(accessToken: "private-token", transport: transport)

        let file = try await client.fetchNativeNotebookFile(pageID: pageID)
        let requests = await transport.requests

        XCTAssertEqual(file.pageID, pageID)
        XCTAssertEqual(file.notebookID, notebookID.lowercased())
        XCTAssertEqual(file.contentHash, String(repeating: "c", count: 64))
        XCTAssertEqual(file.url.absoluteString, freshURL)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].url?.path, "/v1/pages/\(pageID)")
    }

    func testDownloadRejectsInsecureAndOversizedResponses() async {
        let unused = NotionAPIClient(accessToken: "token", transport: RestoreAPITransport(responses: []))
        do {
            _ = try await unused.downloadFile(
                from: URL(string: "http://example.com/file")!,
                maximumByteCount: 10
            )
            XCTFail("Expected an insecure URL to fail")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, .invalidResponse)
        }

        let oversized = NotionAPIClient(
            accessToken: "token",
            transport: RestoreAPITransport(responses: [
                .data(200, Data(repeating: 1, count: 11), headers: ["Content-Length": "11"])
            ])
        )
        do {
            _ = try await oversized.downloadFile(
                from: URL(string: "https://secure.notion-static.com/file")!,
                maximumByteCount: 10
            )
            XCTFail("Expected an oversized file to fail")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, .payloadTooLarge)
        }
    }

    private func queryResponse(page: String, notebook: String, fileURL: String, cursor: String?) -> String {
        let next = cursor.map { "\"\($0)\"" } ?? "null"
        let hashCharacter = notebook.first?.lowercased() ?? "0"
        let contentHash = String(repeating: hashCharacter, count: 64)
        let page = pageResponse(
            page: page,
            notebook: notebook,
            fileURL: fileURL,
            contentHash: contentHash
        )
        return #"{"results":[\#(page)],"has_more":\#(cursor == nil ? "false" : "true"),"next_cursor":\#(next)}"#
    }

    private func pageResponse(
        page: String,
        notebook: String,
        fileURL: String,
        contentHash: String
    ) -> String {
        // swiftlint:disable:next line_length
        #"{"id":"\#(page)","properties":{"Notebook ID":{"type":"rich_text","rich_text":[{"plain_text":"\#(notebook)"}]},"Content Hash":{"type":"rich_text","rich_text":[{"plain_text":"\#(contentHash)"}]},"Native Notebook":{"type":"files","files":[{"type":"file","file":{"url":"\#(fileURL)"}}]}}}"#
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}

private actor RestoreAPITransport: NotionHTTPTransport {
    struct Response: Sendable {
        let status: Int
        let body: Data
        let headers: [String: String]

        static func json(_ status: Int, _ value: String) -> Response {
            Response(status: status, body: Data(value.utf8), headers: [:])
        }

        static func data(_ status: Int, _ value: Data, headers: [String: String]) -> Response {
            Response(status: status, body: value, headers: headers)
        }
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        return (
            response.body,
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
        )
    }
}
