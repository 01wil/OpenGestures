// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
import Model
@testable import Actions

@Suite struct KeyboardTests {
    @Test func commandShiftT() {
        let f = Fake()
        f.runner().run(.keyboardShortcut(KeyCombo(key: "t", modifiers: [.command, .shift])))
        let flags = CGEventFlags([.maskCommand, .maskShift]).rawValue
        #expect(f.log == ["key.17.\(flags).down", "key.17.\(flags).up"])
    }

    @Test func allModifiersMap() {
        let f = Fake()
        f.runner().run(.keyboardShortcut(KeyCombo(key: "return", modifiers: [.command, .shift, .control, .option])))
        let flags = CGEventFlags([.maskCommand, .maskShift, .maskControl, .maskAlternate]).rawValue
        #expect(f.log.first == "key.36.\(flags).down")
    }

    @Test func namedKeysAndPunctuation() {
        #expect(KeyMap.keyCode(for: "f20", layout: { _ in nil }) == 90)
        #expect(KeyMap.keyCode(for: "pageDown", layout: { _ in nil }) == 121)
        #expect(KeyMap.keyCode(for: "[", layout: { _ in nil }) == 33)
        #expect(KeyMap.keyCode(for: "7", layout: { _ in nil }) == 26)
        #expect(KeyMap.keyCode(for: "forwardDelete", layout: { _ in nil }) == 117)
    }

    @Test func everyDocumentedNamedKeyResolves() {
        let names = ["return", "tab", "space", "escape", "delete", "forwardDelete", "left", "right", "up", "down",
                     "home", "end", "pageUp", "pageDown"] + (1...20).map { "f\($0)" }
        for n in names { #expect(KeyMap.keyCode(for: n, layout: { _ in nil }) != nil, "\(n)") }
    }

    @Test func userLayoutWinsOverAnsi() {
        // A layout where "s" lives on the ANSI "o" key.
        #expect(KeyMap.keyCode(for: "s", layout: { $0 == "s" ? 31 : nil }) == 31)
    }

    @Test func unknownKeyReportsErrorAndPostsNothing() {
        let f = Fake()
        f.runner().run(.keyboardShortcut(KeyCombo(key: "bogus")))
        #expect(f.log.isEmpty)
        #expect(f.errors == [.unknownKey("bogus")])
    }

    @MainActor @Test func liveLayoutFindsLetterA() {
        #expect(LiveKeyboardLayout.keyCode(for: "a") != nil)
    }
}

@Suite struct LaunchTests {
    @Test func openApp() { let f = Fake(); f.runner().run(.openApp(bundleID: "com.apple.Safari")); #expect(f.log == ["app com.apple.Safari"]) }

    @Test func openURL() {
        let f = Fake()
        f.runner().run(.openURL("https://example.com/a"))
        #expect(f.log == ["url https://example.com/a"])
    }

    @Test func invalidURLReported() {
        let f = Fake()
        f.runner().run(.openURL("not a url"))
        #expect(f.log.isEmpty)
        #expect(f.errors == [.invalidURL("not a url")])
    }

    @Test func openFileExpandsTilde() {
        let f = Fake()
        f.runner().run(.openFile(path: "~/notes.txt"))
        #expect(f.log == ["file \(NSHomeDirectory())/notes.txt"])
    }
}

@Suite struct ScriptTests {
    @Test func shell() {
        let f = Fake()
        f.runner().run(.shellScript("echo hi"))
        #expect(f.log == ["launch /bin/zsh -lc|echo hi 30"])
    }

    @Test func appleScript() {
        let f = Fake()
        f.runner().run(.appleScript("beep"))
        #expect(f.log == ["launch /usr/bin/osascript -e|beep 30"])
    }

    @Test func shortcut() {
        let f = Fake()
        f.runner().run(.shortcut(name: "My Shortcut"))
        #expect(f.log == ["launch /usr/bin/shortcuts run|My Shortcut 30"])
    }

    @Test func failureIsReported() {
        let f = Fake()
        f.launchResult = .scriptFailed("boom")
        f.runner().run(.shellScript("x"))
        #expect(f.errors == [.scriptFailed("boom")])
    }

    @Test func liveLauncherReportsStderrAndExitStatus() async {
        let err = await withCheckedContinuation { c in
            ProcessLauncher().launch("/bin/sh", arguments: ["-c", "echo oops >&2; exit 3"], timeout: 5) { c.resume(returning: $0) }
        }
        #expect(err == .scriptFailed("oops"))
    }

    @Test func liveLauncherSuccess() async {
        let err = await withCheckedContinuation { c in
            ProcessLauncher().launch("/usr/bin/true", arguments: [], timeout: 5) { c.resume(returning: $0) }
        }
        #expect(err == nil)
    }

