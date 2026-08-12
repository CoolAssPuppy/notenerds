import Foundation

enum LibrarySection: String, CaseIterable, Identifiable {
    case files = "My Notebooks"
    case favorites = "Favorites"
    case recents = "Recents"
    case trash = "Trash"

    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var library = LibraryState()
    @Published var selectedSection = LibrarySection.files
    @Published var selectedNotebookID: NotebookID?
    @Published var currentFolderID: FolderID?
    @Published var searchQuery = ""
    @Published var presentedError: String?
    @Published var pendingSearchNavigation: LibrarySearchResult?
    @Published var syncIssue: String?
    @Published private(set) var hasRestoredLibrary = false

    let repository: any LibraryRepository
    let documentStore: LocalDocumentStore?
    let recognitionCoordinator: HandwritingRecognitionCoordinator
    var histories: [NotebookID: DocumentHistory] = [:]
    var recognitionTasks: [CanvasID: Task<Void, Never>] = [:]
    var pendingRecognitionBackfill: [NotebookID: Set<CanvasID>] = [:]
    var recognitionBackfillTask: Task<Void, Never>?
    var conversionTasks: [CanvasID: Task<Void, Never>] = [:]
    var pendingConversionStrokeIDs: [CanvasID: Set<StrokeID>] = [:]
    let conversionDelay: Duration
    let recognitionDelay: Duration
    let deferredCheckpointDelay: Duration
    var notebookIDsAwaitingCheckpoint: Set<NotebookID> = []
    var deferredCheckpointTask: Task<Void, Never>?
    var activePencilCanvasIDs: Set<CanvasID> = []
    var searchIndex = LibrarySearchIndex()
    let syncEngine: SyncEngine?
    let syncChangeEncoder: SyncChangeEncoder
    var syncSequence = 0
    var seenSyncChangeIDs: Set<ChangeID> = []
    var journalCounts: [NotebookID: Int] = [:]
    var libraryPersistenceTask: Task<Void, Never>?
    var libraryPersistenceOutcomeTask: Task<Bool, Never>?
    var didPersistLibrary = true
    var documentPersistenceTask: Task<Void, Never>?
    var documentPersistenceOutcomeTask: Task<Bool, Never>?
    var documentPersistenceRevision: UInt64 = 0
    var didPersistDocuments = true
    var syncSubmissionTask: Task<Void, Never>?
    var isSyncDeferredForPencilContact = false
    var remoteChangeIDsAwaitingPersistence: Set<ChangeID> = []
    var remoteNotebookIDsAwaitingPersistence: [ChangeID: Set<NotebookID>] = [:]
    var appliedRemoteChangeIDsByNotebook: [NotebookID: Set<ChangeID>] = [:]
    private var libraryRestoreTask: Task<Void, Never>?
    private var initialSyncTask: Task<Void, Never>?

    init(
        repository: any LibraryRepository = AppModel.defaultRepository(),
        documentStore: LocalDocumentStore? = nil,
        syncProvider: (any SyncProvider)? = nil,
        syncStateStore: (any SyncStateStore)? = nil,
        deviceID: String = UUID().uuidString,
        recognitionCoordinator: HandwritingRecognitionCoordinator = HandwritingRecognitionCoordinator(
            recognizer: AppleHandwritingRecognizer()
        ),
        conversionDelay: Duration = .milliseconds(700),
        recognitionDelay: Duration = .seconds(3),
        deferredCheckpointDelay: Duration = .seconds(4),
        automaticallyRestore: Bool = true
    ) {
        self.recognitionDelay = recognitionDelay
        self.deferredCheckpointDelay = deferredCheckpointDelay
        self.repository = repository
        self.documentStore = documentStore
        self.recognitionCoordinator = recognitionCoordinator
        self.conversionDelay = conversionDelay
        syncEngine = syncProvider.map { SyncEngine(provider: $0, stateStore: syncStateStore) }
        syncChangeEncoder = SyncChangeEncoder(deviceID: deviceID)
        if automaticallyRestore {
            libraryRestoreTask = Task { [weak self] in
                guard let self else { return }
                await performLibraryRestore()
            }
        }
    }

