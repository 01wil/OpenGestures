// SPDX-License-Identifier: GPL-3.0-or-later

import Actions
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
        #expect(Action.openURL("https://example.com/a").summary() == "Open example.com")
        #expect(Action.openFile(path: "~/Notes/todo.md").summary() == "Open todo.md")
        #expect(Action.shortcut(name: "Focus").summary() == "Run shortcut “Focus”")
        #expect(Action.systemKey(.playPause).summary() == "Play / Pause")
        #expect(Action.mouseClick(.right).summary() == "Right click")
        #expect(Action.adjust(.volume).summary() == "Adjust volume")
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

    @Test func incompleteActionsCannotBeSaved() {
        #expect(!Action.openApp(bundleID: "").isComplete)
        #expect(!Action.keyboardShortcut(KeyCombo(key: "")).isComplete)
        #expect(!Action.shellScript("  ").isComplete)
        #expect(Action.openURL("https://example.com").isComplete)
        #expect(!Action.openURL("example").isComplete)
        #expect(Action.nextWindow.isComplete)
    }
}
