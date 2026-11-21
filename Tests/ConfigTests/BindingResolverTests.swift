// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import Model
@testable import Config

@Suite struct BindingResolverTests {
    let left = Gesture.swipe(fingers: 4, direction: .left)

    func resolve(_ bindings: [Binding], _ gesture: Gesture, _ mods: Modifiers = [], app: String? = nil) -> Binding? {
        BindingResolver.resolve(bindings, gesture: gesture, modifiers: mods, app: app)
    }

    @Test func globalBindingMatches() {
        let b = Binding(gesture: left, action: .previousWindow())
        #expect(resolve([b], left, app: "com.x") == b)
    }

    @Test func nothingMatchesReturnsNil() {
        let b = Binding(gesture: left, action: .previousWindow())
        #expect(resolve([b], .tap(fingers: 3)) == nil)
        #expect(resolve([], left) == nil)
    }

    @Test func modifiersMustMatchExactly() {
        let plain = Binding(gesture: left, action: .previousWindow())
        let cmd = Binding(gesture: left, modifiers: .command, action: .previousDisplay)
        #expect(resolve([plain, cmd], left) == plain)
        #expect(resolve([plain, cmd], left, .command) == cmd)
        #expect(resolve([plain, cmd], left, [.command, .shift]) == nil)
        #expect(resolve([cmd], left) == nil)
    }

    @Test func disabledBindingsAreIgnored() {
        let off = Binding(gesture: left, action: .previousWindow(), enabled: false)
        #expect(resolve([off], left) == nil)
    }

    @Test func appBindingBeatsGlobalOnlyInThatApp() {
        let global = Binding(gesture: left, action: .previousWindow())
        let app = Binding(gesture: left, apps: ["com.apple.Safari", "com.google.Chrome"], action: .nextWindow())
        #expect(resolve([global, app], left, app: "com.google.Chrome") == app)
        #expect(resolve([app, global], left, app: "com.apple.Safari") == app)
        #expect(resolve([global, app], left, app: "com.apple.Notes") == global)
        #expect(resolve([global, app], left, app: nil) == global)
    }

    @Test func disabledAppBindingFallsBackToGlobal() {
        let global = Binding(gesture: left, action: .previousWindow())
        let app = Binding(gesture: left, apps: ["a"], action: .nextWindow(), enabled: false)
        #expect(resolve([global, app], left, app: "a") == global)
    }
}
