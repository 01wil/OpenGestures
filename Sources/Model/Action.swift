// SPDX-License-Identifier: GPL-3.0-or-later

/// A key plus modifiers, e.g. Cmd-Shift-T. `key` is a lowercase character ("t", "1", "[")
/// or a named key ("return", "tab", "space", "escape", "delete", "left", "right", "up", "down", "f1"..."f20").
public struct KeyCombo: Equatable, Codable, Sendable {
    public var key: String
    public var modifiers: Modifiers

    public init(key: String, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum SystemKey: String, Codable, Sendable, CaseIterable {
    case playPause, nextTrack, previousTrack
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
    case missionControl, appExpose, launchpad, showDesktop
}

public enum MouseButton: String, Codable, Sendable, CaseIterable { case left, right, middle }

public enum WindowLayout: String, Codable, Sendable, CaseIterable {
    case maximize, center
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
}

/// What a continuous gesture adjusts.
public enum AdjustTarget: String, Codable, Sendable, CaseIterable { case volume, brightness }

/// What a binding does. Encoded flat: {"type": "openApp", "bundleID": "com.apple.Safari"}.
public enum Action: Equatable, Sendable {
    case keyboardShortcut(KeyCombo)
    case openApp(bundleID: String)
    case openURL(String)
    case openFile(path: String)
    case shellScript(String)
    case appleScript(String)
    case shortcut(name: String)
    case systemKey(SystemKey)
    case mouseClick(MouseButton)
    case previousWindow
    case nextWindow
    case previousDisplay
    case nextDisplay
    case cursorToNextDisplay
    case windowLayout(WindowLayout)
    /// Only meaningful for continuous gestures.
    case adjust(AdjustTarget)
}

extension Action: Codable {
    private enum Kind: String, Codable {
        case keyboardShortcut, openApp, openURL, openFile, shellScript, appleScript, shortcut, systemKey,
             mouseClick, previousWindow, nextWindow, previousDisplay, nextDisplay, cursorToNextDisplay,
             windowLayout, adjust
    }

    private enum Keys: String, CodingKey {
        case type, key, modifiers, bundleID, url, path, script, name, button, layout, target
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .keyboardShortcut:
            self = .keyboardShortcut(KeyCombo(key: try c.decode(String.self, forKey: .key),
                                              modifiers: try c.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? []))
        case .openApp: self = .openApp(bundleID: try c.decode(String.self, forKey: .bundleID))
        case .openURL: self = .openURL(try c.decode(String.self, forKey: .url))
        case .openFile: self = .openFile(path: try c.decode(String.self, forKey: .path))
        case .shellScript: self = .shellScript(try c.decode(String.self, forKey: .script))
        case .appleScript: self = .appleScript(try c.decode(String.self, forKey: .script))
        case .shortcut: self = .shortcut(name: try c.decode(String.self, forKey: .name))
        case .systemKey: self = .systemKey(try c.decode(SystemKey.self, forKey: .key))
        case .mouseClick: self = .mouseClick(try c.decode(MouseButton.self, forKey: .button))
        case .previousWindow: self = .previousWindow
        case .nextWindow: self = .nextWindow
        case .previousDisplay: self = .previousDisplay
        case .nextDisplay: self = .nextDisplay
        case .cursorToNextDisplay: self = .cursorToNextDisplay
        case .windowLayout: self = .windowLayout(try c.decode(WindowLayout.self, forKey: .layout))
        case .adjust: self = .adjust(try c.decode(AdjustTarget.self, forKey: .target))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .keyboardShortcut(k):
            try c.encode(Kind.keyboardShortcut, forKey: .type)
            try c.encode(k.key, forKey: .key)
            try c.encode(k.modifiers, forKey: .modifiers)
        case let .openApp(id):
            try c.encode(Kind.openApp, forKey: .type)
            try c.encode(id, forKey: .bundleID)
        case let .openURL(u):
            try c.encode(Kind.openURL, forKey: .type)
            try c.encode(u, forKey: .url)
        case let .openFile(p):
            try c.encode(Kind.openFile, forKey: .type)
            try c.encode(p, forKey: .path)
        case let .shellScript(s):
            try c.encode(Kind.shellScript, forKey: .type)
            try c.encode(s, forKey: .script)
        case let .appleScript(s):
            try c.encode(Kind.appleScript, forKey: .type)
            try c.encode(s, forKey: .script)
        case let .shortcut(n):
            try c.encode(Kind.shortcut, forKey: .type)
            try c.encode(n, forKey: .name)
        case let .systemKey(k):
            try c.encode(Kind.systemKey, forKey: .type)
            try c.encode(k, forKey: .key)
        case let .mouseClick(b):
            try c.encode(Kind.mouseClick, forKey: .type)
            try c.encode(b, forKey: .button)
        case .previousWindow: try c.encode(Kind.previousWindow, forKey: .type)
        case .nextWindow: try c.encode(Kind.nextWindow, forKey: .type)
        case .previousDisplay: try c.encode(Kind.previousDisplay, forKey: .type)
        case .nextDisplay: try c.encode(Kind.nextDisplay, forKey: .type)
        case .cursorToNextDisplay: try c.encode(Kind.cursorToNextDisplay, forKey: .type)
        case let .windowLayout(l):
            try c.encode(Kind.windowLayout, forKey: .type)
            try c.encode(l, forKey: .layout)
        case let .adjust(t):
            try c.encode(Kind.adjust, forKey: .type)
            try c.encode(t, forKey: .target)
        }
    }
}
