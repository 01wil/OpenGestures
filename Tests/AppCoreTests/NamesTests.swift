// SPDX-License-Identifier: GPL-3.0-or-later

import Actions
import Foundation
import Model
import Testing
@testable import AppCore

@Suite struct NamesTests {
    @Test func gestureTitles() {
        #expect(Gesture.swipe(fingers: 4, direction: .left).title == "4-finger swipe left")
        #expect(Gesture.tap(fingers: 1).title == "1-finger tap")
        #expect(Gesture.pinch(fingers: 2, direction: .pinchOut).title == "2-finger pinch out")
        #expect(Gesture.rotate(.counterClockwise).title == "Rotate counterclockwise")
        #expect(Gesture.tipTap(side: .right).title == "TipTap right")
        #expect(Gesture.edgeSwipe(edge: .top).title == "Swipe in from top edge")
        #expect(Gesture.cornerTap(corner: .bottomLeft).title == "Tap bottom-left corner")
        #expect(Gesture.edgeSlide(edge: .right).title == "Slide along right edge")
    }

    @Test(arguments: GestureDraft.allGestures)
    func everyGestureHasASymbol(gesture: Gesture) {
        #expect(!gesture.symbolName.isEmpty)
    }

    @Test func modifierSymbolsUseAppleOrder() {
        #expect(Modifiers([.command, .shift, .option, .control]).symbols == ["⌃", "⌥", "⇧", "⌘"])
        #expect(Modifiers().symbols.isEmpty)
    }

    @Test func keyComboDisplay() {
        #expect(KeyCombo(key: "t", modifiers: [.command, .shift]).display == "⇧⌘T")
        #expect(KeyCombo(key: "left", modifiers: .control).display == "⌃←")
        #expect(KeyCombo(key: "return").display == "↩")
        #expect(KeyCombo(key: "f5").display == "F5")
        #expect(KeyCombo(key: "space", modifiers: .option).display == "⌥Space")
    }

    @Test func actionSummaries() {
        #expect(Action.previousWindow.summary() == "Previous window")
        #expect(Action.nextDisplay.summary() == "Move window to next display")
        #expect(Action.windowLayout(.leftHalf).summary() == "Left half")
        #expect(Action.keyboardShortcut(KeyCombo(key: "t", modifiers: .command)).summary() == "Press ⌘T")
        #expect(Action.openApp(bundleID: "com.apple.Safari").summary(appName: { _ in "Safari" }) == "Open Safari")
        #expect(Action.openApp(bundleID: "com.x.y").summary() == "Open com.x.y")
        #expect(Action.openURL("https://example.com/a").summary() == "Open https://example.com/a")
        #expect(Action.openFile(path: "~/Notes/todo.md").summary() == "Open ~/Notes/todo.md")
        #expect(Action.shortcut(name: "Focus").summary() == "Run shortcut “Focus”")
        #expect(Action.systemKey(.playPause).summary() == "Play / Pause")
        #expect(Action.mouseClick(.right).summary() == "Right click")
        #expect(Action.adjust(.volume).summary() == "Adjust volume")
    }

    @Test func summariesShowFullFilePathAndURL() {
        let home = NSHomeDirectory()
        #expect(Action.openFile(path: home + "/Documents/a/b.sh").summary() == "Open ~/Documents/a/b.sh")
        #expect(Action.openFile(path: "/opt/tools/run.sh").summary() == "Open /opt/tools/run.sh")
        #expect(Action.openURL("https://evil.example.com/pay?x=1").summary() == "Open https://evil.example.com/pay?x=1")
    }

    @Test func errorKindsCarryNoContent() {
        #expect(ActionError.scriptFailed("secret").kind == "scriptFailed")
        #expect(ActionError.invalidURL("http://x").kind == "invalidURL")
        #expect(ActionError.timedOut.kind == "timedOut")
    }

    @Test(arguments: ActionKind.allCases)
    func kindRoundTripsThroughItsDefaultAction(kind: ActionKind) {
        #expect(kind.defaultAction.kind == kind)
        #expect(!kind.title.isEmpty)
    }

    @Test func everyGroupHasKinds() {
        for group in ActionGroup.allCases {
            #expect(!ActionKind.allCases.filter { $0.group == group }.isEmpty)
        }
    }
}

@Suite struct MessagesTests {
    @Test func actionErrorsReadAsSentences() {
        #expect(ActionError.unknownKey("ö").message == "Unknown key “ö” in a keyboard shortcut.")
        #expect(ActionError.appNotFound("com.x").message == "Can’t find the app “com.x”.")
        #expect(ActionError.failed("No other display.").message == "No other display.")
    }

    @Test func everyKindIsSavableOnceItsFieldIsFilled() {
        let filled: [ActionKind: Action] = [
            .keyboardShortcut: .keyboardShortcut(KeyCombo(key: "t", modifiers: .command)),
            .openApp: .openApp(bundleID: "com.apple.Safari"),
            .openURL: .openURL("https://example.com"),
            .openFile: .openFile(path: "~/Notes.txt"),
            .shellScript: .shellScript("say hi"),
            .appleScript: .appleScript("beep"),
            .shortcut: .shortcut(name: "Focus"),
        ]
        for kind in ActionKind.allCases {
            let action = filled[kind] ?? kind.defaultAction
            #expect(action.missingField == nil, "\(kind)")
        }
    }

    @Test func emptyRequiredFieldsExplainWhatIsMissing() {
        #expect(Action.keyboardShortcut(KeyCombo(key: "")).missingField == "Record a shortcut")
        #expect(Action.openApp(bundleID: "").missingField == "Choose an app")
        #expect(Action.openURL(" ").missingField == "Enter a URL")
        #expect(Action.openFile(path: "").missingField == "Choose a file")
        #expect(Action.shellScript("  ").missingField == "Enter a script")
        #expect(Action.appleScript("").missingField == "Enter a script")
        #expect(Action.shortcut(name: "").missingField == "Enter the shortcut’s name")
    }

    @Test func urlWithoutSchemeIsSavedAsHTTPS() {
        #expect(Action.openURL("example.com").missingField == nil)
        #expect(Action.openURL(" example.com/a ").normalized == .openURL("https://example.com/a"))
        #expect(Action.openURL("obsidian://open").normalized == .openURL("obsidian://open"))
        #expect(Action.openURL("not a url").missingField == "Enter a valid URL, e.g. https://example.com")
        #expect(Action.shortcut(name: " Focus ").normalized == .shortcut(name: "Focus"))
        #expect(Action.nextWindow.normalized == .nextWindow)
    }
}
