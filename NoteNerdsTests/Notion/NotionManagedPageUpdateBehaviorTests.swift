import XCTest
@testable import NoteNerds

final class NotionManagedPageUpdateBehaviorTests: XCTestCase {
    func testManagedPageReplacementBatchesChildrenAndDeletesOldSectionLast() async throws {
        let pageID = "11111111-1111-1111-1111-111111111111"
        let oldRootID = "22222222-2222-2222-2222-222222222222"
        let newRootID = "33333333-3333-3333-3333-333333333333"
        let children = (0..<205).map { paragraph("Child \($0)") }
        let transport = ManagedPageTransport(responses: [
            .json(200, appendResponse(blockID: newRootID)),
            .json(200, appendResponse(blockID: "44444444-4444-4444-4444-444444444444")),
            .json(200, appendResponse(blockID: "55555555-5555-5555-5555-555555555555")),
            .json(200, appendResponse(blockID: "66666666-6666-6666-6666-666666666666")),
            .json(200, #"{"object":"block","id":"\#(oldRootID)","in_trash":true}"#)
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let result = try await client.replaceManagedPage(
            pageID: pageID,
            oldRootID: oldRootID,
            plan: NotionManagedPagePlan(root: toggle("Note Nerds content"), children: children)
        )
        let requests = await transport.allRequests()

        XCTAssertEqual(result, newRootID)
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests[0].url?.path, "/v1/blocks/\(pageID)/children")
        XCTAssertEqual(requests[1].url?.path, "/v1/blocks/\(newRootID)/children")
        XCTAssertEqual(requests[2].url?.path, "/v1/blocks/\(newRootID)/children")
        XCTAssertEqual(requests[3].url?.path, "/v1/blocks/\(newRootID)/children")
        XCTAssertEqual(requests[4].url?.path, "/v1/blocks/\(oldRootID)")
        XCTAssertEqual(requests[4].httpMethod, "DELETE")
        XCTAssertEqual(try childCount(requests[0]), 1)
        XCTAssertEqual(try childCount(requests[1]), 100)
        XCTAssertEqual(try childCount(requests[2]), 100)
        XCTAssertEqual(try childCount(requests[3]), 5)
    }

    func testManagedPageReplacementKeepsOldSectionWhenNewContentFails() async throws {
        let pageID = "77777777-7777-7777-7777-777777777777"
        let oldRootID = "88888888-8888-8888-8888-888888888888"
        let newRootID = "99999999-9999-9999-9999-999999999999"
        let children = (0..<101).map { paragraph("Child \($0)") }
        let transport = ManagedPageTransport(responses: [
            .json(200, appendResponse(blockID: newRootID)),
            .json(200, appendResponse(blockID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
            .json(400, #"{"object":"error","code":"validation_error"}"#),
            .json(200, #"{"object":"block","id":"\#(newRootID)","in_trash":true}"#)
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport, maximumRetryCount: 0)

        do {
            _ = try await client.replaceManagedPage(
                pageID: pageID,
                oldRootID: oldRootID,
                plan: NotionManagedPagePlan(root: toggle("Note Nerds content"), children: children)
            )
            XCTFail("Expected the failed child batch to stop replacement")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, .httpStatus(400))
        }
        let requests = await transport.allRequests()
        let deletedIDs = requests
            .filter { $0.httpMethod == "DELETE" }
            .compactMap { $0.url?.lastPathComponent }
        XCTAssertEqual(deletedIDs, [newRootID])
        XCTAssertFalse(deletedIDs.contains(oldRootID))
    }

    func testManagedRootDiscoveryPaginatesAndValidatesNotebookMarker() async throws {
        let pageID = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        let candidateID = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        let notebookID = "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
        let transport = ManagedPageTransport(responses: [
            .json(200, blockList(
                blocks: [toggleBlock(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", title: "User content")],
                nextCursor: "next"
            )),
            .json(200, blockList(
                blocks: [toggleBlock(id: candidateID, title: "Note Nerds content")],
                nextCursor: nil
            )),
            .json(200, blockList(
                blocks: [
                    codeBlock(id: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", text: "note-nerds-managed-v1"),
                    paragraphBlock(
                        id: "12121212-1212-1212-1212-121212121212",
                        text: "Notebook ID: \(notebookID)"
                    )
                ],
                nextCursor: nil
            ))
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let result = try await client.findManagedRootBlock(pageID: pageID, notebookID: notebookID)
        let requests = await transport.allRequests()

        XCTAssertEqual(result, candidateID)
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].url?.query, "page_size=100")
        XCTAssertEqual(requests[1].url?.query, "page_size=100&start_cursor=next")
        XCTAssertEqual(requests[2].url?.path, "/v1/blocks/\(candidateID)/children")
    }

    private func childCount(_ request: URLRequest) throws -> Int {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        return try XCTUnwrap(object["children"] as? [Any]).count
    }

    private func appendResponse(blockID: String) -> String {
        #"{"object":"list","results":[{"object":"block","id":"\#(blockID)"}],"has_more":false,"next_cursor":null}"#
    }

    private func blockList(blocks: [String], nextCursor: String?) -> String {
        let cursor = nextCursor.map { "\"\($0)\"" } ?? "null"
        // swiftlint:disable:next line_length
        return #"{"object":"list","results":[\#(blocks.joined(separator: ","))],"has_more":\#(nextCursor == nil ? "false" : "true"),"next_cursor":\#(cursor)}"#
    }

    private func toggleBlock(id: String, title: String) -> String {
        // swiftlint:disable:next line_length
        #"{"object":"block","id":"\#(id)","type":"toggle","has_children":true,"toggle":{"rich_text":[{"plain_text":"\#(title)"}]}}"#
    }

    private func codeBlock(id: String, text: String) -> String {
        // swiftlint:disable:next line_length
        #"{"object":"block","id":"\#(id)","type":"code","has_children":false,"code":{"rich_text":[{"plain_text":"\#(text)"}]}}"#
    }

    private func paragraphBlock(id: String, text: String) -> String {
        // swiftlint:disable:next line_length
        #"{"object":"block","id":"\#(id)","type":"paragraph","has_children":false,"paragraph":{"rich_text":[{"plain_text":"\#(text)"}]}}"#
    }

    private func paragraph(_ text: String) -> NotionJSONValue {
        .object([
            "type": .string("paragraph"),
            "paragraph": .object(["rich_text": .array([richText(text)])])
        ])
    }

    private func toggle(_ text: String) -> NotionJSONValue {
        .object([
            "type": .string("toggle"),
            "toggle": .object(["rich_text": .array([richText(text)])])
        ])
    }

    private func richText(_ text: String) -> NotionJSONValue {
        .object([
            "type": .string("text"),
            "text": .object(["content": .string(text)])
        ])
    }
}

private actor ManagedPageTransport: NotionHTTPTransport {
    struct Response: Sendable {
        let status: Int
        let body: Data

        static func json(_ status: Int, _ body: String) -> Response {
            Response(status: status, body: Data(body.utf8))
        }
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        return (
            response.body,
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
    }

    func allRequests() -> [URLRequest] {
        requests
    }
}
