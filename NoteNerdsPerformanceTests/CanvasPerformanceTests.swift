import XCTest
import UIKit
@testable import NoteNerds

final class CanvasPerformanceTests: XCTestCase {
    func testSyncQueueAcceptsTenThousandUniqueChangesWithinHalfASecond() async {
        let engine = SyncEngine(provider: InMemorySyncProvider())
        let notebookID = NotebookID()
        let changes = (0..<10_000).map { index in
            DocumentChange(
                id: ChangeID(),
                notebookID: notebookID,
                objectKey: "object-\(index)",
                kind: .upsert,
                payload: Data(),
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                deviceID: "performance",
                sequence: index
            )
        }
        let clock = ContinuousClock()
        let start = clock.now

        for change in changes {
            await engine.enqueue(change)
        }

        let pendingCount = await engine.pendingChanges.count
        XCTAssertEqual(pendingCount, changes.count)
        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(500))
    }

    func testTrashingTenThousandNestedFoldersWithinHalfASecond() throws {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        var parentID: FolderID?
        let folders = (0..<10_000).map { index in
            let folder = Folder(
                name: "Folder \(index)",
                parentID: parentID,
                createdAt: date,
                modifiedAt: date
            )
            parentID = folder.id
            return folder
        }
        var library = LibraryState(folders: folders)
        let rootID = try XCTUnwrap(folders.first?.id)
        let clock = ContinuousClock()
        let start = clock.now

        try library.moveFolderToTrash(rootID, at: date)

        XCTAssertEqual(library.folders.filter { $0.trashedAt != nil }.count, folders.count)
        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(500))
    }

    func testNotionQueueWithOneThousandEntriesRestoresWithinOneTenthSecond() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "NoteNerds-Notion-Performance-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalNotionSyncStateStore(directoryURL: directory)
        let queue = (0..<1_000).map { index in
            NotionSyncQueueItem(
                notebookID: deterministicUUIDString(index: index),
                enqueuedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                attemptCount: index % 4,
                nextAttemptAt: nil,
                lastFailure: nil
            )
        }
        try await store.save(NotionSyncState(queue: queue))

        let clock = ContinuousClock()
        let start = clock.now
        let restored = try await store.load()
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(restored?.queue.count, 1_000)
        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    func testVisibleRegionQueryWithTwentyThousandObjects() {
        let layerID = LayerID()
        let objects = (0..<20_000).map { index in
            CanvasObject.text(TextBlock(
                id: ObjectID(),
                layerID: layerID,
                text: "Item \(index)",
                frame: CanvasRect(
                    x: Double(index % 200) * 100,
                    y: Double(index / 200) * 60,
                    width: 80,
                    height: 40
                ),
                fontSize: 17,
                alignment: .left
            ))
        }
        let index = CanvasSpatialIndex(objects: objects)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for offset in stride(from: 0.0, through: 10_000.0, by: 250) {
                _ = index.objects(in: CanvasRect(x: offset, y: offset / 2, width: 1_366, height: 1_024))
            }
        }
    }

    func testHistoryWithOneHundredMeaningfulActions() throws {
        let notebook = Notebook(title: "Performance", canvases: [Canvas(title: "Canvas")])
        let canvasID = notebook.canvases[0].id
        let layerID = notebook.canvases[0].layers[0].id

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            var measuredNotebook = notebook
            var history = DocumentHistory()
            for index in 0..<100 {
                let stroke = makeStroke(index: index, layerID: layerID)
                try? history.execute(
                    .addStroke(canvasID: canvasID, layerID: layerID, stroke: stroke),
                    on: &measuredNotebook
                )
            }
        }
    }

    func testIncrementalSearchIndexingInLargeNotebook() {
        let notebook = makeLargeNotebook(canvasCount: 40, objectsPerCanvas: 250)
        var index = LibrarySearchIndex()
        index.update(notebook)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            index.update(canvasID: notebook.canvases[20].id, in: notebook)
        }
    }

    func testLargeNotebookOpeningDecode() throws {
        let notebook = makeLargeNotebook(canvasCount: 30, objectsPerCanvas: 150)
        let serializer = NativeDocumentSerializer()
        let data = try serializer.encode(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = try? serializer.decode(data)
        }
    }

    func testPanAndZoomCoordinateUpdates() {
        let viewport = CanvasViewport(origin: CanvasPoint(x: 10_000, y: 10_000), zoom: 1.5)

        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<100_000 {
                let point = CanvasPoint(x: Double(index % 2_000), y: Double(index / 2_000))
                _ = viewport.screenPoint(for: point)
            }
        }
    }

    @MainActor
    func testImportedPDFRenderingAndExport() throws {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for page in 0..<12 {
                context.beginPage()
                NSString(string: "Page \(page + 1)").draw(at: CGPoint(x: 40, y: 40), withAttributes: nil)
            }
        }
        let imported = try PDFImporter().importDocument(data: data, title: "Performance", origin: .zero)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = try? NotebookPDFExporter().export(imported.notebook, assets: imported.assets)
        }
    }

    private func makeLargeNotebook(canvasCount: Int, objectsPerCanvas: Int) -> Notebook {
        let canvases = (0..<canvasCount).map { canvasIndex in
            let layerID = LayerID()
            let objects = (0..<objectsPerCanvas).map { objectIndex in
                CanvasObject.text(TextBlock(
                    id: ObjectID(),
                    layerID: layerID,
                    text: "Canvas \(canvasIndex) item \(objectIndex)",
                    frame: CanvasRect(x: Double(objectIndex * 20), y: 20, width: 180, height: 40),
                    fontSize: 17,
                    alignment: .left
                ))
            }
            return Canvas(title: "Canvas \(canvasIndex)", layers: [Layer(id: layerID, name: "Text", objects: objects)])
        }
        return Notebook(title: "Large notebook", canvases: canvases)
    }

    private func makeStroke(index: Int, layerID: LayerID) -> Stroke {
        Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: (0..<40).map { sampleIndex in
                StrokeSample(
                    point: CanvasPoint(x: Double(sampleIndex * 4), y: Double(index * 3)),
                    pressure: 0.5,
                    altitude: 0.8,
                    azimuth: 1.2,
                    roll: 0,
                    timeOffset: Double(sampleIndex) / 120
                )
            },
            style: StrokeStyle(instrument: .ballpoint, width: 2, color: .black),
            createdAt: Date()
        )
    }

    private func deterministicUUIDString(index: Int) -> String {
        String(format: "00000000-0000-0000-0000-%012d", index)
    }
}
