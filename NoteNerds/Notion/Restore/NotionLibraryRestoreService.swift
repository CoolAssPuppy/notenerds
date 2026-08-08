import Foundation

enum NotionRestoreCandidateReason: Equatable, Sendable {
    case missingLocally
    case newerInNotion
    case sameOrOlderInNotion
}

struct NotionRestoreCandidate: Identifiable, Equatable, Sendable {
    let notebookID: NotebookID
    let title: String
    let remoteModifiedAt: Date
    let reason: NotionRestoreCandidateReason

    var id: NotebookID { notebookID }
    var isSelectedByDefault: Bool { reason != .sameOrOlderInNotion }
    var defaultChoice: NotionRestoreChoice {
        switch reason {
        case .missingLocally, .newerInNotion: .useNotion
        case .sameOrOlderInNotion: .keepLocal
        }
    }
}

@MainActor
protocol NotionLibraryRestoring: AnyObject {
    func prepare(local: LibraryState) async throws -> [NotionRestoreCandidate]
    func complete(
        local: LibraryState,
        choices: [NotebookID: NotionRestoreChoice]
    ) throws -> LibraryState
}

@MainActor
final class NotionLibraryRestoreService: NotionLibraryRestoring {
    private let loader: any NotionRemoteLibraryLoading
    private let archive = NotionTransportArchive()
    private let coordinator = NotionRestoreCoordinator()
    private var pendingSnapshot: NotionRemoteLibrarySnapshot?

    init(loader: any NotionRemoteLibraryLoading) {
        self.loader = loader
    }

    func prepare(local: LibraryState) async throws -> [NotionRestoreCandidate] {
        let snapshot = try await loader.load()
        let candidates = try snapshot.archives.map { archiveData in
            let notebook = try archive.decode(archiveData).package.notebook
            return NotionRestoreCandidate(
                notebookID: notebook.id,
                title: notebook.title,
                remoteModifiedAt: notebook.modifiedAt,
                reason: Self.reason(remote: notebook, local: local.notebook(id: notebook.id))
            )
        }
        pendingSnapshot = snapshot
        return candidates
    }

    func complete(
        local: LibraryState,
        choices: [NotebookID: NotionRestoreChoice]
    ) throws -> LibraryState {
        guard let pendingSnapshot else { throw NotionOAuthError.noConnection }
        let restored = try coordinator.restore(
            pendingSnapshot,
            into: local,
            choices: choices
        )
        self.pendingSnapshot = nil
        return restored
    }

    private static func reason(remote: Notebook, local: Notebook?) -> NotionRestoreCandidateReason {
        guard let local else { return .missingLocally }
        return remote.modifiedAt > local.modifiedAt ? .newerInNotion : .sameOrOlderInNotion
    }
}
