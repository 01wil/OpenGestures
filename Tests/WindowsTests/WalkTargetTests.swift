// SPDX-License-Identifier: GPL-3.0-or-later
import Testing
@testable import Windows

@Suite struct WalkTargetTests {
    @Test func visibleWindowIsAWalkTarget() {
        #expect(WindowTracker.canBeShown(onScreen: true, axState: .minimised, appHidden: false))
        #expect(WindowTracker.canBeShown(onScreen: true, axState: .normal, appHidden: false))
    }

    @Test func minimisedWindowIsAWalkTarget() {
        #expect(WindowTracker.canBeShown(onScreen: false, axState: .minimised, appHidden: false))
    }

    @Test func otherSpaceWindowIsAWalkTarget() {
        #expect(WindowTracker.canBeShown(onScreen: false, axState: .unlisted, appHidden: false))
    }

    @Test func hiddenAppWindowIsAWalkTarget() {
        #expect(WindowTracker.canBeShown(onScreen: false, axState: .normal, appHidden: true))
    }

    @Test func orderedOutWindowIsNot() {
        #expect(!WindowTracker.canBeShown(onScreen: false, axState: .normal, appHidden: false))
    }
}
