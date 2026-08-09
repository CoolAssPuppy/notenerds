import Foundation
import XCTest
@testable import NoteNerds

final class NotionMeetingAPIBehaviorTests: XCTestCase {
    func testQueryRequestsRecentMeetingsAndDecodesAnActiveRecording() async throws {
        let meetingID = "11111111-1111-1111-1111-111111111111"
        let parentID = "22222222-2222-2222-2222-222222222222"
        let response = #"""
        {"results":[{"object":"block","id":"\#(meetingID)",
        "parent":{"type":"page_id","page_id":"\#(parentID)"},
        "last_edited_time":"2026-08-09T10:00:00.000Z","type":"meeting_notes",
        "meeting_notes":{"title":[{"plain_text":"Weekly planning"}],
        "status":"transcription_in_progress","recording":{"start_time":"2026-08-09T09:55:00.000Z"}}}],
        "has_more":false}
        """#
        let transport = MeetingStubTransport(responses: [.json(200, response)])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let meetings = try await client.queryMeetingNotes()
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(request)
        let sort = try XCTUnwrap(body["sort"] as? [[String: String]])

        XCTAssertEqual(meetings.first?.id, meetingID)
        XCTAssertEqual(meetings.first?.parentBlockID, parentID)
        XCTAssertEqual(meetings.first?.title, "Weekly planning")
        XCTAssertEqual(meetings.first?.status, .transcriptionInProgress)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/blocks/meeting_notes/query")
        XCTAssertEqual(body["limit"] as? Int, 10)
        XCTAssertEqual(sort, [["property": "created_time", "direction": "descending"]])
    }

    func testQueryRetrievesTheParentWhenTheResponseOmitsIt() async throws {
        let meetingID = "12121212-1212-1212-1212-121212121212"
        let parentID = "34343434-3434-3434-3434-343434343434"
        let queryResponse = #"""
        {"results":[{"id":"\#(meetingID)",
        "last_edited_time":"2026-08-09T10:00:00Z","type":"meeting_notes",
        "meeting_notes":{"title":[],"status":"transcription_in_progress"}}],"has_more":false}
        """#
        let parentResponse = #"""
        {"id":"\#(meetingID)","parent":{"type":"page_id","page_id":"\#(parentID)"}}
        """#
        let transport = MeetingStubTransport(responses: [
            .json(200, queryResponse), .json(200, parentResponse)
        ])

        let meetings = try await NotionAPIClient(
            accessToken: "token",
            transport: transport
        ).queryMeetingNotes()
        let requests = await transport.requests

        XCTAssertEqual(meetings.first?.parentBlockID, parentID)
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/v1/blocks/meeting_notes/query", "/v1/blocks/\(meetingID)"
        ])
    }

    func testLinkIsInsertedAfterTheRecordingAndExistingLinksCanBeFound() async throws {
        let parentID = "33333333-3333-3333-3333-333333333333"
        let meetingID = "44444444-4444-4444-4444-444444444444"
        let pageID = "55555555-5555-5555-5555-555555555555"
        let linkID = "66666666-6666-6666-6666-666666666666"
        let transport = MeetingStubTransport(responses: [
            .json(200, #"""
            {"results":[{"id":"\#(linkID)","type":"link_to_page",
            "link_to_page":{"type":"page_id","page_id":"\#(pageID)"}}],
            "has_more":false,"next_cursor":null}
            """#),
            .json(200, #"{"results":[{"id":"\#(linkID)"}],"has_more":false,"next_cursor":null}"#)
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let links = try await client.listNotebookLinks(parentBlockID: parentID)
        let insertedID = try await client.insertNotebookLink(
            parentBlockID: parentID,
            afterBlockID: meetingID,
            notebookPageID: pageID
        )
        let requests = await transport.requests
        let insertBody = try jsonBody(requests[1])

        XCTAssertEqual(links, [NotionNotebookLinkBlock(id: linkID, pageID: pageID)])
        XCTAssertEqual(insertedID, linkID)
        XCTAssertEqual(requests[0].url?.path, "/v1/blocks/\(parentID)/children")
        XCTAssertEqual(requests[1].httpMethod, "PATCH")
        let position = try XCTUnwrap(insertBody["position"] as? [String: Any])
        let after = try XCTUnwrap(position["after_block"] as? [String: String])
        XCTAssertEqual(after["id"], meetingID)
        let child = try XCTUnwrap((insertBody["children"] as? [[String: Any]])?.first)
        let target = try XCTUnwrap(child["link_to_page"] as? [String: String])
        XCTAssertEqual(target["page_id"], pageID)
    }

    func testLinkRemovalUsesTheBlockTrashEndpoint() async throws {
        let linkID = "77777777-7777-7777-7777-777777777777"
        let transport = MeetingStubTransport(responses: [
            .json(200, #"{"object":"block","id":"\#(linkID)","in_trash":true}"#)
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        try await client.trashMeetingLink(blockID: linkID)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/v1/blocks/\(linkID)")
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}

private actor MeetingStubTransport: NotionHTTPTransport {
    struct Response: Sendable {
        let status: Int
        let body: Data

        static func json(_ status: Int, _ body: String) -> Response {
            Response(status: status, body: Data(body.utf8))
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
            headerFields: [:]
        )!
        return (response.body, http)
    }
}
