import UIKit
import XCTest
@testable import NoteNerds

final class PencilSqueezeBehaviorTests: XCTestCase {
    func testSqueezeHonorsEverySystemPreferenceAtTheCompletedGesturePhase() {
        let expectations: [(UIPencilPreferredAction, PencilSqueezeResponse)] = [
            (.ignore, .none),
            (.switchEraser, .switchEraser),
            (.switchPrevious, .switchPreviousTool),
            (.showColorPalette, .showRadialPalette),
            (.showInkAttributes, .showRadialPalette),
            (.showContextualPalette, .showRadialPalette),
            (.runSystemShortcut, .none)
        ]

        for (preference, expected) in expectations {
            XCTAssertEqual(
                PencilSqueezeBehavior.response(for: preference, phase: .ended),
                expected
            )
        }
    }

    func testSqueezeWaitsForTheCompletedGestureBeforeTakingAction() {
        for phase in [UIPencilInteraction.Phase.began, .changed, .cancelled] {
            XCTAssertEqual(
                PencilSqueezeBehavior.response(for: .showContextualPalette, phase: phase),
                .none
            )
        }
    }

    func testRadialRingIsCenteredOnThePencilWithATightRadius() {
        let canvasSize = CGSize(width: 1_024, height: 768)

        let center = PencilRadialMenuLayout(size: canvasSize, requestedOrigin: CGPoint(x: 512, y: 650))
        let edge = PencilRadialMenuLayout(size: canvasSize, requestedOrigin: CGPoint(x: 12, y: 80))

        XCTAssertEqual(center.anchor, CGPoint(x: 512, y: 650))
        for index in 0..<6 {
            let offset = center.offset(itemAt: index, itemCount: 6)
            XCTAssertEqual(hypot(offset.width, offset.height), 80, accuracy: 0.001)
        }
        XCTAssertGreaterThanOrEqual(edge.anchor.x, 107)
        XCTAssertGreaterThanOrEqual(edge.anchor.y, 107)
        for index in 0..<6 {
            let position = edge.position(itemAt: index, itemCount: 6)
            XCTAssertTrue((27...(canvasSize.width - 27)).contains(position.x))
            XCTAssertTrue((27...(canvasSize.height - 27)).contains(position.y))
        }
    }

    func testSqueezeUsesTheLastLiveHoverPositionWhenItsPoseIsMissing() {
        let lastHover = CGPoint(x: 318, y: 406)

        XCTAssertEqual(
            PencilSqueezeBehavior.location(poseLocation: nil, lastHoverLocation: lastHover),
            lastHover
        )
        XCTAssertEqual(
            PencilSqueezeBehavior.location(
                poseLocation: CGPoint(x: 440, y: 520),
                lastHoverLocation: lastHover
            ),
            CGPoint(x: 440, y: 520)
        )
    }
}
