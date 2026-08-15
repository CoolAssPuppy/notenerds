import Foundation

enum CanvasSearchHighlights {
    static func strokes(_ strokes: [Stroke], intersecting visibleBounds: CanvasRect) -> [Stroke] {
        CanvasSpatialIndex(objects: strokes.map(CanvasObject.stroke))
            .objects(in: visibleBounds)
            .compactMap(\.strokeValue)
    }
}
