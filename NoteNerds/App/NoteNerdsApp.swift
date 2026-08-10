import SwiftUI

@main
struct NoteNerdsApp: App {
    @StateObject private var model: AppModel
    @StateObject private var notion: NotionIntegrationModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let processInfo = ProcessInfo.processInfo
        let isUITesting = processInfo.arguments.contains("-ui-testing")
        let isUnitTesting = processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isUITesting && ProcessInfo.processInfo.arguments.contains("-reset-library") {
            let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: supportURL.appending(path: "Library"))
            try? FileManager.default.removeItem(at: supportURL.appending(path: "Documents"))
            UserDefaults.standard.set(PaperType.blankWhite.rawValue, forKey: "defaultPaperType")
            UserDefaults.standard.set(false, forKey: "isCanvasToolbarExpanded")
            UserDefaults.standard.set(true, forKey: "isToolbarOnLeft")
            UserDefaults.standard.set(
                CanvasToolbarOrientation.vertical.rawValue,
                forKey: "canvasToolbarOrientation"
            )
        }
        let model = AppModel(
            documentStore: AppModel.defaultDocumentStore(),
            syncProvider: isUITesting || isUnitTesting ? nil : DefaultSyncProvider.make(),
            syncStateStore: AppModel.defaultSyncStateStore(),
            automaticallyRestore: false
        )
        if isUITesting && processInfo.arguments.contains("-force-sync-issue") {
            model.syncIssue = "This change is saved locally and is waiting for iCloud sync."
        }
        _model = StateObject(wrappedValue: model)
        let notionConfiguration = Self.notionConfiguration(
            isUITesting: isUITesting,
            processInfo: processInfo
        )
        let notion = Self.makeNotionModel(configuration: notionConfiguration)
#if DEBUG
        if isUITesting && processInfo.arguments.contains("-force-notion-connected") {
            notion.configureForUITesting(
                state: .connected(workspaceName: "Personal"),
                destination: NotionDestination(
                    databaseID: "11111111-1111-1111-1111-111111111111",
                    dataSourceID: "22222222-2222-2222-2222-222222222222"
                )
            )
        } else if isUITesting && processInfo.arguments.contains("-force-notion-failure") {
            notion.configureForUITesting(
                state: .actionNeeded,
                destination: nil,
                failureMessage: "Notion rejected the update."
            )
        }
#endif
        _notion = StateObject(wrappedValue: notion)
    }

    private static func makeNotionModel(
        configuration: NotionOAuthConfiguration
    ) -> NotionIntegrationModel {
        let credentialStore = KeychainNotionCredentialStore()
        let connectionService = NotionConnectionService(
            configuration: configuration,
            credentialStore: credentialStore
        )
        let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let registry = NotionSyncRegistry(
            store: LocalNotionSyncStateStore(directoryURL: supportURL.appending(path: "Notion"))
        )
        let notionRateLimiter = NotionRequestRateLimiter()
        let refreshingAPI = NotionRefreshingAPI(
            credentialStore: credentialStore,
            refresh: { try await connectionService.refresh() },
            apiFactory: { token in
                NotionAPIClient(
                    accessToken: token,
                    requestRateLimiter: notionRateLimiter
                )
            }
        )
        let meetingLinkCoordinator = NotionMeetingLinkCoordinator(
            api: refreshingAPI,
            registry: registry
        )
        let publisher = NotionLibraryPublisher(
            api: refreshingAPI,
            registry: registry,
            meetingLinkCoordinator: meetingLinkCoordinator
        )
        let remoteLoader = NotionRemoteLibraryLoader(api: refreshingAPI, registry: registry)
        let restorer = NotionLibraryRestoreService(loader: remoteLoader)
        return NotionIntegrationModel(
            isConfigured: configuration.isConfigured,
            connectionManager: connectionService,
            destinationProviderFactory: { _ in refreshingAPI },
            registry: registry,
            publisher: publisher,
            restorer: restorer,
            meetingLinkCoordinator: meetingLinkCoordinator
        )
    }

    private static func notionConfiguration(
        isUITesting: Bool,
        processInfo: ProcessInfo
    ) -> NotionOAuthConfiguration {
        guard !isUITesting || !processInfo.arguments.contains("-force-notion-unavailable") else {
            return NotionOAuthConfiguration(clientID: "", clientSecret: "")
        }
        return NotionAppConfiguration.oauthConfiguration
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, notion: notion)
                .onOpenURL { url in
                    Task {
                        await model.restoreLibrary()
                        model.importExternalFile(at: url)
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New notebook") { model.createNotebook() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                notion.resumeAutomaticSync()
                notion.resumeMeetingLinks()
            } else {
                notion.pauseAutomaticSync()
                notion.pauseMeetingLinks()
                Task { await model.checkpointDocuments() }
            }
        }
    }
}
