#if DEBUG
actor NotionDestinationSelectionUITestProvider: NotionDestinationProviding {
    func searchPages(query: String?) -> [NotionPageSummary] { [] }

    func createDatabase(parentPageID: String) async throws -> NotionDestination {
        try await Task.sleep(for: .seconds(3))
        return NotionDestination(
            parentPageID: parentPageID,
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            databaseName: "Note Nerds"
        )
    }

    func createLibraryManifestPage(parentPageID: String) -> NotionPageBinding {
        NotionPageBinding(
            pageID: "55555555-5555-5555-5555-555555555555",
            url: nil
        )
    }
}
#endif