    @Test func liveLauncherTimesOut() async {
        let err = await withCheckedContinuation { c in
            ProcessLauncher().launch("/bin/sleep", arguments: ["10"], timeout: 0.2) { c.resume(returning: $0) }
        }
        #expect(err == .timedOut)
    }

    @Test func liveLauncherMissingExecutable() async {
        let err = await withCheckedContinuation { c in
            ProcessLauncher().launch("/nonexistent/tool", arguments: [], timeout: 5) { c.resume(returning: $0) }
        }
        guard case .launchFailed = err else { Issue.record("got \(String(describing: err))"); return }
    }
}

@Suite struct SystemKeyTests {
    @Test(arguments: [
        (SystemKey.volumeUp, Int32(0)), (.volumeDown, 1), (.brightnessUp, 2), (.brightnessDown, 3),
        (.mute, 7), (.playPause, 16), (.nextTrack, 17), (.previousTrack, 18),
    ])
    func mediaKeys(key: SystemKey, code: Int32) {
        let f = Fake()
        f.runner().run(.systemKey(key))
        #expect(f.log == ["media.\(code).down", "media.\(code).up"])
    }

    @Test func missionControlOpensItsApp() {
        let f = Fake()
        f.runner().run(.systemKey(.missionControl))
        #expect(f.log == ["app com.apple.exposelauncher"])
    }

    @Test func appExposeIsControlDown() {
        let f = Fake()
        f.runner().run(.systemKey(.appExpose))
        #expect(f.log.first == "key.125.\(CGEventFlags.maskControl.rawValue).down")
    }

    @Test func launchpadAndShowDesktopUseDedicatedKeys() {
        let f = Fake()
        f.runner().run(.systemKey(.launchpad))
        f.runner().run(.systemKey(.showDesktop))
        #expect(f.log == ["key.131.0.down", "key.131.0.up", "key.103.0.down", "key.103.0.up"])
    }
}

@Suite struct MouseAndWindowTests {
    @Test(arguments: MouseButton.allCases)
    func click(button: MouseButton) {
        let f = Fake()
        f.runner().run(.mouseClick(button))
        #expect(f.log == ["mouse.\(button.rawValue).down", "mouse.\(button.rawValue).up"])
    }

    @Test func windowActionsDelegate() {
        let f = Fake()
        let r = f.runner()
        r.run(.previousWindow()); r.run(.nextWindow()); r.run(.previousDisplay); r.run(.nextDisplay)
        r.run(.cursorToNextDisplay); r.run(.windowLayout(.leftHalf))
        #expect(f.log == ["prevWindow", "nextWindow", "prevDisplay", "nextDisplay", "cursorNext", "layout.leftHalf"])
    }

    @Test func windowFailureIsReported() {
        struct Boom: WindowCommands {
            func focusPreviousWindow() throws { throw ActionError.failed("no ax") }
            func focusNextWindow() throws {}
            func moveFocusedWindowToPreviousDisplay() throws {}
            func moveFocusedWindowToNextDisplay() throws {}
            func apply(layout: WindowLayout) throws {}
            func moveCursorToNextDisplay() throws {}
        }
        let f = Fake()
        ActionRunner(windows: Boom(), events: f, processes: f, workspace: f, onError: { f.report($0) }).run(.previousWindow())
        #expect(f.errors == [.failed("no ax")])
    }

    @Test func adjustAsDiscreteActionIsAnError() {
        let f = Fake()
        f.runner().run(.adjust(.volume))
        #expect(f.errors == [.notDiscrete])
    }
}

@Suite struct AdjustTests {
    @Test func belowThresholdEmitsNothing() {
        let f = Fake()
        f.runner().adjust(.volume, delta: 0.05)
        #expect(f.log.isEmpty)
    }

    @Test func accumulatesAcrossCalls() {
        let f = Fake()
        let r = f.runner()
        r.adjust(.volume, delta: 0.04)
        r.adjust(.volume, delta: 0.04)
        #expect(f.log == ["media.0.down", "media.0.up"])
    }

    @Test func multipleStepsAndDirection() {
        let f = Fake()
        f.runner().adjust(.brightness, delta: -0.13)
        #expect(f.log == ["media.3.down", "media.3.up", "media.3.down", "media.3.up"])
    }

    @Test func remainderCarriesOver() {
        let f = Fake()
        let r = f.runner()
        r.adjust(.volume, delta: 0.07)
        r.adjust(.volume, delta: 0.05)
        #expect(f.log.count == 4)
    }

    @Test func targetsAreIndependent() {
        let f = Fake()
        let r = f.runner()
        r.adjust(.volume, delta: 0.04)
        r.adjust(.brightness, delta: 0.04)
        #expect(f.log.isEmpty)
    }
}
