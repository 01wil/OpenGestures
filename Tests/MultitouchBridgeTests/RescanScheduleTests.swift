// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import MultitouchBridge

@MainActor @Suite struct RescanScheduleTests {
    /// A manual clock: `after` queues, `fire` runs the oldest pending body.
    @MainActor final class Clock {
        var pending: [@MainActor () -> Void] = []
        var delays: [TimeInterval] = []
        func after(_ delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
            delays.append(delay); pending.append(body)
        }
        func fire() { if !pending.isEmpty { pending.removeFirst()() } }
        func fireAll() { while !pending.isEmpty { fire() } }
    }

    private func make(_ clock: Clock, results: [Bool]) -> (RescanSchedule, () -> Int) {
        var calls = 0
        let schedule = RescanSchedule(after: clock.after, rescan: {
            defer { calls += 1 }
            return calls < results.count ? results[calls] : false
        })
        return (schedule, { calls })
    }

    @Test func foundOnFirstTryStops() {
        let clock = Clock()
        let (s, calls) = make(clock, results: [true])
        s.begin()
        clock.fireAll()
        #expect(calls() == 1)
        #expect(clock.delays == [1])
    }

    @Test func retriesWithBackoffUntilADeviceIsFound() {
        let clock = Clock()
        let (s, calls) = make(clock, results: [false, false, true])
        s.begin()
        clock.fireAll()
        #expect(calls() == 3)
        #expect(clock.delays == [1, 2, 4])
    }

    @Test func givesUpAfterFiveTries() {
        let clock = Clock()
        let (s, calls) = make(clock, results: [])
        s.begin()
        clock.fireAll()
        #expect(calls() == 5)
        #expect(clock.delays == [1, 2, 4, 8, 16])
    }

    @Test func cancelStopsTheSeries() {
        let clock = Clock()
        let (s, calls) = make(clock, results: [])
        s.begin()
        clock.fire()
        s.cancel()
        clock.fireAll()
        #expect(calls() == 1)
    }

    @Test func beginAgainReplacesTheSeriesInProgress() {
        let clock = Clock()
        let (s, calls) = make(clock, results: [false, true])
        s.begin()
        clock.fire()  // try 1 fails, try 2 queued
        s.begin()     // e.g. a trackpad was plugged in
        clock.fireAll()
        #expect(calls() == 2)  // the stale try 2 did nothing, the new series found a device
        #expect(clock.delays == [1, 2, 1])
    }
}
