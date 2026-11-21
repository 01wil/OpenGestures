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
            binding(.tap(fingers: 5), .appleScript("display notification \"hi\"\tdone")),
            Binding(gesture: .tap(fingers: 1), apps: ["com.apple.Safari"], action: .openURL("https://example.com/b")),
        ])
        #expect(text.contains("⌘ 3-finger swipe up"))
        #expect(text.contains("touch /tmp/x\nopen -a Safari"))
        #expect(text.contains("https://example.com/a"))
        #expect(text.contains("/tmp/x/Safari.app"))
        #expect(text.contains("Morning"))
        #expect(text.contains("display notification \"hi\"\tdone"))
        #expect(text.contains("com.apple.Safari"))
    }

    @Test func longScriptsAndLongListsAreShownInFull() {
        let long = String(repeating: "a", count: 2000) + "END"
        let one = ApprovalPrompt.details([binding(.tap(fingers: 2), .shellScript(long))])
        #expect(one.contains(long))
        #expect(!one.contains("…"))
        let many = (1...12).map { binding(.tap(fingers: 2), .openURL("https://example.com/\($0)")) }
        let text = ApprovalPrompt.details(many)
        for n in 1...12 { #expect(text.contains("https://example.com/\(n)\n") || text.hasSuffix("https://example.com/\(n)")) }
        #expect(!text.contains("more"))
    }

    @Test func invisibleAndDirectionCharactersAreShownAsEscapes() {
        let hidden = "echo safe\u{202E}txt.sh\u{200B}\u{2066}\u{FEFF}\u{2060}\u{0007}\r"
        let text = ApprovalPrompt.details([
            binding(.tap(fingers: 2), .shellScript(hidden)),
            binding(.tap(fingers: 3), .openURL("https://example.com/\u{200F}x")),
            Binding(gesture: .tap(fingers: 4), apps: ["com.apple\u{202E}.Safari"], action: .shortcut(name: "a\u{2069}")),
        ])
        for escape in ["\\u{202E}", "\\u{200B}", "\\u{2066}", "\\u{FEFF}", "\\u{2060}", "\\u{0007}", "\\u{000D}", "\\u{200F}", "\\u{2069}"] {
            #expect(text.contains(escape), "missing \(escape)")
        }
        #expect(!text.unicodeScalars.contains { $0.properties.generalCategory == .format || ($0.properties.generalCategory == .control && $0 != "\n" && $0 != "\t") })
    }

    @Test func titleCountsTheActions() {
        #expect(ApprovalPrompt.title(count: 1) == "Allow 1 action from the config file?")
        #expect(ApprovalPrompt.title(count: 3) == "Allow 3 actions from the config file?")
    }
}
