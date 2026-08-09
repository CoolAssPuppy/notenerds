import Foundation

enum NotionMeetingLinkResult: Equatable, Sendable {
    case noActiveMeeting
    case noNotebookBinding
    case linked(meetingTitle: String)
    case alreadyLinked
    case removedByUser
    case needsSelection([NotionMeetingNote])
    case permissionRequired
    case unavailable
}

protocol NotionMeetingLinkCoordinating: Sendable {
    func check(notebookID: String) async throws -> NotionMeetingLinkResult
    func link(meetingID: String, notebookID: String) async throws -> NotionMeetingLinkResult
    func removeLinks(notebookID: String) async throws
}

actor NotionMeetingLinkCoordinator: NotionMeetingLinkCoordinating {
    private let api: any NotionMeetingLinkAPI
    private let registry: NotionSyncRegistry
    private let now: @Sendable () -> Date

    init(
        api: any NotionMeetingLinkAPI,
        registry: NotionSyncRegistry,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.api = api
        self.registry = registry
        self.now = now
    }

    func check(notebookID: String) async throws -> NotionMeetingLinkResult {
        do {
            let meetings = try await api.queryMeetingNotes().filter(isActive)
            guard !meetings.isEmpty else { return .noActiveMeeting }
            guard meetings.count == 1, let meeting = meetings.first else {
                return .needsSelection(meetings)
            }
            return try await link(meeting: meeting, notebookID: notebookID)
        } catch NotionAPIError.httpStatus(403) {
            return .permissionRequired
        } catch NotionAPIError.httpStatus(400) {
            return .unavailable
        }
    }

    func link(meetingID: String, notebookID: String) async throws -> NotionMeetingLinkResult {
        do {
            guard let meeting = try await api.queryMeetingNotes().first(where: {
                $0.id == meetingID && isActive($0)
            }) else { return .noActiveMeeting }
            return try await link(meeting: meeting, notebookID: notebookID)
        } catch NotionAPIError.httpStatus(403) {
            return .permissionRequired
        } catch NotionAPIError.httpStatus(400) {
            return .unavailable
        }
    }

    func removeLinks(notebookID: String) async throws {
        let links = try await registry.snapshot().meetingLinks.filter {
            $0.notebookID == notebookID
        }
        for link in links {
            do {
                try await api.trashMeetingLink(blockID: link.linkBlockID)
            } catch NotionAPIError.httpStatus(404) {
                // The link is already absent from Notion.
            }
        }
        try await registry.removeMeetingLinks(notebookID: notebookID)
    }

    private func link(
        meeting: NotionMeetingNote,
        notebookID: String
    ) async throws -> NotionMeetingLinkResult {
        let state = try await registry.snapshot()
        guard let binding = state.binding(notebookID: notebookID) else {
            return .noNotebookBinding
        }
        let saved = state.meetingLink(meetingBlockID: meeting.id, notebookID: notebookID)
        if saved?.wasRemovedByUser == true { return .removedByUser }
        let remoteLinks = try await api.listNotebookLinks(parentBlockID: meeting.parentBlockID)
        if let remote = remoteLinks.first(where: { $0.pageID == binding.pageID }) {
            if saved == nil {
                try await record(
                    meeting: meeting,
                    notebookID: notebookID,
                    pageID: binding.pageID,
                    linkBlockID: remote.id
                )
            }
            return .alreadyLinked
        }
        if saved != nil {
            try await registry.markMeetingLinkRemoved(
                meetingBlockID: meeting.id,
                notebookID: notebookID
            )
            return .removedByUser
        }
        let linkID = try await api.insertNotebookLink(
            parentBlockID: meeting.parentBlockID,
            afterBlockID: meeting.id,
            notebookPageID: binding.pageID
        )
        try await record(
            meeting: meeting,
            notebookID: notebookID,
            pageID: binding.pageID,
            linkBlockID: linkID
        )
        return .linked(meetingTitle: meeting.title)
    }

    private func record(
        meeting: NotionMeetingNote,
        notebookID: String,
        pageID: String,
        linkBlockID: String
    ) async throws {
        try await registry.recordMeetingLink(NotionMeetingNotebookLink(
            meetingBlockID: meeting.id,
            notebookID: notebookID,
            notebookPageID: pageID,
            linkBlockID: linkBlockID,
            createdAt: now(),
            wasRemovedByUser: false
        ))
    }

    private func isActive(_ meeting: NotionMeetingNote) -> Bool {
        switch meeting.status {
        case .transcriptionInProgress:
            true
        case .transcriptionPaused:
            now().timeIntervalSince(meeting.lastEditedAt) <= 300
        case .transcriptionNotStarted, .summaryInProgress, .notesReady:
            false
        }
    }
}
