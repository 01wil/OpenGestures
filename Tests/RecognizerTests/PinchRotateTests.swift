// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import Recognizer

@Suite struct PinchRotateTests {
    @Test(arguments: Gesture.pinchFingers, Gesture.PinchDirection.allCases)
    func pinch(fingers: Int, direction: Gesture.PinchDirection) {
        let frames = Synth.spread(fingers: fingers, scale: direction == .pinchIn ? 0.4 : 2)
        #expect(recognize(frames) == [GestureEvent(.pinch(fingers: fingers, direction: direction))])
    }

    @Test func smallPinchIsIgnored() {
        #expect(recognize(Synth.spread(fingers: 2, scale: 0.92)).isEmpty)
    }

    @Test(arguments: [(-0.9, Gesture.Rotation.clockwise), (0.9, .counterClockwise)])
    func rotate(turn: Double, rotation: Gesture.Rotation) {
        #expect(recognize(Synth.spread(fingers: 2, turn: turn)) == [GestureEvent(.rotate(rotation))])
    }

    @Test func smallRotationIsIgnored() {
        #expect(recognize(Synth.spread(fingers: 2, turn: 0.15)).isEmpty)
    }

    /// Thumb stays put while the index finger travels far towards it: the centroid moves a lot,
    /// but the spread shrinks first, so it is a pinch and not a swipe.
    @Test func oneSidedPinchIsNotASwipe() {
        let frames = Synth.render([
            Synth.Finger(id: 1, down: 0, up: 0.3, path: { _ in (0.35, 0.4) }),
            Synth.Finger(id: 2, down: 0.01, up: 0.3, path: Synth.linear(from: (0.65, 0.4), by: (-0.25, 0), start: 0.05, duration: 0.2)),
        ])
        #expect(recognize(frames) == [GestureEvent(.pinch(fingers: 2, direction: .pinchIn))])
    }
}
