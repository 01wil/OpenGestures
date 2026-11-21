// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import Actions

@Suite struct KeyFlagsTests {
    private let fnPad: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]

    @Test func arrowsGetSecondaryFnAndNumericPad() {
        for code: CGKeyCode in 123...126 {
            #expect(SystemEventPoster.keyFlags(keyCode: code, flags: .maskControl, existing: []) == [.maskControl, .maskSecondaryFn, .maskNumericPad])
        }
    }

    @Test func functionAndNavigationKeysGetSecondaryFn() {
        for code: CGKeyCode in [103, 111, 115, 116, 117, 119, 121] {
            #expect(SystemEventPoster.keyFlags(keyCode: code, flags: [], existing: []) == .maskSecondaryFn)
        }
    }

    @Test func ordinaryKeysKeepOnlyComboFlags() {
        #expect(SystemEventPoster.keyFlags(keyCode: 0, flags: .maskCommand, existing: []) == .maskCommand)
    }

    @Test func existingEventBitsSurviveAndOtherExistingBitsAreDropped() {
        let existing: CGEventFlags = [.maskNumericPad, .maskShift]
        #expect(SystemEventPoster.keyFlags(keyCode: 0, flags: .maskCommand, existing: existing) == [.maskCommand, .maskNumericPad])
    }
}
