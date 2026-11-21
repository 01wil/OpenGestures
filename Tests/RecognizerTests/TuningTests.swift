// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import Recognizer

@Suite struct TuningTests {
    @Test func highSensitivityAcceptsShortSwipes() {
        let frames = Synth.swipe(fingers: 3, direction: .left, distance: 0.07)
        #expect(recognize(frames).isEmpty)
        #expect(recognize(frames, tuning: Tuning(sensitivity: 1)) == [GestureEvent(.swipe(fingers: 3, direction: .left))])
    }

    @Test func lowSensitivityNeedsLongerSwipes() {
        let frames = Synth.swipe(fingers: 3, direction: .left, distance: 0.15)
        #expect(recognize(frames) == [GestureEvent(.swipe(fingers: 3, direction: .left))])
        #expect(recognize(frames, tuning: Tuning(sensitivity: 0)).isEmpty)
    }

    @Test func palmSizeIsConfigurable() {
        let frames = Synth.render([Synth.palm(duration: 0.1)])
        #expect(recognize(frames, tuning: Tuning(palmSize: 10)) == [GestureEvent(.tap(fingers: 1))])
    }
}

@Suite struct LifecycleTests {
    @Test func liftingSomeFingersMidStrokeDoesNotRefire() {
        let move = Synth.linear(from: (0, 0), by: (0, 0.5), start: 0.05, duration: 0.4)
        let fingers = Synth.row(4).enumerated().map { i, p in
            Synth.Finger(id: i + 1, down: 0, up: i == 3 ? 0.2 : 0.5) { t in let d = move(t); return (p.x + d.x, p.y + d.y) }
        }
        #expect(recognize(Synth.render(fingers)) == [GestureEvent(.swipe(fingers: 4, direction: .up))])
    }

    @Test func resetForgetsTheCurrentStroke() {
        let tap = Synth.tap(fingers: 3)
        let r = GestureRecognizer()
        _ = tap.dropLast().flatMap { r.process($0) }
        r.reset()
        #expect(r.process(tap.last!).isEmpty)
        #expect(tap.flatMap { r.process($0) } == [GestureEvent(.tap(fingers: 3))])
    }
}
