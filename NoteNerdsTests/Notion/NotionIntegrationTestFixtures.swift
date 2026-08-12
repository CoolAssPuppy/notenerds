@testable import NoteNerds

actor StubDestinationProvider: NotionDestinationProviding {
    let destination = NotionDestination(
        databaseID: "11111111-1111-1111-1111-111111111111",
        dataSourceID: "22222222-2222-2222-2222-222222222222"
    )
    private(set) var createdParentIDs: [String] = []
    let manifestPage = NotionPageBinding(
        pageID: "55555555-5555-5555-5555-555555555555",
        url: nil
    )

    func searchPages(query: String?) -> [NotionPageSummary] {
        [
            NotionPageSummary(
                id: "33333333-3333-3333-3333-333333333333",
                title: "Product",
                url: nil
            ),
            NotionPageSummary(
                id: "44444444-4444-4444-4444-444444444444",
                title: "Personal",
                url: nil
            )
        ]
    }

    func createDatabase(parentPageID: String) -> NotionDestination {
        createdParentIDs.append(parentPageID)
        return destination
    }

    func createLibraryManifestPage(parentPageID: String) -> NotionPageBinding {
        createdParentIDs.append(parentPageID)
        return manifestPage
    }
}

actor IntegrationStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?

    init(state: NotionSyncState? = nil) {
        self.state = state
    }

    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}
