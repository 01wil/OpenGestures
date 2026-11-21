// SPDX-License-Identifier: GPL-3.0-or-later
import Testing
@testable import Windows

@Suite struct WindowHistoryTests {
    func history(_ ids: [Int]) -> WindowHistory<Int> {
        var h = WindowHistory<Int>()
        for id in ids { h.activated(id, now: 0) }
        return h
    }

    @Test func activationOrderIsMostRecentFirst() {
        #expect(history([1, 2, 3]).order == [3, 2, 1])
        #expect(history([1, 2, 3, 1]).order == [1, 3, 2])
    }

    @Test func previousIsSecondMostRecent() {
        var h = history([1, 2, 3])
        #expect(h.previous(now: 10) == 2)
    }

    @Test func nextFromFreshStartIsLeastRecent() {
        var h = history([1, 2, 3])
        #expect(h.next(now: 10) == 1)
    }

    /// The switcher lists windows mid-flick: the walked-to window must already be first.
    /// The switcher lists windows mid-walk: the walked-to window must already be first.
    @Test func settleCommitsTheWalk() {
        var h = history([1, 2, 3, 4])   // order 4,3,2,1
        _ = h.previous(now: 10)
        _ = h.previous(now: 10.2)
        h.settle()
        #expect(h.order == [2, 4, 3, 1])
        #expect(h.previous(now: 10.3) == 4)
    }

    @Test func tooFewWindowsGivesNil() {
        var h = history([1])
        #expect(h.previous(now: 10) == nil)
        #expect(h.next(now: 10) == nil)
        var e = WindowHistory<Int>()
        #expect(e.previous(now: 0) == nil)
    }

    @Test func rapidPreviousWalksBackThroughHistory() {
        var h = history([1, 2, 3, 4])   // order 4,3,2,1
        #expect(h.previous(now: 10.0) == 3)
        h.activated(3, now: 10.05)      // our own focus change echoing back is ignored
        #expect(h.previous(now: 10.3) == 2)
        h.activated(2, now: 10.35)
        #expect(h.previous(now: 10.6) == 1)
        #expect(h.previous(now: 10.9) == 4)   // wraps
    }

    @Test func nextWalksBackTowardsNewestInsideSession() {
        var h = history([1, 2, 3, 4])
        #expect(h.previous(now: 10.0) == 3)
        #expect(h.previous(now: 10.2) == 2)
        #expect(h.next(now: 10.4) == 3)
        #expect(h.next(now: 10.6) == 4)
    }

    @Test func slowPreviousWalksTheWholeHistory() {
        var h = history([1, 2, 3, 4])       // order 4,3,2,1
        #expect(h.previous(now: 10) == 3)
        h.activated(3, now: 10.1)           // echo of our own focus change
        #expect(h.previous(now: 20) == 2)
        h.activated(2, now: 20.1)
        #expect(h.previous(now: 30) == 1)
        #expect(h.previous(now: 40) == 4)   // wraps
        #expect(h.previous(now: 50) == 3)
    }

    /// Apps often report a different window of theirs right after we raise one.
    @Test func strayActivationRightAfterAStepIsIgnored() {
        var h = history([1, 2, 3, 4])
        #expect(h.previous(now: 10) == 3)
        h.activated(9, now: 10.3)
        #expect(h.previous(now: 20) == 2)
    }

    @Test func slowNextCyclesThroughAllWindows() {
        var h = history([1, 2, 3])          // order 3,2,1
        #expect(h.next(now: 10) == 1)
        #expect(h.next(now: 20) == 2)
        #expect(h.next(now: 30) == 3)
    }

    @Test func nextUndoesPrevious() {
        var h = history([1, 2, 3, 4])       // order 4,3,2,1
        #expect(h.previous(now: 10) == 3)
        #expect(h.next(now: 20) == 4)
    }

    @Test func userActivationEndsTheWalkAndKeepsRecency() {
        var h = history([1, 2, 3])          // order 3,2,1
        #expect(h.previous(now: 10) == 2)
        h.activated(1, now: 11)             // the user picked a window themselves
        #expect(h.order == [1, 2, 3])
        #expect(h.previous(now: 12) == 2)   // back to where they came from
    }

    @Test func closedWindowsDropOut() {
        var h = history([1, 2, 3])
        h.retain(alive: [1, 3])
        #expect(h.order == [3, 1])
        #expect(h.previous(now: 10) == 1)
    }

    @Test func closingAnyWindowKeepsTheWalk() {
        var h = history([1, 2, 3, 4, 5])    // order 5,4,3,2,1
        #expect(h.previous(now: 10) == 4)
        h.retain(alive: [1, 2, 4, 5])       // 3 closed
        #expect(h.previous(now: 20) == 2)
        h.retain(alive: [1, 4, 5])          // 2, the current target, closed
        #expect(h.previous(now: 30) == 1)
    }

    @Test func historyIsCapped() {
        var h = WindowHistory<Int>(limit: 3)
        for id in 1...5 { h.activated(id, now: 0) }
        #expect(h.order == [5, 4, 3])
    }

    @Test func seedKeepsGivenOrderForUnseenWindows() {
        var h = WindowHistory<Int>()
        h.seed([9, 8, 7])
        #expect(h.order == [9, 8, 7])
        h.activated(7, now: 0)
        h.seed([1, 2])   // seeding never overrides known history, only appends unknown ids
        #expect(h.order == [7, 9, 8, 1, 2])
    }
}
