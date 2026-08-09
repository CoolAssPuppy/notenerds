import Foundation

enum NotionMeetingStatus: String, Codable, Equatable, Sendable {
    case transcriptionNotStarted = "transcription_not_started"
    case transcriptionInProgress = "transcription_in_progress"
    case transcriptionPaused = "transcription_paused"
    case summaryInProgress = "summary_in_progress"
    case notesReady = "notes_ready"
}

struct NotionMeetingNote: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let parentBlockID: String
    let title: String
    let status: NotionMeetingStatus
    let lastEditedAt: Date
    let recordingStartedAt: Date?
}

struct NotionNotebookLinkBlock: Equatable, Sendable {
    let id: String
    let pageID: String
}

protocol NotionMeetingLinkAPI: Sendable {
    func queryMeetingNotes() async throws -> [NotionMeetingNote]
    func listNotebookLinks(parentBlockID: String) async throws -> [NotionNotebookLinkBlock]
    func insertNotebookLink(
        parentBlockID: String,
        afterBlockID: String,
        notebookPageID: String
    ) async throws -> String
    func trashMeetingLink(blockID: String) async throws
}

extension NotionAPIClient: NotionMeetingLinkAPI {
    func queryMeetingNotes() async throws -> [NotionMeetingNote] {
        let body: NotionJSONValue = .object([
            "sort": .array([.object([
                "property": .string("created_time"),
                "direction": .string("descending")
            ])]),
            "limit": .number(10)
        ])
        let request = try makeRequest(
            path: "blocks/meeting_notes/query",
            method: "POST",
            body: body
        )
        let response = try decoder.decode(
            MeetingQueryResponse.self,
            from: try await send(request)
        )
        var meetings: [NotionMeetingNote] = []
        for result in response.results {
            let parentID: String
            if let includedParentID = result.parent?.identifier {
                parentID = includedParentID
            } else {
                parentID = try await retrieveParentBlockID(meetingID: result.id)
            }
            if let meeting = result.meeting(parentBlockID: parentID) {
                meetings.append(meeting)
            }
        }
        return meetings
    }

    func listNotebookLinks(parentBlockID: String) async throws -> [NotionNotebookLinkBlock] {
        try Self.validateMeetingIdentifier(parentBlockID)
        var links: [NotionNotebookLinkBlock] = []
        var cursor: String?
        repeat {
            var query = [URLQueryItem(name: "page_size", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "start_cursor", value: cursor)) }
            let request = try makeRequest(
                path: "blocks/\(parentBlockID)/children",
                method: "GET",
                queryItems: query
            )
            let response = try decoder.decode(
                MeetingChildrenResponse.self,
                from: try await send(request)
            )
            links.append(contentsOf: response.results.compactMap(\.notebookLink))
            cursor = response.hasMore ? response.nextCursor : nil
            if response.hasMore, cursor == nil { throw NotionAPIError.invalidResponse }
        } while cursor != nil
        return links
    }

    func insertNotebookLink(
        parentBlockID: String,
        afterBlockID: String,
        notebookPageID: String
    ) async throws -> String {
        try Self.validateMeetingIdentifier(parentBlockID)
        try Self.validateMeetingIdentifier(afterBlockID)
        try Self.validateMeetingIdentifier(notebookPageID)
        let body: NotionJSONValue = .object([
            "children": .array([.object([
                "object": .string("block"),
                "type": .string("link_to_page"),
                "link_to_page": .object([
                    "type": .string("page_id"),
                    "page_id": .string(notebookPageID)
                ])
            ])]),
            "position": .object([
                "type": .string("after_block"),
                "after_block": .object(["id": .string(afterBlockID)])
            ])
        ])
        let request = try makeRequest(
            path: "blocks/\(parentBlockID)/children",
            method: "PATCH",
            body: body
        )
        let response = try decoder.decode(
            MeetingInsertResponse.self,
            from: try await send(request)
        )
        guard let id = response.results.first?.id, UUID(uuidString: id) != nil else {
            throw NotionAPIError.invalidResponse
        }
        return id
    }

    func trashMeetingLink(blockID: String) async throws {
        try Self.validateMeetingIdentifier(blockID)
        let request = baseRequest(path: "blocks/\(blockID)", method: "DELETE")
        _ = try await send(request)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func validateMeetingIdentifier(_ id: String) throws {
        guard UUID(uuidString: id) != nil else { throw NotionAPIError.invalidIdentifier }
    }

    private func retrieveParentBlockID(meetingID: String) async throws -> String {
        try Self.validateMeetingIdentifier(meetingID)
        let request = baseRequest(path: "blocks/\(meetingID)", method: "GET")
        let response = try decoder.decode(
            MeetingParentResponse.self,
            from: try await send(request)
        )
        guard let identifier = response.parent.identifier else {
            throw NotionAPIError.invalidResponse
        }
        return identifier
    }
}

private struct MeetingQueryResponse: Decodable {
    let results: [MeetingResult]
}

private struct MeetingResult: Decodable {
    let id: String
    let parent: MeetingParent?
    let lastEditedAt: Date
    let details: MeetingDetails

    private enum CodingKeys: String, CodingKey {
        case id
        case parent
        case lastEditedAt = "last_edited_time"
        case details = "meeting_notes"
    }

    func meeting(parentBlockID: String) -> NotionMeetingNote? {
        guard UUID(uuidString: id) != nil else { return nil }
        return NotionMeetingNote(
            id: id,
            parentBlockID: parentBlockID,
            title: details.title.map(\.plainText).joined(),
            status: details.status,
            lastEditedAt: lastEditedAt,
            recordingStartedAt: details.recording?.startTime
        )
    }
}

private struct MeetingParent: Decodable {
    let type: String
    let pageID: String?
    let blockID: String?
    let databaseID: String?
    let dataSourceID: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case pageID = "page_id"
        case blockID = "block_id"
        case databaseID = "database_id"
        case dataSourceID = "data_source_id"
    }

    var identifier: String? {
        switch type {
        case "page_id": pageID
        case "block_id": blockID
        case "database_id": databaseID
        case "data_source_id": dataSourceID
        default: nil
        }
    }
}

private struct MeetingParentResponse: Decodable {
    let parent: MeetingParent
}

private struct MeetingDetails: Decodable {
    let title: [MeetingRichText]
    let status: NotionMeetingStatus
    let recording: MeetingRecording?
}

private struct MeetingRichText: Decodable {
    let plainText: String

    private enum CodingKeys: String, CodingKey { case plainText = "plain_text" }
}

private struct MeetingRecording: Decodable {
    let startTime: Date?

    private enum CodingKeys: String, CodingKey { case startTime = "start_time" }
}

private struct MeetingChildrenResponse: Decodable {
    let results: [MeetingChild]
    let hasMore: Bool
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

private struct MeetingChild: Decodable {
    let id: String
    let type: String?
    let link: MeetingPageLink?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case link = "link_to_page"
    }

    var notebookLink: NotionNotebookLinkBlock? {
        guard type == "link_to_page", let pageID = link?.pageID else { return nil }
        return NotionNotebookLinkBlock(id: id, pageID: pageID)
    }
}

private struct MeetingPageLink: Decodable {
    let pageID: String?

    private enum CodingKeys: String, CodingKey { case pageID = "page_id" }
}

private struct MeetingInsertResponse: Decodable {
    let results: [MeetingInsertedBlock]
}

private struct MeetingInsertedBlock: Decodable {
    let id: String
}
