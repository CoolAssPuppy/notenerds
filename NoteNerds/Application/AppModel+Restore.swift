import Foundation

extension AppModel {
    func recoverNotebooks(
        _ notebooks: [Notebook],
        from documentStore: LocalDocumentStore
    ) async throws -> Bool {
        var recovered: [NotebookID: NativeNotebookPackage] = [:]
        var missing: Set<NotebookID> = []
        try await withThrowingTaskGroup(of: RecoveredNotebook.self) { group in
            var remaining = notebooks.makeIterator()
            func enqueueNext() {
                guard let notebook = remaining.next() else { return }
                group.addTask {
                    do {
                        return RecoveredNotebook(
                            id: notebook.id,
                            package: try await documentStore.recover(notebookID: notebook.id)
                        )
                    } catch LocalDocumentStoreError.notebookNotFound {
                        return RecoveredNotebook(id: notebook.id, package: nil)
                    }
                }
            }
            for _ in 0..<min(4, notebooks.count) { enqueueNext() }
            for try await result in group {
                if let package = result.package {
                    recovered[result.id] = package
                } else {
                    missing.insert(result.id)
                }
                enqueueNext()
            }
        }
        return try await applyRecoveredNotebooks(
            notebooks,
            recovered: recovered,
            missing: missing,
            documentStore: documentStore
        )
    }

    private func applyRecoveredNotebooks(
        _ notebooks: [Notebook],
        recovered: [NotebookID: NativeNotebookPackage],
        missing: Set<NotebookID>,
        documentStore: LocalDocumentStore
    ) async throws -> Bool {
        var didRepairLibrary = false
        for notebook in notebooks {
            if var package = recovered[notebook.id] {
                CanvasDiagnostics.mark("recovered notebook")
                appliedRemoteChangeIDsByNotebook[notebook.id] = package.appliedRemoteChangeIDs
                package.notebook = notebook.restoringDocumentContent(from: package.notebook)
                if package.notebook.repairDuplicateCanvasIdentifiers() {
                    try await documentStore.save(package)
                    didRepairLibrary = true
                }
                noteCheckpointSaved(for: notebook.id)
                library.updateNotebook(package.notebook)
            } else if missing.contains(notebook.id) {
                var repairedNotebook = notebook
                didRepairLibrary = repairedNotebook.repairDuplicateCanvasIdentifiers() || didRepairLibrary
                library.updateNotebook(repairedNotebook)
                try await documentStore.save(nativePackage(for: repairedNotebook))
                noteCheckpointSaved(for: notebook.id)
            }
        }
        return didRepairLibrary
    }
}

private struct RecoveredNotebook: Sendable {
    let id: NotebookID
    let package: NativeNotebookPackage?
}
