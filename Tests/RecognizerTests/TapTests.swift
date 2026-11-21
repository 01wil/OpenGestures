// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import Recognizer

@Suite struct TapTests {
    @Test(arguments: Gesture.tapFingers)
    func firesOnLift(fingers: Int) {
        #expect(recognize(Synth.tap(fingers: fingers)) == [GestureEvent(.tap(fingers: fingers))])
    }

    @Test func heldTooLongIsIgnored() {
        #expect(recognize(Synth.tap(fingers: 2, duration: 0.5)).isEmpty)
    }

    @Test func movingTooMuchIsIgnored() {
        #expect(recognize(Synth.tap(fingers: 2, drift: (0.06, 0))).isEmpty)
    }

    @Test func doubleTapFiresTwice() {
        let one = Synth.tap(fingers: 2)
        #expect(recognize(one.then(one)) == [GestureEvent(.tap(fingers: 2)), GestureEvent(.tap(fingers: 2))])
    }

    @Test func singleFrameContactIsNoise() {
        let frames = [TouchFrame(timestamp: 0, touches: [Touch(id: 1, x: 0.5, y: 0.5)]), TouchFrame(timestamp: 0.011, touches: [])]
        #expect(recognize(frames).isEmpty)
    }

    @Test func hoveringContactsAreIgnored() {
        let frames = Synth.tap(fingers: 2).map { f in
            TouchFrame(timestamp: f.timestamp, touches: f.touches.map { var t = $0; t.state = 3; return t })
        }
        #expect(recognize(frames).isEmpty)
    }

    @Test(arguments: Gesture.Corner.allCases)
    func cornerTapReplacesOneFingerTap(corner: Gesture.Corner) {
        #expect(recognize(Synth.tap(fingers: 1, at: [Synth.corner(corner)])) == [GestureEvent(.cornerTap(corner: corner))])
    }

    @Test func twoFingerTapInCornerIsAPlainTap() {
        let c = Synth.corner(.topRight, inset: 0.05)
        #expect(recognize(Synth.tap(fingers: 2, at: [c, (c.x - 0.04, c.y)])) == [GestureEvent(.tap(fingers: 2))])
    }
}

@Suite struct PalmTests {
    @Test func palmTouchAloneIsIgnored() {
        #expect(recognize(Synth.render([Synth.palm(duration: 0.1)])).isEmpty)
    }

    @Test func restingPalmDoesNotChangeFingerCount() {
        let frames = Synth.tap(fingers: 2, extra: [Synth.palm(duration: 0.4)])
        #expect(recognize(frames) == [GestureEvent(.tap(fingers: 2))])
    }

    @Test func swipeWithRestingPalm() {
        var frames = Synth.swipe(fingers: 4, direction: .left)
        let palm = Touch(id: 99, x: 0.2, y: 0.1, size: 4)
        for i in frames.indices where !frames[i].touches.isEmpty { frames[i].touches.append(palm) }
        #expect(recognize(frames) == [GestureEvent(.swipe(fingers: 4, direction: .left))])
    }
}
