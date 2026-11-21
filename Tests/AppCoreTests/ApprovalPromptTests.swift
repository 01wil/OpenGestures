// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Model
import Testing
@testable import AppCore

@Suite struct ApprovalPromptTests {
    func binding(_ gesture: Gesture, _ action: Action, modifiers: Modifiers = []) -> Binding {
        Binding(gesture: gesture, modifiers: modifiers, action: action)
    }

    @Test func listsEveryPendingBindingWithItsFullAction() {
        let text = ApprovalPrompt.details([
            binding(.swipe(fingers: 3, direction: .up), .shellScript("touch /tmp/x\nopen -a Safari"), modifiers: .command),
            binding(.tap(fingers: 2), .openURL("https://example.com/a")),
            binding(.tap(fingers: 3), .openFile(path: "/tmp/x/Safari.app")),
            binding(.tap(fingers: 4), .shortcut(name: "Morning")),
            binding(.tap(fingers: 5), .appleScript("display notification \"hi\"")),
        ])
        #expect(text.contains("⌘ 3-finger swipe up"))
        #expect(text.contains("touch /tmp/x\nopen -a Safari"))
        #expect(text.contains("https://example.com/a"))
        #expect(text.contains("/tmp/x/Safari.app"))
        #expect(text.contains("Morning"))
        #expect(text.contains("display notification"))
    }

    @Test func longScriptsAreCappedAndLongListsSummarised() {
        let long = String(repeating: "a", count: 2000)
        let one = ApprovalPrompt.details([binding(.tap(fingers: 2), .shellScript(long))])
        #expect(one.count < 600)
        #expect(one.contains("…"))
        let many = (1...12).map { binding(.tap(fingers: 2), .openURL("https://example.com/\($0)")) }
        let text = ApprovalPrompt.details(many)
        #expect(text.contains("https://example.com/8"))
        #expect(!text.contains("https://example.com/9"))
        #expect(text.contains("and 4 more"))
    }

    @Test func titleCountsTheActions() {
        #expect(ApprovalPrompt.title(count: 1) == "Allow 1 action from the config file?")
        #expect(ApprovalPrompt.title(count: 3) == "Allow 3 actions from the config file?")
    }
}
