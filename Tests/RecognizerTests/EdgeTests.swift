// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import Recognizer

@Suite struct EdgeTests {
    /// One finger starting `inset` from the middle of `edge`, moving `inward` towards the centre and `along` the edge
    /// (up for left/right, right for top/bottom).
    static func stroke(_ edge: Gesture.Edge, inset: Double = 0.02, inward: Double = 0, along: Double = 0) -> [TouchFrame] {
        let (start, move): ((x: Double, y: Double), (x: Double, y: Double)) = switch edge {
        case .left: ((inset, 0.5), (inward, along))
        case .right: ((1 - inset, 0.5), (-inward, along))
        case .bottom: ((0.5, inset), (along, inward))
        case .top: ((0.5, 1 - inset), (along, -inward))
        }
        return Synth.render([Synth.Finger(id: 1, down: 0, up: 0.35, path: Synth.linear(from: start, by: move, start: 0.05, duration: 0.25))])
    }

    @Test(arguments: Gesture.Edge.allCases)
    func edgeSwipe(edge: Gesture.Edge) {
        #expect(recognize(Self.stroke(edge, inward: 0.25)) == [GestureEvent(.edgeSwipe(edge: edge))])
    }

    @Test func startingAwayFromTheEdgeIsIgnored() {
        #expect(recognize(Self.stroke(.left, inset: 0.12, inward: 0.25)).isEmpty)
    }

    @Test func tooShortIsIgnored() {
        #expect(recognize(Self.stroke(.bottom, inward: 0.04)).isEmpty)
    }

    @Test(arguments: Gesture.Edge.allCases, [0.3, -0.3])
    func edgeSlideReportsDeltas(edge: Gesture.Edge, along: Double) {
        let events = recognize(Self.stroke(edge, along: along))
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.gesture == .edgeSlide(edge: edge) })
        let total = events.compactMap(\.delta).reduce(0, +)
        #expect(abs(total - along) < 0.01)
    }

    @Test func tapOnAnEdgeIsAPlainTap() {
        #expect(recognize(Synth.tap(fingers: 1, at: [(0.02, 0.5)])) == [GestureEvent(.tap(fingers: 1))])
    }

    @Test func oneFingerMoveInTheMiddleIsIgnored() {
        let frames = Synth.render([Synth.Finger(id: 1, down: 0, up: 0.3, path: Synth.linear(from: (0.4, 0.4), by: (0.3, 0), start: 0.05, duration: 0.2))])
        #expect(recognize(frames).isEmpty)
    }
}
