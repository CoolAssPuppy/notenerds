import Combine
import XCTest
@testable import NoteNerds

final class CanvasViewportBehaviorTests: XCTestCase {
    func testRepeatedViewportReportsDoNotNotifyObservers() {
        let viewport = CanvasViewportModel(bounds: bounds(x: 0))
        var notificationCount = 0
        let cancellable = viewport.objectWillChange.sink { notificationCount += 1 }

        viewport.report(bounds(x: 0))
        viewport.report(bounds(x: 0))
        viewport.report(bounds(x: 0))

        XCTAssertEqual(notificationCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testAChangedViewportNotifiesObserversOnce() {
        let viewport = CanvasViewportModel(bounds: bounds(x: 0))
        var notificationCount = 0
        let cancellable = viewport.objectWillChange.sink { notificationCount += 1 }

        viewport.report(bounds(x: 40))
        viewport.report(bounds(x: 40))

        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(viewport.bounds, bounds(x: 40))
        withExtendedLifetime(cancellable) {}
    }

    private func bounds(x: Double) -> CanvasRect {
        CanvasRect(x: x, y: 0, width: 1_024, height: 1_366)
    }
}
