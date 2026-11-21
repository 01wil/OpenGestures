// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import Recognizer

/// Contact noise shaped like the recorded fixtures: frames 8 ms apart, and a real finger passes through
/// states 1 and 3 before it touches (4) and through 5 and 7 after it lifts.
@Suite struct NoiseTests {
    /// One string per frame, one state digit per finger ("0" = absent); "" is an empty frame.
    static func frames(_ states: [String], at points: [(x: Double, y: Double)] = Synth.row(5)) -> [TouchFrame] {
        states.enumerated().map { i, s in
            let touches = zip(points.indices, s).compactMap { j, c -> Touch? in
                c == "0" ? nil : Touch(id: j + 1, x: Float(points[j].x), y: Float(points[j].y), state: c.wholeNumberValue!)
            }
            return TouchFrame(timestamp: Double(i) * 0.008, touches: touches)
        }
    }

    static let landing = ["1", "3"], lifting = ["5", "7", ""]
    static func held(_ n: Int, _ s: String = "4") -> [String] { Array(repeating: s, count: n) }

    @Test func lightestRecordedTapFires() {
        // tap.1__real-1795274648-1: touching for three frames only.
        #expect(recognize(Self.frames(Self.landing + Self.held(3) + Self.lifting)) == [GestureEvent(.tap(fingers: 1))])
    }

    @Test func strayContactWhileLandingDoesNotRaiseFingerCount() {
        var frames = Synth.swipe(fingers: 4, direction: .left)
        frames[6].touches.append(Touch(id: 9, x: 0.1, y: 0.1))
        #expect(recognize(frames) == [GestureEvent(.swipe(fingers: 4, direction: .left))])
    }

    @Test(arguments: ["3", "5"])
    func singleFrameOutOfTouchDoesNotEndTheTap(state: String) {
        let frames = Self.frames(Self.landing + Self.held(5) + [state] + Self.held(5) + Self.lifting)
        #expect(recognize(frames) == [GestureEvent(.tap(fingers: 1))])
    }

    @Test func singleEmptyFrameDoesNotFireTwice() {
        let frames = Self.frames(Self.landing + Self.held(5) + [""] + Self.held(5) + Self.lifting)
        #expect(recognize(frames) == [GestureEvent(.tap(fingers: 1))])
    }

    @Test func lingeringHoverStillEndsTheTap() {
        #expect(recognize(Self.frames(Self.landing + Self.held(5) + Self.held(10, "3"))) == [GestureEvent(.tap(fingers: 1))])
    }

    @Test func contactGrowingIntoAPalmIsNoTap() {
        // none__real-1795274648-24: a resting palm touches at size 1.2 and passes `palmSize` 2 on its fourth frame.
        let sizes: [Float] = [0.4, 0.9, 1.2, 1.6, 1.9, 2.2] + Array(repeating: 3, count: 30)
        var frames = sizes.enumerated().map { i, size in
            TouchFrame(timestamp: Double(i) * 0.008, touches: [Touch(id: 1, x: 0.78, y: 0.27, size: size, state: i < 2 ? i * 2 + 1 : 4)])
        }
        frames.append(TouchFrame(timestamp: Double(sizes.count) * 0.008, touches: []))
        #expect(recognize(frames).isEmpty)
    }

    @Test func sixFingerTapCountsAsFive() {
        #expect(recognize(Synth.tap(fingers: 6)) == [GestureEvent(.tap(fingers: 5))])
    }

    @Test func sixFingerSwipeCountsAsFive() {
        #expect(recognize(Synth.swipe(fingers: 6, direction: .left)) == [GestureEvent(.swipe(fingers: 5, direction: .left))])
    }
}
