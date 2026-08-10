import XCTest
@testable import NoteNerds

final class NotionFileUploadBehaviorTests: XCTestCase {
    func testSmallFileUsesSinglePartMultipartUpload() async throws {
        let uploadID = "11111111-1111-1111-1111-111111111111"
        let payload = Data([0x00, 0x0D, 0x0A, 0xFF])
        let transport = FileUploadTransport(responses: [
            .json(200, botResponse(maximumFileByteCount: 5 * 1_024 * 1_024)),
            .json(200, uploadResponse(id: uploadID, status: "pending")),
            .json(200, uploadResponse(id: uploadID, status: "uploaded"))
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let result = try await client.uploadFile(
            data: payload,
            filename: "canvas.png",
            contentType: "image/png"
        )
        let requests = await transport.allRequests()

        XCTAssertEqual(result, uploadID)
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/v1/users/me",
            "/v1/file_uploads",
            "/v1/file_uploads/\(uploadID)/send"
        ])
        let createBody = try jsonBody(requests[1])
        XCTAssertEqual(createBody["mode"] as? String, "single_part")
        XCTAssertEqual(createBody["filename"] as? String, "canvas.png")
        XCTAssertEqual(createBody["content_type"] as? String, "image/png")
        XCTAssertNil(createBody["number_of_parts"])
        try assertMultipart(
            requests[2],
            filename: "canvas.png",
            contentType: "image/png",
            payload: payload,
            partNumber: nil
        )
    }

    func testLargeFileUsesTenMegabytePartsAndCompletesUpload() async throws {
        let uploadID = "22222222-2222-2222-2222-222222222222"
        let tenMegabytes = 10 * 1_024 * 1_024
        let payload = Data(repeating: 0xA5, count: (2 * tenMegabytes) + 7)
        let transport = FileUploadTransport(responses: [
            .json(200, botResponse(maximumFileByteCount: 5 * 1_024 * 1_024 * 1_024)),
            .json(200, uploadResponse(id: uploadID, status: "pending")),
            .json(200, uploadResponse(id: uploadID, status: "pending")),
            .json(200, uploadResponse(id: uploadID, status: "pending")),
            .json(200, uploadResponse(id: uploadID, status: "pending")),
            .json(200, uploadResponse(id: uploadID, status: "uploaded"))
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        let result = try await client.uploadFile(
            data: payload,
            filename: "notebook.notenerds.json",
            contentType: "application/json"
        )
        let requests = await transport.allRequests()

        XCTAssertEqual(result, uploadID)
        XCTAssertEqual(requests.count, 6)
        let createBody = try jsonBody(requests[1])
        XCTAssertEqual(createBody["mode"] as? String, "multi_part")
        XCTAssertEqual(createBody["number_of_parts"] as? Int, 3)
        for partIndex in 0..<3 {
            let expectedSize = partIndex == 2 ? 7 : tenMegabytes
            try assertMultipart(
                requests[partIndex + 2],
                filename: "notebook.notenerds.json",
                contentType: "application/json",
                payloadSize: expectedSize,
                partNumber: partIndex + 1
            )
        }
        XCTAssertEqual(requests[5].url?.path, "/v1/file_uploads/\(uploadID)/complete")
        XCTAssertEqual(requests[5].httpMethod, "POST")
    }

    func testUploadRejectsBeforeCreationWhenConnectedWorkspaceLimitIsExceeded() async {
        let transport = FileUploadTransport(responses: [
            .json(200, botResponse(maximumFileByteCount: 5))
        ])
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        await assertUploadError(
            client: client,
            data: Data(repeating: 0xA5, count: 6),
            filename: "notebook.notenerds.json",
            contentType: "application/json",
            expected: .payloadTooLarge
        )
        let requests = await transport.allRequests()

        XCTAssertEqual(requests.map { $0.url?.path }, ["/v1/users/me"])
    }

    func testUploadRejectsUnsafeMetadataAndFilesAboveNotionLimit() async {
        let client = NotionAPIClient(
            accessToken: "token",
            transport: FileUploadTransport(responses: [])
        )

        await assertUploadError(
            client: client,
            data: Data(),
            filename: "../secret.pdf",
            contentType: "application/pdf",
            expected: .invalidFilename
        )
        await assertUploadError(
            client: client,
            data: Data(),
            filename: "document.pdf",
            contentType: "text/plain\r\nX-Injected: yes",
            expected: .invalidContentType
        )
        await assertUploadError(
            client: client,
            data: Data(),
            filename: "empty.pdf",
            contentType: "application/pdf",
            expected: .emptyFile
        )
        await assertUploadError(
            client: client,
            data: Data("archive".utf8),
            filename: "notebook.notenerds",
            contentType: "application/octet-stream",
            expected: .invalidContentType
        )
    }

    func testUploadRejectsMismatchedOrIncompleteNotionResponses() async throws {
        let expectedID = "33333333-3333-3333-3333-333333333333"
        let otherID = "44444444-4444-4444-4444-444444444444"
        let mismatch = FileUploadTransport(responses: [
            .json(200, botResponse(maximumFileByteCount: 5 * 1_024 * 1_024)),
            .json(200, uploadResponse(id: expectedID, status: "pending")),
            .json(200, uploadResponse(id: otherID, status: "uploaded"))
        ])

        do {
            _ = try await NotionAPIClient(accessToken: "token", transport: mismatch).uploadFile(
                data: Data("content".utf8),
                filename: "document.pdf",
                contentType: "application/pdf"
            )
            XCTFail("Expected a mismatched upload response to fail")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, .invalidResponse)
        }
    }

    func testProductionTransportReceivesMultipartBodyAsAProtectedFile() async throws {
        let uploadID = "55555555-5555-5555-5555-555555555555"
        let payload = Data(repeating: 0x5A, count: 2 * 1_024 * 1_024)
        let transport = StreamingFileUploadTransport(uploadID: uploadID)
        let client = NotionAPIClient(accessToken: "token", transport: transport)

        _ = try await client.uploadFile(
            data: payload,
            filename: "notebook.notenerds.json",
            contentType: "application/json"
        )
        let streamed = await transport.streamedBodies

        XCTAssertEqual(streamed.count, 1)
        XCTAssertNil(streamed[0].requestBody)
        XCTAssertNotNil(streamed[0].fileBody.range(of: payload))
        XCTAssertEqual(streamed[0].fileMode, 0o600)
    }

    private func assertUploadError(
        client: NotionAPIClient,
        data: Data,
        filename: String,
        contentType: String,
        expected: NotionAPIError
    ) async {
        do {
            _ = try await client.uploadFile(data: data, filename: filename, contentType: contentType)
            XCTFail("Expected upload validation to fail")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, expected)
        }
    }

