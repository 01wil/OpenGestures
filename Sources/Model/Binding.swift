// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A set of modifier keys. Encoded as a sorted array of short names: ["cmd","shift","ctrl","opt"].
public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let shift = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let option = Modifiers(rawValue: 1 << 3)

    /// Encoding order and names.
    public static let named: [(Modifiers, String)] = [(.command, "cmd"), (.shift, "shift"), (.control, "ctrl"), (.option, "opt")]
}

extension Modifiers: Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var result: Modifiers = []
        while !c.isAtEnd {
            let name = try c.decode(String.self)
            guard let m = Self.named.first(where: { $0.1 == name })?.0 else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown modifier \"\(name)\"")
            }
            result.insert(m)
        }
        self = result
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for (m, name) in Self.named where contains(m) { try c.encode(name) }
    }
}

/// A gesture, the modifiers that must be held, the apps it is limited to, and what it does.
public struct Binding: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var gesture: Gesture
    public var modifiers: Modifiers
    /// Bundle identifiers. Empty means global.
    public var apps: [String]
    public var action: Action
    public var enabled: Bool
    /// Optional label shown in the editor.
    public var name: String?

    public init(id: UUID = UUID(), gesture: Gesture, modifiers: Modifiers = [], apps: [String] = [],
                action: Action, enabled: Bool = true, name: String? = nil) {
        self.id = id
        self.gesture = gesture
        self.modifiers = modifiers
        self.apps = apps
        self.action = action
        self.enabled = enabled
        self.name = name
    }

    public var isGlobal: Bool { apps.isEmpty }

    private enum CodingKeys: String, CodingKey { case id, gesture, modifiers, apps, action, enabled, name }

    /// Lenient on optional fields so hand-written config stays short.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        gesture = try c.decode(Gesture.self, forKey: .gesture)
        modifiers = try c.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? []
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        action = try c.decode(Action.self, forKey: .action)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}
