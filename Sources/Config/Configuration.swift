// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Model

public struct Settings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var showMenuBarIcon: Bool
    public var launchAtLogin: Bool
    /// 0...1, higher recognises gestures from smaller movements.
    public var sensitivity: Double

    public init(enabled: Bool = true, showMenuBarIcon: Bool = true, launchAtLogin: Bool = false, sensitivity: Double = 0.5) {
        self.enabled = enabled
        self.showMenuBarIcon = showMenuBarIcon
        self.launchAtLogin = launchAtLogin
        self.sensitivity = sensitivity
    }

    private enum CodingKeys: String, CodingKey { case enabled, showMenuBarIcon, launchAtLogin, sensitivity }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? d.sensitivity
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var settings: Settings
    public var bindings: [Binding]

    public init(version: Int = Configuration.currentVersion, settings: Settings = Settings(), bindings: [Binding] = []) {
        self.version = version
        self.settings = settings
        self.bindings = bindings
    }

    private enum CodingKeys: String, CodingKey { case version, settings, bindings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        bindings = try c.decodeIfPresent([Binding].self, forKey: .bindings) ?? []
    }

    /// Stable, diff-friendly JSON for the config file.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    /// Decodes a config file, migrating older versions and rejecting newer ones.
    public static func decode(_ data: Data) throws -> Configuration {
        var config: Configuration
        do {
            config = try JSONDecoder().decode(Configuration.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.describing(error)
        }
        guard config.version <= currentVersion else {
            throw ConfigError.unsupportedVersion(found: config.version, supported: currentVersion)
        }
        // Migration hook: when the schema changes, upgrade `config` step by step here
        // (while config.version < currentVersion { ... }). Version 1 is the first schema.
        config.version = currentVersion
        return config
    }

    public static let `default` = Configuration(bindings: [
        Binding(id: UUID(uuidString: "0F1E2D3C-0001-4000-8000-000000000001")!, gesture: .swipe(fingers: 4, direction: .left),
                action: .previousWindow(), name: "Previous window"),
        Binding(id: UUID(uuidString: "0F1E2D3C-0002-4000-8000-000000000002")!, gesture: .swipe(fingers: 4, direction: .right),
                action: .nextWindow(), name: "Next window"),
        Binding(id: UUID(uuidString: "0F1E2D3C-0003-4000-8000-000000000003")!, gesture: .swipe(fingers: 4, direction: .left),
                modifiers: .command, action: .previousDisplay, name: "Move window to previous display"),
        Binding(id: UUID(uuidString: "0F1E2D3C-0004-4000-8000-000000000004")!, gesture: .swipe(fingers: 4, direction: .right),
                modifiers: .command, action: .nextDisplay, name: "Move window to next display"),
    ])
}
