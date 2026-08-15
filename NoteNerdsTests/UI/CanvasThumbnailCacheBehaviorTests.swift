import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class CanvasThumbnailCacheBehaviorTests: XCTestCase {
    func testReturnsTheSameImageWhileTheCanvasIdentityIsUnchanged() {
        let canvas = DomainFixtures.notebook().canvases[0]
        let size = CGSize(width: 80, height: 60)

        let first = CanvasThumbnailCache.image(for: canvas, size: size)
        let second = CanvasThumbnailCache.image(for: canvas, size: size)

        XCTAssertTrue(first === second)
    }

    func testRendersANewImageAfterTheCanvasChanges() {
        var canvas = DomainFixtures.notebook().canvases[0]
        let size = CGSize(width: 80, height: 60)
        let first = CanvasThumbnailCache.image(for: canvas, size: size)
        canvas.modifiedAt = canvas.modifiedAt.addingTimeInterval(1)

        let second = CanvasThumbnailCache.image(for: canvas, size: size)

        XCTAssertFalse(first === second)
    }
}
