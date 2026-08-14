import Foundation

extension AppModel {
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
            let persistenceOutcomeTask = documentStore == nil
                ? libraryPersistenceOutcomeTask
                : documentPersistenceOutcomeTask
            submitForSync(using: syncEngine) { engine in
                let wasAppliedLocally = await persistenceOutcomeTask?.value ?? false
                await engine.enqueue(change, wasAppliedLocally: wasAppliedLocally)
            }
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
            submitForSync(using: syncEngine) {
                await $0.enqueue(change, wasAppliedLocally: false)
            }
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
        guard activePencilCanvasIDs.isEmpty else {
            isSyncDeferredForPencilContact = true
            return
        }
        await engine.synchronize()
        guard activePencilCanvasIDs.isEmpty else {
            isSyncDeferredForPencilContact = true
            return
        }
        let changes = await engine.receivedChangesSnapshot()
        let locallyAppliedChangeIDs = await engine.locallyAppliedChangeIDsSnapshot()
        let decodedChanges = await Self.decodeRemoteChanges(changes)
        let outcome = applyRemoteChanges(
            decodedChanges,
            locallyAppliedChangeIDs: locallyAppliedChangeIDs
        )
        var acknowledgedIDs = outcome.immediateAcknowledgements
        if !outcome.localEchoesAwaitingPersistence.isEmpty {
            // Awaiting the task that happens to be current is not enough: a save
            // scheduled while we were suspended would leave the echo
            // acknowledged before its own document reached disk.
            await waitForDocumentPersistenceToFinish()
            await libraryPersistenceTask?.value
            if didPersistDocuments, didPersistLibrary {
                acknowledgedIDs.formUnion(outcome.localEchoesAwaitingPersistence)
            }
        }
        if !outcome.changesAwaitingPersistence.isEmpty {
            let savedDocumentChanges = await persistRemoteDocuments(
                outcome.documentChangesByNotebook
            )
            persistLibrary()
            await libraryPersistenceTask?.value
            if didPersistLibrary {
                let savedChanges = outcome.changesAwaitingPersistence
                    .subtracting(outcome.notebookChangeIDs)
                    .union(savedDocumentChanges)
                acknowledgedIDs.formUnion(savedChanges)
                remoteChangeIDsAwaitingPersistence.subtract(savedChanges)
                for changeID in savedChanges {
                    remoteNotebookIDsAwaitingPersistence[changeID] = nil
                }
            }
        }
        if !acknowledgedIDs.isEmpty {
            let didPersistAcknowledgement = await engine.acknowledgeReceivedChanges(acknowledgedIDs)
            if didPersistAcknowledgement {
                seenSyncChangeIDs.subtract(acknowledgedIDs)
                await pruneRemoteChangeReceipts(acknowledgedIDs)
            }
        }
        await updateSyncIssue(from: engine)
    }

    private func updateSyncIssue(from engine: SyncEngine) async {
        let state = await engine.state
        let failure = await engine.lastFailure
        syncIssue = state == .idle ? nil : failure?.userMessage
    }

    private func pruneRemoteChangeReceipts(_ acknowledgedIDs: Set<ChangeID>) async {
        let affectedNotebookIDs = appliedRemoteChangeIDsByNotebook.keys.filter { notebookID in
            !appliedRemoteChangeIDsByNotebook[notebookID, default: []]
                .isDisjoint(with: acknowledgedIDs)
        }
        guard !affectedNotebookIDs.isEmpty else { return }
        for notebookID in affectedNotebookIDs {
            appliedRemoteChangeIDsByNotebook[notebookID]?.subtract(acknowledgedIDs)
            if appliedRemoteChangeIDsByNotebook[notebookID]?.isEmpty == true {
                appliedRemoteChangeIDsByNotebook[notebookID] = nil
            }
        }
        if !activePencilCanvasIDs.isEmpty {
            for notebookID in affectedNotebookIDs {
                scheduleDeferredCheckpoint(for: notebookID)
            }
            return
        }
        guard let documentStore else { return }
        let checkpoints = affectedNotebookIDs.compactMap { notebookID in
            library.notebook(id: notebookID).map(nativePackage(for:))
        }
        let precedingTask = documentPersistenceTask
        let persistenceTask = Task {
            await precedingTask?.value
            for checkpoint in checkpoints {
                do {
                    try await documentStore.save(checkpoint)
                    journalCounts[checkpoint.notebook.id] = 0
                } catch {
                    presentedError = "Sync history cleanup could not be saved. \(error.localizedDescription)"
                }
            }
        }
        setDocumentPersistenceTail(persistenceTask)
        await persistenceTask.value
    }

    /// Reads every incoming payload once, away from the main thread.
    ///
    /// A batch of remote strokes holds every sample of every gesture, and the
    /// main thread used to decode each one several times over while the canvas
    /// waited. That is what the watchdog was killing the app for.
    nonisolated private static func decodeRemoteChanges(
        _ changes: [DocumentChange]
    ) async -> [DecodedRemoteChange] {
        guard !changes.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            changes.map {
                DecodedRemoteChange(change: $0, payload: try? SyncChangeEncoder.decodePayload($0))
            }
        }.value
    }

    private func applyRemoteChanges(
        _ decodedChanges: [DecodedRemoteChange],
        locallyAppliedChangeIDs: Set<ChangeID>
    ) -> RemoteChangeApplicationOutcome {
        var outcome = RemoteChangeApplicationOutcome()
        var deferredChanges: [DecodedRemoteChange] = []
        for decoded in decodedChanges {
            let change = decoded.change
            let isDocumentAction = decoded.documentAction != nil
            let isDurableLocalDocumentEcho = isDocumentAction
                && locallyAppliedChangeIDs.contains(change.id)
            if isDurableLocalDocumentEcho || (!isDocumentAction && seenSyncChangeIDs.contains(change.id)) {
                outcome.localEchoesAwaitingPersistence.insert(change.id)
            } else if isDocumentAction && seenSyncChangeIDs.contains(change.id) {
                continue
            } else if remoteChangeIDsAwaitingPersistence.contains(change.id) {
                outcome.requirePersistence(
                    changeID: change.id,
                    notebookIDs: remoteNotebookIDsAwaitingPersistence[change.id, default: []]
                )
            } else {
                deferredChanges.append(decoded)
            }
        }
        var madeProgress = true
        while madeProgress, !deferredChanges.isEmpty {
            madeProgress = false
            deferredChanges = deferredChanges.filter { decoded in
                let changeID = decoded.change.id
                switch applyRemoteChange(decoded) {
                case let .applied(notebookIDs):
                    madeProgress = true
                    remoteChangeIDsAwaitingPersistence.insert(changeID)
                    remoteNotebookIDsAwaitingPersistence[changeID] = notebookIDs
                    outcome.requirePersistence(changeID: changeID, notebookIDs: notebookIDs)
                    return false
                case .alreadyApplied:
                    madeProgress = true
                    outcome.immediateAcknowledgements.insert(changeID)
                    return false
                case .discarded:
                    outcome.immediateAcknowledgements.insert(changeID)
                    return false
                case .deferred:
                    return true
                }
            }
        }
        leaveInactiveCurrentFolder()
        return outcome
    }

    private func persistRemoteDocuments(
        _ changesByNotebook: [NotebookID: Set<ChangeID>]
    ) async -> Set<ChangeID> {
        let allChangeIDs = changesByNotebook.values.reduce(into: Set<ChangeID>()) {
            $0.formUnion($1)
        }
        guard let documentStore, !allChangeIDs.isEmpty else { return allChangeIDs }
        guard activePencilCanvasIDs.isEmpty else {
            isSyncDeferredForPencilContact = true
            return []
        }
        var failedChangeIDs = Set<ChangeID>()
        let checkpoints: [RemoteDocumentCheckpoint] = changesByNotebook.compactMap { notebookID, changeIDs in
            guard let notebook = library.notebook(id: notebookID) else { return nil }
            return RemoteDocumentCheckpoint(package: nativePackage(for: notebook), changeIDs: changeIDs)
        }
        let precedingTask = documentPersistenceTask
        let persistenceTask = Task { () -> Set<ChangeID> in
            await precedingTask?.value
            var didSaveEveryDocument = true
            for checkpoint in checkpoints {
                do {
                    try await documentStore.save(checkpoint.package)
                    journalCounts[checkpoint.package.notebook.id] = 0
                } catch {
                    didSaveEveryDocument = false
                    failedChangeIDs.formUnion(checkpoint.changeIDs)
                    presentedError = "Your latest change could not be saved. \(error.localizedDescription)"
                }
            }
            didPersistDocuments = didSaveEveryDocument
            return allChangeIDs.subtracting(failedChangeIDs)
        }
        setDocumentPersistenceTail(Task { _ = await persistenceTask.value })
        return await persistenceTask.value
    }

    private func applyRemoteChange(_ decoded: DecodedRemoteChange) -> RemoteChangeDisposition {
        let change = decoded.change
        if let mutation = decoded.libraryMutation {
            if let disposition = missingNotebookDisposition(for: mutation) {
                return disposition
            }
            let notebooksBeforeMutation = notebooksByID(library.notebooks)
            guard (try? mutation.apply(to: &library)) != nil else { return .deferred }
            let changedNotebookIDs = notebookIDsChanged(from: notebooksBeforeMutation)
            updateSearchIndex(after: mutation)
            return .applied(changedNotebookIDs)
        }
        guard let action = decoded.documentAction else {
            return .discarded
        }
        guard var notebook = library.notebook(id: change.notebookID) else {
            return library.isPermanentlyDeleted(change.notebookID) ? .discarded : .deferred
        }
        if appliedRemoteChangeIDsByNotebook[notebook.id, default: []].contains(change.id) {
            return .alreadyApplied
        }
        guard (try? action.perform(on: &notebook)) != nil else { return .deferred }
        appliedRemoteChangeIDsByNotebook[notebook.id, default: []].insert(change.id)
        let handwritingCanvasID = cancelHandwritingRecognition(after: action.operation)
        notebook.modifiedAt = max(notebook.modifiedAt, change.timestamp)
        library.updateNotebook(notebook)
        if let handwritingCanvasID {
            finishHandwritingChange(after: action.operation, canvasID: handwritingCanvasID, in: notebook)
        } else {
            searchIndex.update(notebook)
        }
        fetchMissingAssets(in: notebook)
        return .applied([notebook.id])
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
            restoreHandwritingSearch()
            return
        }
        guard let notebook = library.notebook(id: notebookID) else {
            searchIndex.remove(notebookID: notebookID)
            return
        }
        refreshHandwritingSearch(in: notebook.id)
        fetchMissingAssets(in: notebook)
    }

    private func notebookIDsChanged(
        from previousNotebooks: [NotebookID: Notebook]
    ) -> Set<NotebookID> {
        let currentNotebooks = notebooksByID(library.notebooks)
        let allNotebookIDs = Set(previousNotebooks.keys).union(currentNotebooks.keys)
        return Set(allNotebookIDs.filter {
            previousNotebooks[$0] != currentNotebooks[$0]
        })
    }

    private func notebooksByID(_ notebooks: [Notebook]) -> [NotebookID: Notebook] {
        var result: [NotebookID: Notebook] = [:]
        for notebook in notebooks {
            result[notebook.id] = notebook
        }
        return result
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

/// A change paired with the payload it was found to hold.
///
/// `nil` means the bytes were unreadable, which is how a change earns being
/// discarded rather than retried.
private struct DecodedRemoteChange: Sendable {
    let change: DocumentChange
    let payload: SyncChangePayload?

    var documentAction: SyncedDocumentAction? { payload?.documentAction }
    var libraryMutation: LibrarySyncMutation? { payload?.libraryMutation }
}

private struct RemoteChangeApplicationOutcome {
    var immediateAcknowledgements: Set<ChangeID> = []
    var localEchoesAwaitingPersistence: Set<ChangeID> = []
    var changesAwaitingPersistence: Set<ChangeID> = []
    var documentChangesByNotebook: [NotebookID: Set<ChangeID>] = [:]

    var notebookChangeIDs: Set<ChangeID> {
        documentChangesByNotebook.values.reduce(into: Set<ChangeID>()) {
            $0.formUnion($1)
        }
    }

    mutating func requirePersistence(changeID: ChangeID, notebookIDs: Set<NotebookID>) {
        changesAwaitingPersistence.insert(changeID)
        for notebookID in notebookIDs {
            documentChangesByNotebook[notebookID, default: []].insert(changeID)
        }
    }
}

private struct RemoteDocumentCheckpoint {
    let package: NativeNotebookPackage
    let changeIDs: Set<ChangeID>
}

private enum RemoteChangeDisposition {
    case applied(Set<NotebookID>)
    case alreadyApplied
    case deferred
    case discarded
}
