import Foundation

extension NotionIntegrationModel {
    func prepareRestore(local: LibraryState) async -> [NotionRestoreCandidate] {
        guard destination != nil, let restorer else { return [] }
        state = .preparingRestore
        failureMessage = nil
        do {
            restoreCandidates = try await restorer.prepare(local: local)
            state = .reviewingRestore
            return restoreCandidates
        } catch {
            showFailure("Your Notion notebooks could not be prepared for restore.")
            return []
        }
    }

    func completeRestore(
        local: LibraryState,
        choices: [NotebookID: NotionRestoreChoice]
    ) -> LibraryState? {
        guard let restorer else { return nil }
        state = .restoring
        do {
            let restored = try restorer.complete(
                local: local,
                choices: choices
            )
            restoreCandidates = []
            if let connection {
                state = .connected(workspaceName: connection.credentials.workspaceName)
            }
            return restored
        } catch {
            showFailure("The selected notebooks could not be restored.")
            return nil
        }
    }
}
