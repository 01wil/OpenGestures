// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import Recognizer

@Suite struct TipTapTests {
    /// Finger 1 rests at the centre; each tap is (land time, x offset from the resting finger, held for).
    static func frames(taps: [(at: Double, dx: Double, hold: Double)], restDrift: Double = 0) -> [TouchFrame] {
        let end = (taps.map { $0.at + $0.hold }.max() ?? 0) + 0.2
        let rest = Synth.Finger(id: 1, down: 0, up: end, path: Synth.linear(from: (0.5, 0.4), by: (restDrift, 0), start: 0, duration: end))
        let tappers = taps.enumerated().map { i, tap in
            Synth.Finger(id: i + 2, down: tap.at, up: tap.at + tap.hold, path: { _ in (0.5 + tap.dx, 0.42) })
        }
        return Synth.render([rest] + tappers)
    }

    @Test(arguments: [(-0.12, Gesture.Side.left), (0.12, .right)])
    func fires(dx: Double, side: Gesture.Side) {
        #expect(recognize(Self.frames(taps: [(0.3, dx, 0.1)])) == [GestureEvent(.tipTap(side: side))])
    }

    @Test func repeatsWhileTheFingerRests() {
        let events = recognize(Self.frames(taps: [(0.3, 0.12, 0.1), (0.6, -0.12, 0.1)]))
        #expect(events == [GestureEvent(.tipTap(side: .right)), GestureEvent(.tipTap(side: .left))])
    }

    @Test func restTooShortIsIgnored() {
        #expect(recognize(Self.frames(taps: [(0.06, 0.12, 0.1)])).isEmpty)
    }

    @Test func tapHeldTooLongIsIgnored() {
        #expect(recognize(Self.frames(taps: [(0.3, 0.12, 0.5)])).isEmpty)
    }

    @Test func movingRestFingerIsIgnored() {
        #expect(recognize(Self.frames(taps: [(0.3, 0.12, 0.1)], restDrift: 0.2)).isEmpty)
    }
}
