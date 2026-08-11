import Combine
import Foundation

/// Carries the visible canvas rectangle to the views that draw it.
///
/// `PKCanvasView` reports its viewport on every scroll and zoom frame. Holding
/// that value in `NotebookEditorView` state re-evaluated the whole editor body
/// at scroll rate, and each evaluation rebuilt the stroke and object arrays for
/// the open canvas. Only the minimap needs the live value, so it observes this
/// object directly and the editor body stays out of the scroll path.
final class CanvasViewportModel: ObservableObject {
    static let defaultBounds = CanvasRect(x: 9_500, y: 9_500, width: 1_024, height: 1_366)

    @Published private(set) var bounds: CanvasRect

    init(bounds: CanvasRect = CanvasViewportModel.defaultBounds) {
        self.bounds = bounds
    }

    /// Records a viewport report, ignoring the repeats that scrolling produces.
    func report(_ bounds: CanvasRect) {
        guard self.bounds != bounds else { return }
        self.bounds = bounds
    }
}
