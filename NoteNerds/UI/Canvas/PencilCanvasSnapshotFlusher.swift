import Combine
import Foundation

@MainActor
final class PencilCanvasSnapshotFlusher: ObservableObject {
    typealias RegistrationID = UUID
    typealias Flush = @MainActor () async -> Void

    private var flushes: [RegistrationID: Flush] = [:]

    func attach(id: RegistrationID, flush: @escaping Flush) {
        flushes[id] = flush
    }

    func detach(id: RegistrationID) {
        flushes[id] = nil
    }

    func flushPendingSnapshots() async {
        let pendingFlushes = Array(flushes.values)
        for flush in pendingFlushes {
            await flush()
        }
    }
}
