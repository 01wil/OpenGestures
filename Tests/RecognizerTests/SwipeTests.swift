// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import Recognizer

@Suite struct SwipeTests {
    @Test(arguments: Gesture.swipeFingers, Gesture.Direction.allCases)
    func firesOncePerStroke(fingers: Int, direction: Gesture.Direction) {
        let events = recognize(Synth.swipe(fingers: fingers, direction: direction))
        #expect(events == [GestureEvent(.swipe(fingers: fingers, direction: direction))])
    }

    @Test(arguments: [60.0, 120.0])
    func worksAtDifferentFrameRates(hz: Double) {
        let events = recognize(Synth.swipe(fingers: 4, direction: .left, hz: hz, seed: 7))
        #expect(events == [GestureEvent(.swipe(fingers: 4, direction: .left))])
    }

    @Test func tooShortIsIgnored() {
        #expect(recognize(Synth.swipe(fingers: 3, direction: .up, distance: 0.04)).isEmpty)
    }

    @Test func tooSlowIsIgnored() {
        #expect(recognize(Synth.swipe(fingers: 3, direction: .right, distance: 0.2, duration: 2)).isEmpty)
    }

    @Test func eachStrokeFiresSeparately() {
        let one = Synth.swipe(fingers: 4, direction: .right)
        let offset = (one.last?.timestamp ?? 0) + 0.1
        let two = Synth.swipe(fingers: 4, direction: .right).map { TouchFrame(timestamp: $0.timestamp + offset, touches: $0.touches) }
        #expect(recognize(one + two).count == 2)
    }

    @Test func diagonalWithoutDominantAxisIsIgnored() {
        let frames = Synth.render(Synth.row(3).enumerated().map { i, p in
            Synth.Finger(id: i + 1, down: 0, up: 0.3, path: Synth.linear(from: p, by: (0.15, 0.15), start: 0.05, duration: 0.2))
        })
        #expect(recognize(frames).isEmpty)
    }

    @Test func flickeringFingerDoesNotBreakFastSwipe() {
        let frames = Synth.swipe(fingers: 4, direction: .left, distance: 0.3, duration: 0.2).enumerated().map { i, f in
            i % 5 == 4 ? TouchFrame(timestamp: f.timestamp, touches: f.touches.filter { $0.id != 2 }) : f
        }
        #expect(recognize(frames) == [GestureEvent(.swipe(fingers: 4, direction: .left))])
    }
}