    var visibleNotebooks: [Notebook] {
        let base: [Notebook]
        switch selectedSection {
        case .files:
            let sortMode: LibrarySortMode = currentFolderID == nil ? .recentlyModified : library.preferredSortMode
            base = library.notebooks(in: currentFolderID, sortedBy: sortMode)
        case .favorites:
            base = library.notebooks(sortedBy: library.preferredSortMode).filter(\.isFavorite)
        case .recents:
            base = library.notebooks(sortedBy: .recentlyOpened)
        case .trash:
            base = library.notebooks.filter { $0.trashedAt != nil }.sorted { $0.modifiedAt > $1.modifiedAt }
        }
        let scoped = base
        guard !searchQuery.isEmpty else { return scoped }
        return scoped.filter { $0.matches(searchQuery) }
    }

    var visibleFolders: [Folder] {
        switch selectedSection {
        case .files:
            let active = library.folders(sortedBy: library.preferredSortMode).filter { $0.trashedAt == nil }
            return searchQuery.isEmpty
                ? active.filter { $0.parentID == currentFolderID }
                : active.filter {
                    $0.name.localizedCaseInsensitiveContains(searchQuery)
                        || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
                }
        case .favorites:
            return library.folders(sortedBy: library.preferredSortMode).filter {
                $0.isFavorite && $0.trashedAt == nil
            }
        case .recents:
            return []
        case .trash:
            return library.folders(sortedBy: .recentlyModified).filter { $0.trashedAt != nil }
        }
    }

    var searchResults: [LibrarySearchResult] {
        searchIndex.search(searchQuery)
    }

    func restoreLibrary() async {
        await restoreLocalLibrary()
        await initialSyncTask?.value
    }

    func restoreLocalLibrary() async {
        if let libraryRestoreTask {
            await libraryRestoreTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await performLibraryRestore()
        }
        libraryRestoreTask = task
        await task.value
    }

    private func performLibraryRestore() async {
        CanvasDiagnostics.mark("library restore began")
        defer {
            CanvasDiagnostics.mark("library restore finished notebooks=\(library.notebooks.count)")
            hasRestoredLibrary = true
        }
        do {
            library = try await repository.load()
            CanvasDiagnostics.mark("library index loaded notebooks=\(library.notebooks.count)")
            var didRepairLibrary = false
            if let documentStore {
                for notebook in library.notebooks {
                    do {
                        var recovered = try await documentStore.recover(notebookID: notebook.id)
                        CanvasDiagnostics.mark("recovered notebook")
                        appliedRemoteChangeIDsByNotebook[notebook.id] = recovered.appliedRemoteChangeIDs
                        recovered.notebook = notebook.restoringDocumentContent(from: recovered.notebook)
                        if recovered.notebook.repairDuplicateCanvasIdentifiers() {
                            try await documentStore.save(recovered)
                            didRepairLibrary = true
                        }
                        library.updateNotebook(recovered.notebook)
                    } catch LocalDocumentStoreError.notebookNotFound {
                        var repairedNotebook = notebook
                        didRepairLibrary = repairedNotebook.repairDuplicateCanvasIdentifiers() || didRepairLibrary
                        library.updateNotebook(repairedNotebook)
                        try await documentStore.save(
                            nativePackage(for: repairedNotebook)
                        )
                    }
                }
            } else {
                for notebook in library.notebooks {
                    var repairedNotebook = notebook
                    guard repairedNotebook.repairDuplicateCanvasIdentifiers() else { continue }
                    library.updateNotebook(repairedNotebook)
                    didRepairLibrary = true
                }
            }
            if didRepairLibrary {
                try await repository.save(library)
            }
            restoreHandwritingSearch()
            hasRestoredLibrary = true
            initialSyncTask = Task { [weak self] in
                await self?.synchronize()
            }
        } catch {
            presentedError = "Your local library could not be opened. \(error.localizedDescription)"
        }
    }

    func persistLibrary() {
        let snapshot = library
        let precedingTask = libraryPersistenceTask
        let outcomeTask = Task { () -> Bool in
            await precedingTask?.value
            do {
                try await repository.save(snapshot)
                didPersistLibrary = true
                return true
            } catch {
                didPersistLibrary = false
                presentedError = "Your latest change could not be saved. \(error.localizedDescription)"
                return false
            }
        }
        libraryPersistenceOutcomeTask = outcomeTask
        libraryPersistenceTask = Task { _ = await outcomeTask.value }
    }

