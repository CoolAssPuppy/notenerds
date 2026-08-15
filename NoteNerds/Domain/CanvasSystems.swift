import Foundation

struct CanvasSpatialIndex: Sendable {
    private struct Cell: Hashable, Sendable {
        let column: Int
        let row: Int
    }

    private let objects: [CanvasObject]
    private let cellSize: Double
    private let objectIndicesByCell: [Cell: Set<Int>]
    private let broadlyIntersectingIndices: Set<Int>

    init(objects: [CanvasObject], cellSize: Double = 512) {
        self.objects = objects
        self.cellSize = max(cellSize, 1)
        var index: [Cell: Set<Int>] = [:]
        var broadIndices: Set<Int> = []
        for (objectIndex, object) in objects.enumerated() {
            guard let cells = Self.cells(
                intersecting: object.bounds,
                cellSize: self.cellSize,
                maximumCount: 4_096
            ) else {
                broadIndices.insert(objectIndex)
                continue
            }
            for cell in cells {
                index[cell, default: []].insert(objectIndex)
            }
        }
        objectIndicesByCell = index
        broadlyIntersectingIndices = broadIndices
    }

    func objects(in visibleBounds: CanvasRect) -> [CanvasObject] {
        let visibleCells = Self.cells(intersecting: visibleBounds, cellSize: cellSize, maximumCount: 4_096) ?? []
        var indices = broadlyIntersectingIndices
        for cell in visibleCells {
            indices.formUnion(objectIndicesByCell[cell] ?? [])
        }
        return indices.sorted().compactMap { index in
            let object = objects[index]
            return object.bounds.intersects(visibleBounds) ? object : nil
        }
    }

    private static func cells(
        intersecting bounds: CanvasRect,
        cellSize: Double,
        maximumCount: Int
    ) -> [Cell]? {
        let values = [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY]
        guard values.allSatisfy(\.isFinite),
              bounds.size.width >= 0,
              bounds.size.height >= 0 else { return nil }
        let minimumColumn = floor(bounds.minX / cellSize)
        let maximumColumn = floor(bounds.maxX / cellSize)
        let minimumRow = floor(bounds.minY / cellSize)
        let maximumRow = floor(bounds.maxY / cellSize)
        guard minimumColumn >= Double(Int.min), maximumColumn < Double(Int.max),
              minimumRow >= Double(Int.min), maximumRow < Double(Int.max) else { return nil }
        let columns = Int(minimumColumn)...Int(maximumColumn)
        let rows = Int(minimumRow)...Int(maximumRow)
        let (count, overflow) = columns.count.multipliedReportingOverflow(by: rows.count)
        guard !overflow, count <= maximumCount else { return nil }
        return columns.flatMap { column in rows.map { Cell(column: column, row: $0) } }
    }
}

struct MinimapLayout: Sendable {
    let contentFrame: CanvasRect
    let viewportFrame: CanvasRect

    init(contentBounds: CanvasRect, viewportBounds: CanvasRect, displaySize: CanvasSize) {
        let contentWidth = max(contentBounds.size.width, 1)
        let contentHeight = max(contentBounds.size.height, 1)
        let scale = min(displaySize.width / contentWidth, displaySize.height / contentHeight)
        let width = contentWidth * scale
        let height = contentHeight * scale
        let originX = (displaySize.width - width) / 2
        let originY = (displaySize.height - height) / 2
        contentFrame = CanvasRect(x: originX, y: originY, width: width, height: height)
        viewportFrame = CanvasRect(
            x: originX + (viewportBounds.minX - contentBounds.minX) * scale,
            y: originY + (viewportBounds.minY - contentBounds.minY) * scale,
            width: viewportBounds.size.width * scale,
            height: viewportBounds.size.height * scale
        )
    }
}

enum CanvasInputMode: String, Codable, Sendable {
    case pencilAndNavigation
    case fingerDrawing
}

enum CanvasInput: Sendable {
    case pencil
    case oneFinger
    case twoFingers
}

enum CanvasInputAction: Sendable {
    case draw
    case navigate
}

enum CanvasNavigationAction: Equatable, Sendable {
    case home
    case zoomToContent(CanvasRect)
}

/// Decides where a reopened canvas should look.
///
/// New writing is supposed to land in the centred home page. `PKCanvasView`
/// often drops that offset while its bounds are still zero, so the first
/// strokes are saved near the origin. The library thumbnail crops to those
/// strokes, then opening the note shows the empty home page. If the ink is
/// outside home, this zooms to it.
enum CanvasViewportPolicy {
    static func openingAction(
        contentBounds: CanvasRect?,
        defaultViewport: CanvasRect = CanvasViewport.defaultVisibleBounds
    ) -> CanvasNavigationAction {
        guard let contentBounds, hasVisibleInk(contentBounds) else { return .home }
        if contentBounds.intersects(defaultViewport) { return .home }
        return .zoomToContent(contentBounds)
    }

    private static func hasVisibleInk(_ bounds: CanvasRect) -> Bool {
        bounds.size.width > 0 || bounds.size.height > 0 || bounds.minX != 0 || bounds.minY != 0
    }
}

struct CanvasNavigationCommand: Identifiable, Sendable {
    let id = UUID()
    let action: CanvasNavigationAction
}

enum CanvasEditingAction: Equatable, Sendable {
    case copy
    case cut
    case paste
    case selectAll
    case delete
    case convertToText
    case duplicate
    case moveToLayer(LayerID)
}

struct CanvasEditingCommand: Identifiable, Sendable {
    let id = UUID()
    let action: CanvasEditingAction
}

struct InputRouter: Sendable {
    let mode: CanvasInputMode

    func action(for input: CanvasInput) -> CanvasInputAction? {
        switch (mode, input) {
        case (_, .pencil), (.fingerDrawing, .oneFinger): .draw
        case (_, .twoFingers): .navigate
        case (.pencilAndNavigation, .oneFinger): nil
        }
    }
}

enum DrawingInputPolicy {
    static func allowsFingerDrawing(userPreference: Bool, isSimulator: Bool) -> Bool {
        userPreference || isSimulator
    }

    static func allowsFingerDrawingForCurrentBuild(userPreference: Bool) -> Bool {
        #if targetEnvironment(simulator)
        allowsFingerDrawing(userPreference: userPreference, isSimulator: true)
        #else
        allowsFingerDrawing(userPreference: userPreference, isSimulator: false)
        #endif
    }
}

extension Canvas {
    var contentBounds: CanvasRect? {
        let objects = layers.filter(\.isVisible).flatMap(\.objects)
        guard let first = objects.first else { return nil }
        return objects.dropFirst().reduce(first.bounds) { bounds, object in
            CanvasRect.enclosing([
                bounds.origin,
                CanvasPoint(x: bounds.maxX, y: bounds.maxY),
                object.bounds.origin,
                CanvasPoint(x: object.bounds.maxX, y: object.bounds.maxY)
            ])
        }
    }

    var exportBounds: CanvasRect {
        contentBounds ?? CanvasViewport.defaultVisibleBounds
    }
}

extension Notebook {
    var previewCanvas: Canvas {
        canvases.first { canvas in
            canvas.layers.contains { layer in
                layer.isVisible && !layer.objects.isEmpty
            }
        } ?? canvases[0]
    }
}
