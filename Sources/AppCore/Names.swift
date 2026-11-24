// SPDX-License-Identifier: GPL-3.0-or-later

import Actions
import Foundation
import Model

extension Gesture {
    public var title: String {
        switch self {
        case let .swipe(n, d): "\(n)-finger swipe \(d.rawValue)"
        case let .tap(n): "\(n)-finger tap"
        case let .pinch(n, d): "\(n)-finger pinch \(d.rawValue)"
        case let .rotate(r): r == .clockwise ? "Rotate clockwise" : "Rotate counterclockwise"
        case let .tipTap(s): "TipTap \(s.rawValue)"
        case let .edgeSwipe(e): "Swipe in from \(e.rawValue) edge"
        case let .cornerTap(c): "Tap \(c.title) corner"
        case let .edgeSlide(e): "Slide along \(e.rawValue) edge"
        case let .forceClick(n): "\(n)-finger force click"
        }
    }

    public var symbolName: String {
        switch self {
        case let .swipe(_, d): "arrow.\(d.rawValue)"
        case .tap: "hand.tap"
        case let .pinch(_, d): d == .pinchIn ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        case let .rotate(r): r == .clockwise ? "arrow.clockwise" : "arrow.counterclockwise"
        case .tipTap: "hand.point.up.left"
        case let .edgeSwipe(e): "rectangle.\(e.rawValue)half.inset.filled"
        case let .cornerTap(c): "rectangle.inset.\(c.rawValue).filled"
        case let .edgeSlide(e): e == .left || e == .right ? "slider.vertical.3" : "slider.horizontal.3"
        case .forceClick: "hand.tap.fill"
        }
    }
}

extension Gesture.Corner {
    public var title: String {
        switch self {
        case .topLeft: "top-left"
        case .topRight: "top-right"
        case .bottomLeft: "bottom-left"
        case .bottomRight: "bottom-right"
        }
    }
}

extension Modifiers {
    /// Menu order: Control, Option, Shift, Command.
    public static let ordered: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]

    public var symbols: [String] { Self.ordered.filter { contains($0.0) }.map(\.1) }
}

extension KeyCombo {
    private static let keySymbols: [String: String] = [
        "return": "↩", "tab": "⇥", "space": "Space", "escape": "⎋", "delete": "⌫", "forwarddelete": "⌦",
        "left": "←", "right": "→", "up": "↑", "down": "↓", "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]

    public var display: String {
        let k = key.lowercased()
        let name = Self.keySymbols[k] ?? (k.count > 1 ? k.uppercased() : key.uppercased())
        return modifiers.symbols.joined() + name
    }

    /// From a key-down event; nil when the key cannot be written to the config file.
    public init?(keyCode: UInt16, characters: String, modifiers: Modifiers) {
        if let name = KeyMap.named.first(where: { $0.value == keyCode })?.key {
            self.init(key: name, modifiers: modifiers)
        } else if characters.count == 1, let ch = characters.first, ch.isASCII, !ch.isWhitespace, !ch.isNewline {
            self.init(key: characters.lowercased(), modifiers: modifiers)
        } else {
            return nil
        }
    }
}

public enum ActionGroup: String, CaseIterable, Sendable {
    case windows, keyboard, appsAndFiles, scripts, mediaAndSystem, mouse

    public var title: String {
        switch self {
        case .windows: "Windows"
        case .keyboard: "Keyboard"
        case .appsAndFiles: "Apps & files"
        case .scripts: "Scripts & Shortcuts"
        case .mediaAndSystem: "Media & system"
        case .mouse: "Mouse"
        }
    }
}

/// Action cases without their payload, for pickers.
public enum ActionKind: String, CaseIterable, Sendable {
    case previousWindow, nextWindow, previousDisplay, nextDisplay, windowLayout
    case keyboardShortcut
    case openApp, openURL, openFile
    case shellScript, appleScript, shortcut
    case systemKey, adjust
    case mouseClick, cursorToNextDisplay

    public var group: ActionGroup {
        switch self {
        case .previousWindow, .nextWindow, .previousDisplay, .nextDisplay, .windowLayout: .windows
        case .keyboardShortcut: .keyboard
        case .openApp, .openURL, .openFile: .appsAndFiles
        case .shellScript, .appleScript, .shortcut: .scripts
        case .systemKey, .adjust: .mediaAndSystem
        case .mouseClick, .cursorToNextDisplay: .mouse
        }
    }

    public var title: String {
        switch self {
        case .previousWindow: "Previous window"
        case .nextWindow: "Next window"
        case .previousDisplay: "Move window to previous display"
        case .nextDisplay: "Move window to next display"
        case .windowLayout: "Window layout"
        case .keyboardShortcut: "Keyboard shortcut"
        case .openApp: "Open app"
        case .openURL: "Open URL"
        case .openFile: "Open file"
        case .shellScript: "Shell script"
        case .appleScript: "AppleScript"
        case .shortcut: "Shortcut"
        case .systemKey: "Media or system key"
        case .adjust: "Volume or brightness (slide)"
        case .mouseClick: "Click"
        case .cursorToNextDisplay: "Move pointer to next display"
        }
    }

