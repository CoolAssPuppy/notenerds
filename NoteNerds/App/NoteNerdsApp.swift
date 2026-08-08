import SwiftUI

@main
struct NoteNerdsApp: App {
    @StateObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let processInfo = ProcessInfo.processInfo
        let isUITesting = processInfo.arguments.contains("-ui-testing")
        let isUnitTesting = processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isUITesting && ProcessInfo.processInfo.arguments.contains("-reset-library") {
            let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: supportURL.appending(path: "Library"))
            try? FileManager.default.removeItem(at: supportURL.appending(path: "Documents"))
        }
        _model = StateObject(wrappedValue: AppModel(
            documentStore: AppModel.defaultDocumentStore(),
            syncProvider: isUITesting || isUnitTesting ? nil : DefaultSyncProvider.make(),
            syncStateStore: AppModel.defaultSyncStateStore()
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onOpenURL(perform: model.importExternalFile)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New notebook") { model.createNotebook() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.checkpointDocuments() } }
        }
    }
}
