// SPDX-License-Identifier: GPL-3.0-or-later

import Model
import Testing
@testable import AppCore

@Suite struct SwitcherTests {
    let windows = ["a", "b", "c", "d"]
    let step = Switcher<String>.stepDistance
    let left = Gesture.Direction.left, right = Gesture.Direction.right

    @Test func needsTwoWindows() {
        #expect(Switcher(items: ["a"], older: true, swipe: left) == nil)
        #expect(Switcher(items: [String](), older: false, swipe: right) == nil)
    }

    /// Before any further movement the selection is where the plain jump would land.
    @Test func startsAtThePlainJumpTarget() {
        #expect(Switcher(items: windows, older: true, swipe: left)?.selection == "b")
        #expect(Switcher(items: windows, older: false, swipe: right)?.selection == "d")
    }

    /// The selection after each move, or nil when it did not change.
    func walk(_ s: Switcher<String>?, _ moves: [Double]) -> [String?] {
        guard var s else { return [] }
        return moves.map { s.move($0) ? s.selection : nil }
    }

    @Test func continuingTheSwipeStepsFurtherAndWraps() {
        #expect(walk(Switcher(items: windows, older: true, swipe: left), [-step, -step, -step]) == ["c", "d", "a"])
        #expect(walk(Switcher(items: windows, older: false, swipe: right), [step]) == ["c"])
    }

    @Test func reversingStepsBackAndReturningToTheStartRestoresThePlainJump() {
        #expect(walk(Switcher(items: windows, older: true, swipe: left), [-step, step, step, step]) == ["c", "b", "a", "d"])
    }

    @Test func oneLongMoveTakesSeveralSteps() {
        #expect(walk(Switcher(items: windows, older: true, swipe: left), [-2.5 * step]) == ["d"])
    }

    /// Movement smaller than a step, back and forth, never flickers the selection.
    @Test func jitterDoesNothing() {
        let jitter = Array(repeating: [0.6 * step, -0.6 * step], count: 20).flatMap { $0 }
        #expect(walk(Switcher(items: windows, older: true, swipe: left), [-step] + jitter + [-step]) == ["c"] + jitter.map { _ in nil } + ["d"])
    }

    /// The strip runs so that older windows lie in the direction the fingers move to reach them.
    @Test func olderWindowsLieTowardsTheFingers() {
        #expect(Switcher(items: windows, older: true, swipe: left)?.olderToTheLeft == true)
        #expect(Switcher(items: windows, older: false, swipe: right)?.olderToTheLeft == true)
        #expect(Switcher(items: windows, older: true, swipe: right)?.olderToTheLeft == false)
        #expect(walk(Switcher(items: windows, older: true, swipe: right), [step]) == ["c"])
    }
}
