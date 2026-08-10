import Foundation

extension AppModel {
    func enqueueForSync(_ operation: DocumentOperation, notebookID: NotebookID) {
        enqueueForSync(SyncedDocumentAction(operation: operation, direction: .apply), notebookID: notebookID)
    }

    func enqueueForSync(_ action: SyncedDocumentAction, notebookID: NotebookID) {
        guard let syncEngine else { return }
        syncSequence = nextSyncSequence()
        do {
            let change = try syncChangeEncoder.change(
                for: action,
                notebookID: notebookID,
                sequence: syncSequence
            )
            seenSyncChangeIDs.insert(change.id)
            submitForSync(using: syncEngine) { await $0.enqueue(change) }
        } catch {
            syncIssue = "This change is saved locally and is waiting for iCloud sync."
        }
    }

    func enqueueForSync(_ mutation: LibrarySyncMutation, notebookID: NotebookID) {
        guard let syncEngine else { return }
        syncSequence = nextSyncSequence()
        do {
            let change = try syncChangeEncoder.change(
                for: mutation,
                notebookID: notebookID,
                sequence: syncSequence
            )
            seenSyncChangeIDs.insert(change.id)
            submitForSync(using: syncEngine) { await $0.enqueue(change) }
        } catch {
            syncIssue = "This change is saved locally and is waiting for iCloud sync."
        }
    }

    func enqueueAssetForSync(_ asset: DocumentAsset) {
        guard let syncEngine else { return }
        submitForSync(using: syncEngine) { await $0.enqueue(asset) }
    }

    private func submitForSync(
        using engine: SyncEngine,
        enqueue: @escaping @Sendable (SyncEngine) async -> Void
    ) {
        let previous = syncSubmissionTask
        let enqueueTask = Task {
            await previous?.value
            await enqueue(engine)
        }
        syncSubmissionTask = enqueueTask
        Task { [weak self] in
            await enqueueTask.value
            guard let self else { return }
            await self.synchronize(using: engine)
        }
    }

    func synchronize(using engine: SyncEngine? = nil) async {
        guard let engine = engine ?? syncEngine else { return }
        await engine.synchronize()
        let state = await engine.state
        let failure = await engine.lastFailure
        let changes = await engine.receivedChangesSnapshot()
        let outcome = applyRemoteChanges(changes)
        var acknowledgedIDs = outcome.immediateAcknowledgements
        if !outcome.localEchoesAwaitingPersistence.isEmpty {
            await documentPersistenceTask?.value
            await libraryPersistenceTask?.value
            if didPersistDocuments, didPersistLibrary {
                acknowledgedIDs.formUnion(outcome.localEchoesAwaitingPersistence)
            }
        }
        if !outcome.changesAwaitingPersistence.isEmpty {
            persistLibrary()
            await libraryPersistenceTask?.value
            if didPersistLibrary {
                acknowledgedIDs.formUnion(outcome.changesAwaitingPersistence)
                remoteChangeIDsAwaitingPersistence.subtract(outcome.changesAwaitingPersistence)
            }
        }
        if !acknowledgedIDs.isEmpty {
            await engine.acknowledgeReceivedChanges(acknowledgedIDs)
            seenSyncChangeIDs.subtract(acknowledgedIDs)
        }
        syncIssue = state == .idle ? nil : failure?.userMessage
    }

    private func applyRemoteChanges(_ changes: [DocumentChange]) -> RemoteChangeApplicationOutcome {
        var outcome = RemoteChangeApplicationOutcome()
        var deferredChanges: [DocumentChange] = []
        for change in changes {
            if seenSyncChangeIDs.contains(change.id) {
                outcome.localEchoesAwaitingPersistence.insert(change.id)
            } else if remoteChangeIDsAwaitingPersistence.contains(change.id) {
                outcome.changesAwaitingPersistence.insert(change.id)
            } else {
                deferredChanges.append(change)
            }
        }
        var madeProgress = true
        while madeProgress, !deferredChanges.isEmpty {
            madeProgress = false
            deferredChanges = deferredChanges.filter { change in
                switch applyRemoteChange(change) {
                case .applied:
                    madeProgress = true
                    remoteChangeIDsAwaitingPersistence.insert(change.id)
                    outcome.changesAwaitingPersistence.insert(change.id)
                    return false
                case .discarded:
                    outcome.immediateAcknowledgements.insert(change.id)
                    return false
                case .deferred:
                    return true
                }
            }
        }
        leaveInactiveCurrentFolder()
        return outcome
    }

    private func applyRemoteChange(_ change: DocumentChange) -> RemoteChangeDisposition {
        if let mutation = try? SyncChangeEncoder.decodeLibraryMutation(change) {
            if let disposition = missingNotebookDisposition(for: mutation) {
                return disposition
            }
            guard (try? mutation.apply(to: &library)) != nil else { return .deferred }
            updateSearchIndex(after: mutation)
            return .applied
        }
        guard let action = try? SyncChangeEncoder.decodeDocumentAction(change) else {
            return .discarded
        }
        guard var notebook = library.notebook(id: change.notebookID) else {
            return library.isPermanentlyDeleted(change.notebookID) ? .discarded : .deferred
        }
        guard (try? action.perform(on: &notebook)) != nil else { return .deferred }
        notebook.modifiedAt = max(notebook.modifiedAt, change.timestamp)
        library.updateNotebook(notebook)
        searchIndex.update(notebook)
        fetchMissingAssets(in: notebook)
        return .applied
    }

    private func missingNotebookDisposition(
        for mutation: LibrarySyncMutation
    ) -> RemoteChangeDisposition? {
        let notebookID: NotebookID?
        switch mutation {
        case let .updateNotebookMetadata(metadata): notebookID = metadata.id
        case let .restoreNotebook(id): notebookID = id
        default: notebookID = nil
        }
        guard let notebookID, library.notebook(id: notebookID) == nil else { return nil }
        return library.isPermanentlyDeleted(notebookID) ? .discarded : .deferred
    }

    private func updateSearchIndex(after mutation: LibrarySyncMutation) {
        guard let notebookID = mutation.affectedNotebookID else {
            searchIndex = LibrarySearchIndex()
            for notebook in library.notebooks { searchIndex.update(notebook) }
            return
        }
        guard let notebook = library.notebook(id: notebookID) else {
            searchIndex.remove(notebookID: notebookID)
            return
        }
        searchIndex.update(notebook)
        fetchMissingAssets(in: notebook)
    }

    private func fetchMissingAssets(in notebook: Notebook) {
        guard let syncEngine else { return }
        let identifiers = Set(notebook.canvases.flatMap(\.layers).flatMap(\.objects).compactMap { object in
            switch object {
            case let .image(image): image.assetID
            case let .pdf(pdf): pdf.assetID
            case .stroke, .shape, .text: nil
            }
        }).filter { library.asset(id: $0) == nil }
        for id in identifiers {
            Task {
                guard let data = try? await syncEngine.fetchAsset(id) else { return }
                library.storeAsset(DocumentAsset(id: id, data: data, contentType: "application/octet-stream"))
                persistLibrary()
            }
        }
    }

    private func nextSyncSequence() -> Int {
        max(syncSequence + 1, Int(Date().timeIntervalSince1970 * 1_000_000))
    }
}

private struct RemoteChangeApplicationOutcome {
    var immediateAcknowledgements: Set<ChangeID> = []
    var localEchoesAwaitingPersistence: Set<ChangeID> = []
    var changesAwaitingPersistence: Set<ChangeID> = []
}

private enum RemoteChangeDisposition {
    case applied
    case deferred
    case discarded
}
