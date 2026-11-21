// SPDX-License-Identifier: GPL-3.0-or-later

import Config
import Model
import Testing
@testable import AppCore

@Suite struct GestureDraftTests {
    @Test(arguments: GestureDraft.allGestures)
    func roundTrips(gesture: Gesture) {
        #expect(GestureDraft(gesture).gesture == gesture)
    }

    @Test func allGesturesCoversEveryKind() {
        #expect(GestureDraft.allGestures.count == 4 * 4 + 5 + 4 * 2 + 2 + 2 + 4 + 4 + 4)
    }

    @Test func switchingKindClampsFingers() {
        var d = GestureDraft(.tap(fingers: 1))
        d.kind = .swipe
        #expect(d.gesture == .swipe(fingers: 2, direction: .left))
    }
}

@Suite struct EditingTests {
    let a = Binding(gesture: .tap(fingers: 3), action: .nextWindow)
    let b = Binding(gesture: .tap(fingers: 4), apps: ["com.apple.Safari"], action: .previousWindow)
    let c = Binding(gesture: .tap(fingers: 5), apps: ["com.apple.Safari"], action: .nextDisplay)
    let d = Binding(gesture: .tap(fingers: 2), apps: ["com.apple.mail", "com.apple.Notes"], action: .nextDisplay)

    @Test func upsertReplacesOrAppends() {
        var config = Configuration(bindings: [a])
        var changed = a
        changed.action = .previousWindow
        config.upsert(changed)
        #expect(config.bindings == [changed])
        config.upsert(b)
        #expect(config.bindings == [changed, b])
    }

    @Test func removeAndToggle() {
        var config = Configuration(bindings: [a, b])
        config.setEnabled(false, id: b.id)
        #expect(config.bindings[1].enabled == false)
        config.remove(id: a.id)
        #expect(config.bindings.map(\.id) == [b.id])
    }

    @Test func groupsGlobalFirstThenAppsInOrder() {
        let groups = BindingGroup.groups([b, d, a, c])
        #expect(groups.map(\.apps) == [[], ["com.apple.Safari"], ["com.apple.Notes", "com.apple.mail"]])
        #expect(groups.map { $0.bindings.map(\.id) } == [[a.id], [b.id, c.id], [d.id]])
    }

    @Test func noGlobalGroupWhenEmpty() {
        #expect(BindingGroup.groups([b]).map(\.apps) == [["com.apple.Safari"]])
        #expect(BindingGroup.groups([]).isEmpty)
    }
}

@Suite struct KeyRecordingTests {
    @Test func buildsComboFromKeyEvent() {
        #expect(KeyCombo(keyCode: 17, characters: "t", modifiers: .command) == KeyCombo(key: "t", modifiers: .command))
        #expect(KeyCombo(keyCode: 123, characters: "\u{F702}", modifiers: []) == KeyCombo(key: "left"))
        #expect(KeyCombo(keyCode: 36, characters: "\r", modifiers: .shift) == KeyCombo(key: "return", modifiers: .shift))
        #expect(KeyCombo(keyCode: 999, characters: "", modifiers: []) == nil)
    }
}