    private func assertMultipart(
        _ request: URLRequest,
        filename: String,
        contentType: String,
        payload: Data,
        partNumber: Int?
    ) throws {
        try assertMultipart(
            request,
            filename: filename,
            contentType: contentType,
            payloadSize: payload.count,
            partNumber: partNumber
        )
        XCTAssertNotNil(try XCTUnwrap(request.httpBody).range(of: payload))
    }

    private func assertMultipart(
        _ request: URLRequest,
        filename: String,
        contentType: String,
        payloadSize: Int,
        partNumber: Int?
    ) throws {
        let contentTypeHeader = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try XCTUnwrap(contentTypeHeader.split(separator: "boundary=").last.map(String.init))
        let body = try XCTUnwrap(request.httpBody)
        let text = String(decoding: body, as: Unicode.UTF8.self)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2026-03-11")
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"\(filename)\""))
        XCTAssertTrue(text.contains("Content-Type: \(contentType)"))
        XCTAssertTrue(text.hasSuffix("--\(boundary)--\r\n"))
        if let partNumber {
            XCTAssertTrue(text.contains("name=\"part_number\"\r\n\r\n\(partNumber)\r\n"))
        } else {
            XCTAssertFalse(text.contains("name=\"part_number\""))
        }
        let envelopeSize = body.count - payloadSize
        XCTAssertGreaterThan(envelopeSize, 0)
        XCTAssertLessThan(envelopeSize, 2_048)
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func uploadResponse(id: String, status: String) -> String {
        #"{"object":"file_upload","id":"\#(id)","status":"\#(status)"}"#
    }

    private func botResponse(maximumFileByteCount: Int) -> String {
        """
        {"object":"user","type":"bot","bot":{"workspace_limits":{
        "max_file_upload_size_in_bytes":\(maximumFileByteCount)}}}
        """
    }
}

private actor StreamingFileUploadTransport: NotionHTTPTransport {
    struct StreamedBody: Sendable {
        let requestBody: Data?
        let fileBody: Data
        let fileMode: Int
    }

    private let uploadID: String
    private(set) var streamedBodies: [StreamedBody] = []

    init(uploadID: String) { self.uploadID = uploadID }

    func data(for request: URLRequest) -> (Data, HTTPURLResponse) {
        if request.url?.path == "/v1/users/me" {
            let body = """
            {"object":"user","type":"bot","bot":{"workspace_limits":{
            "max_file_upload_size_in_bytes":5242880}}}
            """
            return response(
                request: request,
                body: Data(body.utf8)
            )
        }
        return response(
            request: request,
            body: Data(#"{"object":"file_upload","id":"\#(uploadID)","status":"pending"}"#.utf8)
        )
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) throws -> (Data, HTTPURLResponse) {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        streamedBodies.append(StreamedBody(
            requestBody: request.httpBody,
            fileBody: try Data(contentsOf: fileURL),
            fileMode: (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        ))
        return response(
            request: request,
            body: Data(#"{"object":"file_upload","id":"\#(uploadID)","status":"uploaded"}"#.utf8)
        )
    }

    private func response(request: URLRequest, body: Data) -> (Data, HTTPURLResponse) {
        (
            body,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
    }
}

private actor FileUploadTransport: NotionHTTPTransport {
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
