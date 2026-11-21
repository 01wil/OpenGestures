// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Model

/// Executes `Model.Action` values. Never throws: failures go to `onError`. Call from the main thread
/// (the keyboard-layout lookup requires it); scripts run out of process and never block the caller.
public final class ActionRunner: @unchecked Sendable {
    static let scriptTimeout: TimeInterval = 30
    /// Normalised delta per volume/brightness step.
    static let adjustStep = 0.06

    private let windows: WindowCommands
    private let events: EventPosting
    private let processes: ProcessLaunching
    private let workspace: WorkspaceOpening
    private let keyCodeForCharacter: @Sendable (Character) -> CGKeyCode?
    private let onError: @Sendable (ActionError) -> Void
    private let lock = NSLock()
    private var accumulated: [AdjustTarget: Double] = [:]

    public init(windows: WindowCommands, events: EventPosting = SystemEventPoster(),
                processes: ProcessLaunching = ProcessLauncher(), workspace: WorkspaceOpening = SystemWorkspace(),
                keyCodeForCharacter: (@Sendable (Character) -> CGKeyCode?)? = nil,
                onError: @escaping @Sendable (ActionError) -> Void = { _ in }) {
        self.windows = windows
        self.events = events
        self.processes = processes
        self.workspace = workspace
        self.keyCodeForCharacter = keyCodeForCharacter ?? { LiveKeyboardLayout.keyCode(for: $0) }
        self.onError = onError
    }

    public func run(_ action: Action) {
        do {
            switch action {
            case let .keyboardShortcut(combo):
                guard let code = KeyMap.keyCode(for: combo.key, layout: keyCodeForCharacter) else {
                    throw ActionError.unknownKey(combo.key)
                }
                tap(code, flags: Self.flags(combo.modifiers))
            case let .openApp(bundleID): try workspace.openApp(bundleID: bundleID)
            case let .openURL(string):
                guard let url = URL(string: string), url.scheme != nil else { throw ActionError.invalidURL(string) }
                try workspace.open(url: url)
            case let .openFile(path):
                try workspace.openFile(at: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            case let .shellScript(script): launch("/bin/zsh", ["-lc", script])
            case let .appleScript(script): launch("/usr/bin/osascript", ["-e", script])
            case let .shortcut(name): launch("/usr/bin/shortcuts", ["run", "--", name])
            case let .systemKey(key): try system(key)
            case let .mouseClick(button):
                events.postMouse(button, down: true)
                events.postMouse(button, down: false)
            case .previousWindow: try windows.focusPreviousWindow()
            case .nextWindow: try windows.focusNextWindow()
            case .previousDisplay: try windows.moveFocusedWindowToPreviousDisplay()
            case .nextDisplay: try windows.moveFocusedWindowToNextDisplay()
            case .cursorToNextDisplay: try windows.moveCursorToNextDisplay()
            case let .windowLayout(layout): try windows.apply(layout: layout)
            case .adjust: throw ActionError.notDiscrete
            }
        } catch {
            onError(error as? ActionError ?? .failed(error.localizedDescription))
        }
    }

    /// Continuous gestures: one step per `adjustStep` of accumulated movement, sign = direction.
    public func adjust(_ target: AdjustTarget, delta: Double) {
        guard delta.isFinite else { return }
        let steps: Int = lock.withLock {
            var total = (accumulated[target] ?? 0) + delta
            let whole = Int(total / Self.adjustStep)
            total -= Double(whole) * Self.adjustStep
            accumulated[target] = total
            return whole
        }
        let key: Int32 = switch target {
        case .volume: steps > 0 ? Media.soundUp : Media.soundDown
        case .brightness: steps > 0 ? Media.brightnessUp : Media.brightnessDown
        }
        for _ in 0..<abs(steps) { mediaTap(key) }
    }

    // NX_KEYTYPE_* from IOKit/hidsystem/ev_keymap.h
    private enum Media {
        static let soundUp: Int32 = 0, soundDown: Int32 = 1, brightnessUp: Int32 = 2, brightnessDown: Int32 = 3
        static let mute: Int32 = 7, play: Int32 = 16, next: Int32 = 17, previous: Int32 = 18
    }

    /// Mission Control launches its own app (com.apple.exposelauncher): works whatever the user did to the
    /// Keyboard Shortcuts pane. App Exposé, Launchpad and Show Desktop have no launchable app, so they post
    /// the keys macOS itself sends for them: Ctrl-Down (the default shortcut, user-configurable), the
    /// Launchpad key (131) and F11 (103, "Show Desktop" default). Verify per macOS release.
    private func system(_ key: SystemKey) throws {
        switch key {
        case .playPause: mediaTap(Media.play)
        case .nextTrack: mediaTap(Media.next)
        case .previousTrack: mediaTap(Media.previous)
        case .volumeUp: mediaTap(Media.soundUp)
        case .volumeDown: mediaTap(Media.soundDown)
        case .mute: mediaTap(Media.mute)
        case .brightnessUp: mediaTap(Media.brightnessUp)
        case .brightnessDown: mediaTap(Media.brightnessDown)
        case .missionControl: try workspace.openApp(bundleID: "com.apple.exposelauncher")
        case .appExpose: tap(125, flags: .maskControl)
        case .launchpad: tap(131, flags: [])
        case .showDesktop: tap(103, flags: [])
        }
    }

    private func tap(_ code: CGKeyCode, flags: CGEventFlags) {
        events.postKey(keyCode: code, flags: flags, down: true)
        events.postKey(keyCode: code, flags: flags, down: false)
    }

    private func mediaTap(_ key: Int32) {
        events.postMediaKey(key, down: true)
        events.postMediaKey(key, down: false)
    }

    private func launch(_ executable: String, _ arguments: [String]) {
        processes.launch(executable, arguments: arguments, timeout: Self.scriptTimeout) { [onError] in
            if let error = $0 { onError(error) }
        }
    }

    private static func flags(_ m: Modifiers) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        return f
    }
}
