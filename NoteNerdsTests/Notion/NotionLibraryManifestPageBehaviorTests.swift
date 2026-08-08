import XCTest
@testable import NoteNerds

final class NotionLibraryManifestPageBehaviorTests: XCTestCase {
    func testManifestPageIsCreatedBesideTheNotebookDatabase() async throws {
        let parentID = "11111111-1111-1111-1111-111111111111"
        let pageID = "22222222-2222-2222-2222-222222222222"
        let transport = ManifestTransport(responses: [
            .json(200, #"{"object":"page","id":"\#(pageID)","url":"https://www.notion.so/manifest"}"#)
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let page = try await client.createLibraryManifestPage(parentPageID: parentID)
        let requests = await transport.allRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try jsonBody(request)
        let parent = try XCTUnwrap(body["parent"] as? [String: String])
        let properties = try XCTUnwrap(body["properties"] as? [String: Any])
        let titleProperty = try XCTUnwrap(properties["title"] as? [String: Any])
        let title = try XCTUnwrap(titleProperty["title"] as? [[String: Any]])
        let text = try XCTUnwrap(title.first?["text"] as? [String: String])

        XCTAssertEqual(page.pageID, pageID)
        XCTAssertEqual(request.url?.path, "/v1/pages")
        XCTAssertEqual(parent, ["type": "page_id", "page_id": parentID])
        XCTAssertEqual(text["content"], "Note Nerds Library Manifest")
        XCTAssertNil(titleProperty["type"])
    }

    func testManifestPlanContainsAStableMarkerAndUploadedManifestFile() throws {
        let uploadID = "33333333-3333-3333-3333-333333333333"

        let plan = try NotionLibraryManifestPageBuilder.plan(uploadID: uploadID)
        let root = try jsonObject(plan.root)
        let children = try plan.children.map(jsonObject)
        let toggle = try XCTUnwrap(root["toggle"] as? [String: Any])
        let code = try XCTUnwrap(children[0]["code"] as? [String: Any])
        let file = try XCTUnwrap(children[1]["file"] as? [String: Any])
        let fileUpload = try XCTUnwrap(file["file_upload"] as? [String: String])

        XCTAssertEqual(try richText(toggle), "Note Nerds library manifest")
        XCTAssertEqual(try richText(code), "note-nerds-library-manifest-v1")
        XCTAssertEqual(file["type"] as? String, "file_upload")
        XCTAssertEqual(fileUpload["id"], uploadID)
    }

    func testManifestPlanRejectsAnInvalidUploadIdentifier() {
        XCTAssertThrowsError(try NotionLibraryManifestPageBuilder.plan(uploadID: "../unsafe")) { error in
            XCTAssertEqual(error as? NotionAPIError, .invalidIdentifier)
        }
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func jsonObject(_ value: NotionJSONValue) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func richText(_ container: [String: Any]) throws -> String {
        let values = try XCTUnwrap(container["rich_text"] as? [[String: Any]])
        let text = try XCTUnwrap(values.first?["text"] as? [String: String])
        return try XCTUnwrap(text["content"])
    }
}

private actor ManifestTransport: NotionHTTPTransport {
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

    func allRequests() -> [URLRequest] { requests }
}
