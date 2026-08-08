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

    let repository: LocalLibraryRepository
    let documentStore: LocalDocumentStore?
    let recognitionCoordinator: HandwritingRecognitionCoordinator
    var histories: [NotebookID: DocumentHistory] = [:]
    var recognitionTasks: [CanvasID: Task<Void, Never>] = [:]
    var conversionTasks: [CanvasID: Task<Void, Never>] = [:]
    var pendingConversionStrokeIDs: [CanvasID: Set<StrokeID>] = [:]
    let conversionDelay: Duration
    var searchIndex = LibrarySearchIndex()
    let syncEngine: SyncEngine?
    let syncChangeEncoder: SyncChangeEncoder
    var syncSequence = 0
    var seenSyncChangeIDs: Set<ChangeID> = []
    var journalCounts: [NotebookID: Int] = [:]
    var libraryPersistenceTask: Task<Void, Never>?
    var documentPersistenceTask: Task<Void, Never>?
    private var libraryRestoreTask: Task<Void, Never>?

    init(
        repository: LocalLibraryRepository = AppModel.defaultRepository(),
        documentStore: LocalDocumentStore? = nil,
        syncProvider: (any SyncProvider)? = nil,
        syncStateStore: (any SyncStateStore)? = nil,
        deviceID: String = UUID().uuidString,
        recognitionCoordinator: HandwritingRecognitionCoordinator = HandwritingRecognitionCoordinator(
            recognizer: AppleHandwritingRecognizer()
        ),
        conversionDelay: Duration = .milliseconds(700),
        automaticallyRestore: Bool = true
    ) {
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
            base = library.notebooks(sortedBy: library.preferredSortMode)
        case .favorites:
            base = library.notebooks(sortedBy: library.preferredSortMode).filter(\.isFavorite)
        case .recents:
            base = library.notebooks(sortedBy: .recentlyOpened)
        case .trash:
            base = library.notebooks.filter { $0.trashedAt != nil }.sorted { $0.modifiedAt > $1.modifiedAt }
        }
        let scoped = selectedSection == .files && searchQuery.isEmpty
            ? base.filter { $0.parentFolderID == currentFolderID }
            : base
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
        defer { hasRestoredLibrary = true }
        do {
            library = try await repository.load()
            if let documentStore {
                for notebook in library.notebooks {
                    do {
                        let recovered = try await documentStore.recover(notebookID: notebook.id)
                        library.updateNotebook(recovered.notebook)
                    } catch LocalDocumentStoreError.notebookNotFound {
                        try await documentStore.save(
                            NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
                        )
                    }
                }
            }
            for notebook in library.notebooks { searchIndex.update(notebook) }
            await synchronize()
        } catch {
            presentedError = "Your local library could not be opened. \(error.localizedDescription)"
        }
    }

    func persistLibrary() {
        let snapshot = library
        let precedingTask = libraryPersistenceTask
        libraryPersistenceTask = Task {
            await precedingTask?.value
            do {
                try await repository.save(snapshot)
            } catch {
                presentedError = "Your latest change could not be saved. \(error.localizedDescription)"
            }
        }
    }

    func execute(_ operation: DocumentOperation, on notebookID: NotebookID) {
        guard var notebook = library.notebook(id: notebookID) else { return }
        var history = histories[notebookID, default: DocumentHistory()]
        do {
            try history.execute(operation, on: &notebook)
            notebook.modifiedAt = Date()
            histories[notebookID] = history
            library.updateNotebook(notebook)
            updateSearchIndex(after: operation, in: notebook)
            persist(operation, notebook: notebook)
            enqueueForSync(operation, notebookID: notebookID)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func updateSearchIndex(after operation: DocumentOperation, in notebook: Notebook) {
        guard operation.requiresSearchIndexUpdate else { return }
        if let canvasID = operation.searchCanvasID {
            searchIndex.update(canvasID: canvasID, in: notebook)
        } else {
            searchIndex.update(notebook)
        }
    }

    func persist(_ operation: DocumentOperation, notebook: Notebook) {
        guard let documentStore else {
            persistLibrary()
            return
        }
        let notebookID = notebook.id
        let count = journalCounts[notebookID, default: 0] + 1
        journalCounts[notebookID] = count
        let precedingTask = documentPersistenceTask
        documentPersistenceTask = Task {
            await precedingTask?.value
            do {
                try await documentStore.append(operation, notebookID: notebookID)
                if count >= 20 {
                    try await documentStore.save(
                        NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
                    )
                    journalCounts[notebookID] = 0
                    persistLibrary()
                }
            } catch {
                presentedError = "Your latest change could not be saved. \(error.localizedDescription)"
            }
        }
    }

    func persistCheckpoint(_ notebook: Notebook) {
        guard let documentStore else {
            persistLibrary()
            return
        }
        journalCounts[notebook.id] = 0
        let precedingTask = documentPersistenceTask
        documentPersistenceTask = Task {
            await precedingTask?.value
            do {
                try await documentStore.save(
                    NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
                )
                persistLibrary()
            } catch {
                presentedError = "Your latest change could not be saved. \(error.localizedDescription)"
            }
        }
    }

    func checkpointDocuments() async {
        await documentPersistenceTask?.value
        guard let documentStore else {
            await libraryPersistenceTask?.value
            return
        }
        for notebook in library.notebooks {
            try? await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
            journalCounts[notebook.id] = 0
        }
        persistLibrary()
        await libraryPersistenceTask?.value
    }

    private func enqueueForSync(_ operation: DocumentOperation, notebookID: NotebookID) {
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
            Task {
                await syncEngine.enqueue(change)
                await synchronize(using: syncEngine)
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
            Task {
                await syncEngine.enqueue(change)
                await synchronize(using: syncEngine)
            }
        } catch {
            syncIssue = "This change is saved locally and is waiting for iCloud sync."
        }
    }

    func enqueueAssetForSync(_ asset: DocumentAsset) {
        guard let syncEngine else { return }
        Task {
            await syncEngine.enqueue(asset)
            await synchronize(using: syncEngine)
        }
    }

    func synchronize(using engine: SyncEngine? = nil) async {
        guard let engine = engine ?? syncEngine else { return }
        await engine.synchronize()
        let state = await engine.state
        let failure = await engine.lastFailure
        let changes = await engine.receivedChangesSnapshot()
        applyRemoteChanges(changes)
        await engine.acknowledgeReceivedChanges(Set(changes.map(\.id)))
        syncIssue = state == .idle ? nil : failure?.userMessage
    }

    private func applyRemoteChanges(_ changes: [DocumentChange]) {
        for change in changes where !seenSyncChangeIDs.contains(change.id) {
            seenSyncChangeIDs.insert(change.id)
            if let mutation = try? SyncChangeEncoder.decodeLibraryMutation(change) {
                try? mutation.apply(to: &library)
                if let notebookID = mutation.affectedNotebookID {
                    if let notebook = library.notebook(id: notebookID) {
                        searchIndex.update(notebook)
                        fetchMissingAssets(in: notebook)
                    } else {
                        searchIndex.remove(notebookID: notebookID)
                    }
                } else {
                    searchIndex = LibrarySearchIndex()
                    for notebook in library.notebooks { searchIndex.update(notebook) }
                }
                continue
            }
            guard var notebook = library.notebook(id: change.notebookID),
                  let action = try? SyncChangeEncoder.decodeDocumentAction(change),
                  (try? action.perform(on: &notebook)) != nil else { continue }
            notebook.modifiedAt = max(notebook.modifiedAt, change.timestamp)
            library.updateNotebook(notebook)
            searchIndex.update(notebook)
            fetchMissingAssets(in: notebook)
        }
        if !changes.isEmpty { persistLibrary() }
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