    func execute(_ operation: DocumentOperation, on notebookID: NotebookID) {
        guard var notebook = library.notebook(id: notebookID) else { return }
        var history = histories[notebookID, default: DocumentHistory()]
        do {
            try history.execute(operation, on: &notebook)
            finishDocumentMutation(
                SyncedDocumentAction(operation: operation, direction: .apply),
                notebook: notebook,
                history: history
            )
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func finishDocumentMutation(
        _ action: SyncedDocumentAction,
        notebook: Notebook,
        history: DocumentHistory
    ) {
        var notebook = notebook
        let operation = action.operation
        let handwritingCanvasID = cancelHandwritingRecognition(after: operation)
        notebook.modifiedAt = Date()
        histories[notebook.id] = history
        library.updateNotebook(notebook)
        if let handwritingCanvasID {
            finishHandwritingChange(after: operation, canvasID: handwritingCanvasID, in: notebook)
        } else {
            updateSearchIndex(after: operation, in: notebook)
        }
        delayPendingCheckpoints()
        persist(action, notebook: notebook)
        enqueueForSync(action, notebookID: notebook.id)
    }

    func updateSearchIndex(after operation: DocumentOperation, in notebook: Notebook) {
        guard operation.requiresSearchIndexUpdate else { return }
        if let canvasID = operation.searchCanvasID {
            searchIndex.update(canvasID: canvasID, in: notebook)
        } else {
            searchIndex.update(notebook)
        }
    }

    func persist(_ action: SyncedDocumentAction, notebook: Notebook) {
        guard let documentStore else {
            persistLibrary()
            return
        }
        let notebookID = notebook.id
        let count = journalCounts[notebookID, default: 0] + 1
        journalCounts[notebookID] = count
        // Compacting the journal means writing the whole notebook, so it waits
        // for a pause in editing like every other snapshot. The journal already
        // holds these operations, so nothing is at risk while it waits.
        if count >= 20 {
            scheduleDeferredCheckpoint(for: notebookID)
        }
        let precedingTask = documentPersistenceTask
        let outcomeTask = Task { () -> Bool in
            await precedingTask?.value
            do {
                try await documentStore.append(action, notebookID: notebookID)
                didPersistDocuments = true
                return true
            } catch {
                didPersistDocuments = false
                presentedError = "Your latest change could not be saved. \(error.localizedDescription)"
                return false
            }
        }
        documentPersistenceOutcomeTask = outcomeTask
        setDocumentPersistenceTail(Task { _ = await outcomeTask.value })
    }

    /// Marks a notebook as needing a full snapshot without writing one now.
    ///
    /// Handwriting recognition is derived data, but writing it used to send a
    /// whole notebook to disk the moment recognition finished. On device that
    /// put 100–500ms file writes in the middle of live Pencil input, including
    /// for notebooks that were not even open. The write is coalesced and held
    /// until editing has been quiet, and flushed when the app backgrounds.
    func scheduleDeferredCheckpoint(for notebookID: NotebookID) {
        notebookIDsAwaitingCheckpoint.insert(notebookID)
        guard activePencilCanvasIDs.isEmpty else { return }
        restartDeferredCheckpointTimer()
    }

    /// Pushes any deferred checkpoint further out because editing is ongoing.
    ///
    /// Called on every document change so a snapshot never lands between two
    /// strokes.
    func delayPendingCheckpoints() {
        guard !notebookIDsAwaitingCheckpoint.isEmpty else { return }
        guard activePencilCanvasIDs.isEmpty else { return }
        restartDeferredCheckpointTimer()
    }

    func restartDeferredCheckpointTimer() {
        deferredCheckpointTask?.cancel()
        deferredCheckpointTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: deferredCheckpointDelay)
            } catch {
                return
            }
            flushDeferredCheckpoints()
        }
    }

    /// Writes every notebook that a deferred checkpoint is waiting on.
    func flushDeferredCheckpoints() {
        guard activePencilCanvasIDs.isEmpty else { return }
        for notebookID in cancelDeferredCheckpoints() {
            guard let notebook = library.notebook(id: notebookID) else { continue }
            persistCheckpoint(notebook)
        }
    }

    /// Stops the timer and returns the notebooks it was holding, for a caller
    /// that is about to write them itself.
    @discardableResult
    func cancelDeferredCheckpoints() -> Set<NotebookID> {
        deferredCheckpointTask?.cancel()
        deferredCheckpointTask = nil
        defer { notebookIDsAwaitingCheckpoint = [] }
        return notebookIDsAwaitingCheckpoint
    }

    func persistCheckpoint(_ notebook: Notebook) {
        guard activePencilCanvasIDs.isEmpty else {
            scheduleDeferredCheckpoint(for: notebook.id)
            return
        }
        guard let documentStore else {
            persistLibrary()
            return
        }
        journalCounts[notebook.id] = 0
        let checkpoint = nativePackage(for: notebook)
        let precedingTask = documentPersistenceTask
        let outcomeTask = Task { () -> Bool in
            await precedingTask?.value
            do {
                try await documentStore.save(checkpoint)
                persistLibrary()
                didPersistDocuments = true
                return true
            } catch {
                didPersistDocuments = false
                presentedError = "Your latest change could not be saved. \(error.localizedDescription)"
                return false
            }
        }
        documentPersistenceOutcomeTask = outcomeTask
        setDocumentPersistenceTail(Task { _ = await outcomeTask.value })
    }

    func checkpointDocuments() async {
        guard activePencilCanvasIDs.isEmpty else {
            notebookIDsAwaitingCheckpoint.formUnion(library.notebooks.map(\.id))
            return
        }
        guard let documentStore else {
            flushDeferredCheckpoints()
            await libraryPersistenceTask?.value
            await syncSubmissionTask?.value
            return
        }
        // Everything below writes every notebook, so anything the timer was
        // holding is already covered. Flushing as well would write those
        // notebooks twice inside the limited window the system grants for
        // backgrounding.
        cancelDeferredCheckpoints()

        let checkpoints = library.notebooks.map(nativePackage(for:))
        for checkpoint in checkpoints {
            journalCounts[checkpoint.notebook.id] = 0
        }
        let precedingTask = documentPersistenceTask
        let outcomeTask = Task { () -> Bool in
            await precedingTask?.value
            var didSaveEveryDocument = true
            for checkpoint in checkpoints {
                do {
                    try await documentStore.save(checkpoint)
                } catch {
                    didSaveEveryDocument = false
                    presentedError = "Your latest change could not be saved. \(error.localizedDescription)"
                }
            }
            didPersistDocuments = didSaveEveryDocument
            return didSaveEveryDocument
        }
        let persistenceTask = Task { _ = await outcomeTask.value }
        documentPersistenceOutcomeTask = outcomeTask
        setDocumentPersistenceTail(persistenceTask)
        await persistenceTask.value

        persistLibrary()
        await libraryPersistenceTask?.value
        await syncSubmissionTask?.value
        await waitForDocumentPersistenceToFinish()
    }

    func setDocumentPersistenceTail(_ task: Task<Void, Never>) {
        documentPersistenceTask = task
        documentPersistenceRevision &+= 1
    }

    func waitForDocumentPersistenceToFinish() async {
        while let persistenceTask = documentPersistenceTask {
            let revision = documentPersistenceRevision
            await persistenceTask.value
            if revision == documentPersistenceRevision { return }
        }
    }

    func nativePackage(for notebook: Notebook) -> NativeNotebookPackage {
        NativeNotebookPackage(
            schemaVersion: .current,
            notebook: notebook,
            appliedRemoteChangeIDs: appliedRemoteChangeIDsByNotebook[notebook.id, default: []]
        )
    }

    func openSearchResult(_ result: LibrarySearchResult) {
        pendingSearchNavigation = result
        open(result.notebookID)
    }

    func refreshSearchIndex(for notebookID: NotebookID) {
        guard let notebook = library.notebook(id: notebookID) else { return }
        searchIndex.update(notebook)
    }

    nonisolated static func defaultRepository() -> LocalLibraryRepository {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalLibraryRepository(fileURL: baseURL.appending(path: "Library/library.json"))
    }

    nonisolated static func defaultDocumentStore() -> LocalDocumentStore {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalDocumentStore(rootURL: baseURL.appending(path: "Documents", directoryHint: .isDirectory))
    }

    nonisolated static func defaultSyncStateStore() -> LocalSyncStateStore {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalSyncStateStore(directoryURL: supportURL.appending(path: "Sync"))
    }
}

private extension Notebook {
    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || tags.contains { $0.localizedCaseInsensitiveContains(query) }
            || canvases.contains { canvas in
                canvas.layers.flatMap(\.objects).contains { object in
                    object.searchableText?.localizedCaseInsensitiveContains(query) == true
                }
            }
            || recognitionByCanvas.values.flatMap({ $0 }).contains { record in
                record.result.text.localizedCaseInsensitiveContains(query)
            }
    }
}

private extension CanvasObject {
    var searchableText: String? {
        switch self {
        case let .text(text): text.text
        case let .pdf(pdf): pdf.embeddedText
        case .stroke, .shape, .image: nil
        }
    }
}
