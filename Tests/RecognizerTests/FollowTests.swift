// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import Recognizer

/// With `followsSwipes`, a swipe keeps reporting movement along its axis after it fired, until the fingers lift.
@Suite struct FollowTests {
    let follow = Tuning(followsSwipes: true)

    /// Four fingers: a quick swipe of `swipe`, then `more` and `back` along x at a calm pace, then lift.
    func stroke(swipe: Double, more: Double, back: Double, drop: Bool = false) -> [TouchFrame] {
        let fingers = Synth.row(4).enumerated().map { i, p in
            Synth.Finger(id: i + 1, down: 0, up: drop && i == 3 ? 0.4 : 0.85) { t in
                func k(_ a: Double, _ b: Double) -> Double { min(max((t - a) / (b - a), 0), 1) }
                return (p.x + swipe * k(0.1, 0.2) + more * k(0.2, 0.5) + back * k(0.5, 0.8), p.y)
            }
        }
        return Synth.render(fingers, jitter: 0)
    }

    func moves(_ events: [GestureEvent]) -> [Double] { events.filter { $0.phase == .changed }.compactMap(\.delta) }

    @Test func swipeThenKeepMovingThenReverseThenLift() {
        let events = recognize(stroke(swipe: -0.15, more: -0.15, back: 0.1), tuning: follow)
        let left = Gesture.swipe(fingers: 4, direction: .left)
        #expect(events.first == GestureEvent(left))
        #expect(events.last == GestureEvent(left, phase: .ended))
        #expect(events.dropFirst().dropLast().allSatisfy { $0.gesture == left && $0.phase == .changed })
        let deltas = moves(events)
        let firstPositive = deltas.firstIndex { $0 > 0 } ?? deltas.endIndex
        let forward = deltas[..<firstPositive], reverse = deltas[firstPositive...]
        #expect(forward.allSatisfy { $0 < 0 } && reverse.allSatisfy { $0 > 0 })
        #expect((-0.3 ... -0.15).contains(forward.reduce(0, +)))
        #expect(abs(reverse.reduce(0, +) - 0.1) < 1e-6)
    }

    @Test func liftingOneFingerDoesNotJump() {
        let deltas = moves(recognize(stroke(swipe: -0.15, more: -0.15, back: 0, drop: true), tuning: follow))
        #expect(deltas.allSatisfy { $0 < 0 && $0 > -0.02 })
    }

    @Test func verticalSwipeFollowsY() {
        let frames = Synth.swipe(fingers: 3, direction: .up, distance: 0.3, duration: 0.3)
        let events = recognize(frames, tuning: follow)
        #expect(events.first == GestureEvent(.swipe(fingers: 3, direction: .up)))
        #expect(moves(events).reduce(0, +) > 0.05)
        #expect(events.last?.phase == .ended)
    }

    @Test func offByDefault() {
        #expect(recognize(stroke(swipe: -0.15, more: -0.15, back: 0.1)) == [GestureEvent(.swipe(fingers: 4, direction: .left))])
    }

    @Test func tapsAreNotFollowed() {
        #expect(recognize(Synth.tap(fingers: 3), tuning: follow) == [GestureEvent(.tap(fingers: 3))])
    }
}
