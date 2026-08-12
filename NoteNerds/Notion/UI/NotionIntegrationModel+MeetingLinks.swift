import Foundation

extension NotionIntegrationModel {
    func openNotebook(_ notebookID: NotebookID, library: LibraryState) {
        meetingLinkTask?.cancel()
        meetingLinkTask = nil
        meetingNotebookID = notebookID
        meetingLibrary = library
        meetingChoices = []
        dismissedMeetingIDs = []
        startMeetingLinkTask(publishFirst: false)
    }

    func updateOpenNotebookLibrary(_ library: LibraryState) {
        meetingLibrary = library
    }

    func closeNotebookMeetingLinks() {
        meetingLinkTask?.cancel()
        meetingLinkTask = nil
        meetingNotebookID = nil
        meetingLibrary = nil
        meetingChoices = []
        dismissedMeetingIDs = []
    }

    func pauseMeetingLinks() {
        meetingLinkTask?.cancel()
        meetingLinkTask = nil
    }

    func resumeMeetingLinks() {
        startMeetingLinkTask(publishFirst: false)
    }

    func chooseMeeting(_ meeting: NotionMeetingNote) {
        guard let coordinator = meetingLinkCoordinator,
              let notebookID = meetingNotebookID else { return }
        meetingChoices = []
        dismissedMeetingIDs = []
        Task { [weak self] in
            let result = try? await coordinator.link(
                meetingID: meeting.id,
                notebookID: notebookID.rawValue.uuidString.lowercased()
            )
            if let result { self?.applyMeetingLinkResult(result) }
        }
    }

    func dismissMeetingChoices() {
        dismissedMeetingIDs.formUnion(meetingChoices.map(\.id))
        meetingChoices = []
    }

    private func startMeetingLinkTask(publishFirst: Bool) {
        guard meetingLinkTask == nil,
              meetingLinkCoordinator != nil,
              destination != nil,
              meetingNotebookID != nil,
              meetingLibrary != nil else { return }
        meetingLinkTask = Task { [weak self] in
            await self?.runMeetingLinkChecks(publishFirst: publishFirst)
        }
    }

    private func runMeetingLinkChecks(publishFirst: Bool) async {
        guard let coordinator = meetingLinkCoordinator,
              let notebookID = meetingNotebookID,
              let library = meetingLibrary else {
            meetingLinkTask = nil
            return
        }
        if publishFirst {
            await sync(library, notebookID: notebookID)
            guard !Task.isCancelled else { return }
        }
        let identifier = notebookID.rawValue.uuidString.lowercased()
        while !Task.isCancelled, meetingNotebookID == notebookID {
            do {
                let result = try await coordinator.check(notebookID: identifier)
                applyMeetingLinkResult(result)
                let delay: Duration = switch result {
                case .linked, .alreadyLinked, .removedByUser: .seconds(120)
                default: meetingPollInterval
                }
                try await Task.sleep(for: delay)
            } catch is CancellationError {
                break
            } catch {
                meetingLinkMessage = "The active Notion meeting could not be checked."
                try? await Task.sleep(for: meetingPollInterval)
            }
        }
        if meetingNotebookID == notebookID { meetingLinkTask = nil }
    }

    func applyMeetingLinkResult(_ result: NotionMeetingLinkResult) {
        switch result {
        case .linked:
            meetingChoices = []
            isMeetingLinkPermissionRequired = false
            meetingLinkMessage = "Linked to the active Notion meeting note."
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.meetingLinkMessage = nil
            }
        case let .needsSelection(meetings):
            meetingChoices = meetings.filter { !dismissedMeetingIDs.contains($0.id) }
            isMeetingLinkPermissionRequired = false
        case .permissionRequired:
            meetingChoices = []
            isMeetingLinkPermissionRequired = true
            meetingLinkMessage = nil
        case .noActiveMeeting, .noNotebookBinding, .alreadyLinked, .removedByUser, .unavailable:
            meetingChoices = []
        }
    }
}
