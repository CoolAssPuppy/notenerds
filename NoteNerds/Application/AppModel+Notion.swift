import Foundation

extension AppModel {
    func replaceLibraryAfterNotionRestore(_ restored: LibraryState) async {
        do {
            if let documentStore {
                for notebook in restored.notebooks {
                    try await documentStore.save(
                        NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
                    )
                }
            }
            try await repository.save(restored)
            library = restored
            searchIndex = LibrarySearchIndex()
            for notebook in restored.notebooks {
                refreshHandwritingSearch(in: notebook.id)
            }
        } catch {
            presentedError = "The restored notebooks could not be saved. \(error.localizedDescription)"
        }
    }
}
