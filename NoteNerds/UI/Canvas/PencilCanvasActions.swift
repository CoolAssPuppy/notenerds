import CoreGraphics
import Foundation

struct PencilCanvasActions {
    var onStrokesCompleted: @MainActor ([CompletedPencilStroke]) -> Void
    var onDrawingChanged: @MainActor (CanvasStrokeEdit, [CompletedPencilStroke]) -> Void
    var onConvertStrokesToText: @MainActor ([Stroke]) -> Void
    var onTransformObjects: @MainActor (Set<ObjectID>, SelectionTransform, CanvasPoint, [Stroke]) -> Void
    var onDeleteObjects: @MainActor (Set<ObjectID>) -> Void
    var onPasteObjects: @MainActor ([CanvasObject]) -> Void
    var onMoveObjectsToLayer: @MainActor (Set<ObjectID>, LayerID) -> Void
    var onEditText: @MainActor (TextBlock) -> Void
    var onPlaceText: @MainActor (CanvasPoint) -> Void
    var onPlaceShape: @MainActor (CanvasPoint) -> Void
    var onCommitText: @MainActor (TextBlock) -> Void
    var onCancelText: @MainActor () -> Void
    var onObjectSelectionChanged: @MainActor (Bool) -> Void
    var onViewportChanged: @MainActor (CanvasRect) -> Void
    var onPencilSqueeze: @MainActor (PencilSqueezeResponse, CGPoint?) -> Void
    var onPencilDoubleTap: @MainActor () -> Void
    var onPlannerRegionPageRequested: @MainActor (Int) -> Void
    var onPencilContactChanged: @MainActor (Bool) -> Void
}
