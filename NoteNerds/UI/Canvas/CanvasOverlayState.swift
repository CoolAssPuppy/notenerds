import Foundation

struct CanvasOverlayState {
    var strokes: [Stroke] = []
    var objects: [CanvasObject] = []
    var assets: [AssetID: Data] = [:]
    var highlightedStrokeIDs: Set<StrokeID> = []
    var isLassoEnabled = false
    var isTextPlacementEnabled = false
    var shapePlacementKind: RecognizedShapeKind?
}
