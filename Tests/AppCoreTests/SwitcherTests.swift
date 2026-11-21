// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import AppCore

@Suite struct SwitcherTests {
    let windows = ["a", "b", "c", "d"]
    let step = Switcher<String>.stepDistance

    @Test func needsTwoWindows() {
        #expect(Switcher(items: ["a"], older: true) == nil)
        #expect(Switcher(items: [String](), older: false) == nil)
    }

    /// Before any further movement the selection is where the plain jump would land.
    @Test func startsAtThePlainJumpTarget() {
        #expect(Switcher(items: windows, older: true)?.selection == "b")
        #expect(Switcher(items: windows, older: false)?.selection == "d")
    }

    /// The selection after each move, or nil when it did not change.
    func walk(_ s: Switcher<String>?, _ moves: [Double]) -> [String?] {
        guard var s else { return [] }
        return moves.map { s.move($0) ? s.selection : nil }
    }

    /// Like pressing Tab again: every stretch of movement steps on, whichever way the fingers go, and wraps.
    @Test func everyStretchStepsOnInEitherDirection() {
        #expect(walk(Switcher(items: windows, older: true), [-step, step, -step]) == ["c", "d", "a"])
        #expect(walk(Switcher(items: windows, older: false), [step, -step]) == ["c", "b"])
    }

    @Test func oneLongMoveTakesSeveralSteps() {
        #expect(walk(Switcher(items: windows, older: true), [-2.5 * step]) == ["d"])
    }

    @Test func smallMovesInOneDirectionAddUp() {
        #expect(walk(Switcher(items: windows, older: true), [0.6 * step, 0.6 * step]) == [nil, "c"])
    }

    /// Movement smaller than a step, back and forth, never steps: a reversal starts a new stretch.
    @Test func jitterDoesNothing() {
        let jitter = Array(repeating: [0.6 * step, -0.6 * step], count: 20).flatMap { $0 }
        #expect(walk(Switcher(items: windows, older: true), [-step] + jitter + [-step]) == ["c"] + jitter.map { _ in nil } + ["d"])
    }
}