    public var defaultAction: Action {
        switch self {
        case .previousWindow: .previousWindow
        case .nextWindow: .nextWindow
        case .previousDisplay: .previousDisplay
        case .nextDisplay: .nextDisplay
        case .windowLayout: .windowLayout(.maximize)
        case .keyboardShortcut: .keyboardShortcut(KeyCombo(key: ""))
        case .openApp: .openApp(bundleID: "")
        case .openURL: .openURL("")
        case .openFile: .openFile(path: "")
        case .shellScript: .shellScript("")
        case .appleScript: .appleScript("")
        case .shortcut: .shortcut(name: "")
        case .systemKey: .systemKey(.playPause)
        case .adjust: .adjust(.volume)
        case .mouseClick: .mouseClick(.left)
        case .cursorToNextDisplay: .cursorToNextDisplay
        }
    }
}

extension Action {
    public var kind: ActionKind {
        switch self {
        case .keyboardShortcut: .keyboardShortcut
        case .openApp: .openApp
        case .openURL: .openURL
        case .openFile: .openFile
        case .shellScript: .shellScript
        case .appleScript: .appleScript
        case .shortcut: .shortcut
        case .systemKey: .systemKey
        case .mouseClick: .mouseClick
        case .previousWindow: .previousWindow
        case .nextWindow: .nextWindow
        case .previousDisplay: .previousDisplay
        case .nextDisplay: .nextDisplay
        case .cursorToNextDisplay: .cursorToNextDisplay
        case .windowLayout: .windowLayout
        case .adjust: .adjust
        }
    }

    /// One line for a binding row. `appName` turns a bundle identifier into a display name.
    public func summary(appName: (String) -> String? = { _ in nil }) -> String {
        switch self {
        case let .keyboardShortcut(k): "Press \(k.display)"
        case let .openApp(id): "Open \(appName(id) ?? id)"
        case let .openURL(s): "Open \(s)"
        case let .openFile(p): "Open \((p as NSString).abbreviatingWithTildeInPath)"
        case .shellScript: "Run shell script"
        case .appleScript: "Run AppleScript"
        case let .shortcut(name): "Run shortcut “\(name)”"
        case let .systemKey(k): k.title
        case let .mouseClick(b): "\(b.rawValue.capitalized) click"
        case let .windowLayout(l): l.title
        case let .adjust(t): "Adjust \(t.rawValue)"
        default: kind.title
        }
    }
}

extension SystemKey {
    public var title: String {
        switch self {
        case .playPause: "Play / Pause"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        case .brightnessUp: "Brightness up"
        case .brightnessDown: "Brightness down"
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .launchpad: "Launchpad"
        case .showDesktop: "Show desktop"
        }
    }
}

extension WindowLayout {
    public var title: String {
        switch self {
        case .maximize: "Maximize"
        case .center: "Center"
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .topHalf: "Top half"
        case .bottomHalf: "Bottom half"
        case .topLeft: "Top-left quarter"
        case .topRight: "Top-right quarter"
        case .bottomLeft: "Bottom-left quarter"
        case .bottomRight: "Bottom-right quarter"
        }
    }
}

extension ActionError {
    /// The case name alone: safe to log publicly, unlike `message`, which can quote scripts, URLs and stderr.
    public var kind: String {
        switch self {
        case .unknownKey: "unknownKey"
        case .invalidURL: "invalidURL"
        case .appNotFound: "appNotFound"
        case .scriptFailed: "scriptFailed"
        case .timedOut: "timedOut"
        case .launchFailed: "launchFailed"
        case .notDiscrete: "notDiscrete"
        case .failed: "failed"
        }
    }

    public var message: String {
        switch self {
        case let .unknownKey(k): "Unknown key “\(k)” in a keyboard shortcut."
        case let .invalidURL(s): "“\(s)” is not a valid URL."
        case let .appNotFound(id): "Can’t find the app “\(id)”."
        case let .scriptFailed(m): "A script failed: \(m)"
        case .timedOut: "A script ran too long and was stopped."
        case let .launchFailed(m): "Couldn’t start a script: \(m)"
        case .notDiscrete: "Adjusting a value needs a sliding gesture."
        case let .failed(m): m
        }
    }
}

extension Action {
    /// What the editor saves: text fields trimmed, and a URL typed without a scheme opened over https.
    public var normalized: Action {
        func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch self {
        case let .openURL(s):
            let s = trim(s)
            guard !s.isEmpty, URL(string: s)?.scheme == nil, !s.contains(where: \.isWhitespace) else { return .openURL(s) }
            return .openURL("https://" + s)
        case let .shortcut(n): return .shortcut(name: trim(n))
        case let .openApp(id): return .openApp(bundleID: trim(id))
        default: return self
        }
    }

    /// Why the editor cannot save this action yet, as an inline hint; nil when every required field is filled.
    public var missingField: String? {
        func empty(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch normalized {
        case let .keyboardShortcut(k): return empty(k.key) ? "Record a shortcut" : nil
        case let .openApp(id): return empty(id) ? "Choose an app" : nil
        case let .openURL(s):
            if s.isEmpty { return "Enter a URL" }
            return URL(string: s)?.scheme != nil && !s.contains(where: \.isWhitespace) ? nil : "Enter a valid URL, e.g. https://example.com"
        case let .openFile(p): return empty(p) ? "Choose a file" : nil
        case let .shellScript(s), let .appleScript(s): return empty(s) ? "Enter a script" : nil
        case let .shortcut(n): return empty(n) ? "Enter the shortcut’s name" : nil
        default: return nil
        }
    }
}
