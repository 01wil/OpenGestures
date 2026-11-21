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

/// Real 4-finger swipes on a laptop trackpad, 120 Hz: fingers land staggered, the swipe fires and the fingers keep
/// going, and the sensor is noisy while they do. The follow must outlive all of that and end only when the hand lifts.
@Suite struct RealisticFollowTests {
    let follow = Tuning(followsSwipes: true)
    let left = Gesture.swipe(fingers: 4, direction: .left)

    /// `states(frame, finger)` overrides the touching state 4; nil drops the contact from that frame.
    func hand(frames n: Int, extra: (Int) -> [Touch] = { _ in [] }, states: (Int, Int) -> Int? = { _, _ in 4 }) -> [TouchFrame] {
        (0..<n).map { i in
            let t = Double(i) / 120
            // Fingers land 8 ms apart (the fourth one 25 ms late), then sweep left 0.6 units/s for the whole stroke.
            let touches = (1...4).compactMap { id -> Touch? in
                guard t >= Double(id - 1) * (id == 4 ? 0.025 / 3 : 0.008), let state = states(i, id) else { return nil }
                return Touch(id: id, x: Float(0.35 + 0.08 * Double(id) - 0.6 * max(t - 0.04, 0)), y: 0.45,
                             size: 0.4 + 0.1 * Float(id), state: state)
            }
            return TouchFrame(timestamp: t, touches: touches + extra(i))
        }
    }

    func ends(_ events: [GestureEvent]) -> [GestureEvent] { events.filter { $0.phase == .ended } }

    /// Every frame after the swipe fired is noisy in a different way; only the final lift (states 5, then 7, then
    /// no contacts) may end the follow.
    @Test func noisyFingersAfterTheSwipeKeepTheFollowAlive() {
        let n = 60
        var frames = hand(frames: n, extra: { i in
            // A thumb grazes the pad for three frames: five contacts.
            (30...32).contains(i) ? [Touch(id: 9, x: 0.3, y: 0.1, size: 0.9)] : []
        }, states: { i, id in
            switch i {
            case 24 where id == 2: 5                  // one finger dips to "lifting" for a frame
            case 27 where id == 3: 3                  // one to "make touch": three touching
            case 36, 37: 5                            // the whole hand lightens for two frames
            case 42: id == 1 ? nil : 6                // one contact missing, the rest lingering
            default: 4
            }
        })
        let t = frames.last!.timestamp
        frames += [TouchFrame(timestamp: t + 1 / 120, touches: frames.last!.touches.map { var c = $0; c.state = 5; return c }),
                   TouchFrame(timestamp: t + 2 / 120, touches: frames.last!.touches.map { var c = $0; c.state = 7; return c }),
                   TouchFrame(timestamp: t + 3 / 120, touches: [])]
        let r = GestureRecognizer(tuning: follow)
        var endedAt: Int?
        var began = 0
        for (i, frame) in frames.enumerated() {
            for e in r.process(frame) {
                if e.phase == .began { began += 1; #expect(e == GestureEvent(left)) }
                if e.phase == .ended, endedAt == nil { endedAt = i }
            }
        }
        #expect(began == 1)
        #expect(endedAt == frames.count - 1)
    }

    /// Contacts that hover above the pad without touching do not hold the switcher open for ever.
    @Test func hoveringWithoutTouchingEndsAfterAGracePeriod() {
        let frames = hand(frames: 120, states: { i, _ in i < 40 ? 4 : 3 })
        let events = recognize(frames, tuning: follow)
        #expect(events.first == GestureEvent(left))
        #expect(ends(events).count == 1)
    }

    @Test func liftingEndsTheFollowAtOnce() {
        let frames = hand(frames: 40) + [TouchFrame(timestamp: 40.0 / 120, touches: [])]
        #expect(recognize(frames, tuning: follow).last == GestureEvent(left, phase: .ended))
    }
}
