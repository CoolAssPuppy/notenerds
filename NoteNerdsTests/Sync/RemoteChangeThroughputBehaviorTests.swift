import XCTest
@testable import NoteNerds

@MainActor
final class RemoteChangeThroughputBehaviorTests: XCTestCase {
    /// The watchdog kills an app whose main thread stops answering, so a large
    /// batch of incoming strokes has to be read without holding onto it.
    func testALargeBatchOfRemoteStrokesNeverStallsTheMainThread() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let provider = InMemorySyncProvider()
        let notebook = DomainFixtures.notebook(title: "Busy shared notebook")
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let existingStrokeCount = strokeCount(in: notebook)
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let encoder = SyncChangeEncoder(deviceID: "remote-device")
        let changes = try (0..<200).map { index in
            try encoder.change(
                for: .addStroke(
                    canvasID: canvas.id,
                    layerID: layer.id,
                    stroke: makeStroke(layerID: layer.id, sampleCount: 1_500)
                ),
                notebookID: notebook.id,
                sequence: index + 1,
                timestamp: DomainFixtures.fixedDate.addingTimeInterval(TimeInterval(index))
            )
        }
        let model = AppModel(
            repository: repository,
            documentStore: documentStore,
            syncProvider: provider,
            syncStateStore: InMemorySyncStateStore(),
            deviceID: "receiving-device",
            automaticallyRestore: false
        )
        await model.restoreLibrary()
        try await provider.push(changes)

        let monitor = MainThreadStallMonitor()
        await monitor.start()
        await model.synchronize()
        let longestStall = await monitor.stop()

        let applied = try XCTUnwrap(model.notebook(notebook.id))
        XCTAssertEqual(strokeCount(in: applied), existingStrokeCount + changes.count)
        XCTAssertLessThan(longestStall, .milliseconds(750), "Main thread stalled for \(longestStall)")
    }

    private func strokeCount(in notebook: Notebook) -> Int {
        notebook.canvases
            .flatMap(\.layers)
            .flatMap(\.objects)
            .compactMap(\.strokeValue)
            .count
    }

    private func makeStroke(layerID: LayerID, sampleCount: Int) -> Stroke {
        Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: (0..<sampleCount).map { index in
                StrokeSample(
                    point: CanvasPoint(x: Double(index), y: Double(index) * 1.5),
                    pressure: 0.5,
                    altitude: 0.8,
                    azimuth: 1.2,
                    roll: 0.1,
                    timeOffset: TimeInterval(index) / 240
                )
            },
            style: StrokeStyle(
                instrument: .ballpoint,
                width: 2,
                color: InkColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
            ),
            createdAt: DomainFixtures.fixedDate
        )
    }
}

/// Ticks on the main actor and remembers the longest it was kept waiting.
@MainActor
private final class MainThreadStallMonitor {
    private var longestStall: Duration = .zero
    private var ticker: Task<Void, Never>?

    func start() async {
        let clock = ContinuousClock()
        ticker = Task { @MainActor [weak self] in
            var previousTick = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = clock.now
                self?.recordTick(since: previousTick)
                previousTick = now
            }
        }
        // Let the ticker take its first measurement before the work begins.
        try? await Task.sleep(for: .milliseconds(50))
        longestStall = .zero
    }

    func stop() async -> Duration {
        ticker?.cancel()
        ticker = nil
        return longestStall
    }

    private func recordTick(since previousTick: ContinuousClock.Instant) {
        longestStall = max(longestStall, ContinuousClock().now - previousTick)
    }
}
