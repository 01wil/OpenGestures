// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import Model
@testable import Config

@Suite struct ValidationTests {
    let left = Gesture.swipe(fingers: 4, direction: .left)

    @Test func defaultConfigHasNoWarnings() {
        #expect(Validator.warnings(for: Configuration.default.bindings).isEmpty)
    }

    @Test func duplicateGlobalTriggersWarn() {
        let a = Binding(gesture: left, action: .previousWindow())
        let b = Binding(gesture: left, action: .nextWindow())
        let w = Validator.warnings(for: [a, b])
        #expect(w.count == 1)
        #expect(w.first?.kind == .duplicateTrigger)
        #expect(w.first?.bindingIDs == [a.id, b.id])
        #expect(w.first?.message.contains("swipe.4.left") == true)
    }

    @Test func differentModifiersAreNotDuplicates() {
        let a = Binding(gesture: left, action: .previousWindow())
        let b = Binding(gesture: left, modifiers: .command, action: .nextWindow())
        #expect(Validator.warnings(for: [a, b]).isEmpty)
    }

    @Test func appOverridingGlobalIsNotADuplicate() {
        let a = Binding(gesture: left, action: .previousWindow())
        let b = Binding(gesture: left, apps: ["x"], action: .nextWindow())
        #expect(Validator.warnings(for: [a, b]).isEmpty)
    }

    @Test func overlappingAppScopesWarn() {
        let a = Binding(gesture: left, apps: ["x", "y"], action: .previousWindow())
        let b = Binding(gesture: left, apps: ["y", "z"], action: .nextWindow())
        let c = Binding(gesture: left, apps: ["q"], action: .nextWindow())
        #expect(Validator.warnings(for: [a, b, c]).map(\.kind) == [.duplicateTrigger])
    }

    @Test func disabledBindingsDoNotDuplicate() {
        let a = Binding(gesture: left, action: .previousWindow())
        let b = Binding(gesture: left, action: .nextWindow(), enabled: false)
        #expect(Validator.warnings(for: [a, b]).isEmpty)
    }

    @Test func adjustNeedsContinuousGesture() {
        let bad = Binding(gesture: left, action: .adjust(.volume))
        let good = Binding(gesture: .edgeSlide(edge: .right), action: .adjust(.volume))
        #expect(Validator.warnings(for: [bad, good]).map(\.kind) == [.adjustOnDiscreteGesture])
        #expect(Validator.warnings(for: [bad]).first?.bindingIDs == [bad.id])
    }

    @Test func continuousGestureNeedsAdjust() {
        let bad = Binding(gesture: .edgeSlide(edge: .left), action: .nextWindow())
        #expect(Validator.warnings(for: [bad]).map(\.kind) == [.discreteActionOnContinuousGesture])
    }
}
