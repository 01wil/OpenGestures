// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation
import Model

/// Actions that run code or open arbitrary things with the app's permissions only run after the user
/// approved that exact action. What the settings window writes counts as approved; what arrives from a
/// text editor, a git pull or a copied file is pending until the user allows it.
public enum ActionApproval {
    public static func requiresApproval(_ action: Action) -> Bool {
        switch action {
        case .shellScript, .appleScript, .shortcut, .openFile, .openURL: true
        default: false
        }
    }

    /// Identifies the action's content, so a changed script or URL is a new action.
    public static func fingerprint(_ action: Action) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(action)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Enabled bindings that need approval and do not have it. They must not run.
    public static func pending(_ bindings: [Binding], approved: Set<String>) -> [Binding] {
        bindings.filter { $0.enabled && requiresApproval($0.action) && !approved.contains(fingerprint($0.action)) }
    }

    /// What an edit made in the app approves: the actions of bindings it added, changed or switched on.
    public static func approvedByEdit(old: [Binding], new: [Binding]) -> Set<String> {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(new.filter { b in
            guard b.enabled, requiresApproval(b.action), let was = before[b.id] else { return b.enabled && requiresApproval(b.action) }
            return !was.enabled || was.action != b.action
        }.map { fingerprint($0.action) })
    }
}

/// The approved fingerprints, kept outside config.json so a config that arrives from elsewhere cannot approve
/// itself. Another program running as the same user can edit this file too (see SECURITY.md).
public struct ApprovalStore: Sendable {
    public let url: URL

    public init(url: URL = ApprovalStore.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenGestures/approved.json")
    }

    private struct File: Codable { var approved: [String] }

    /// A missing or unreadable file means nothing is approved.
    public func load() -> Set<String> {
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return Set(file.approved)
    }

    public func add(_ fingerprints: Set<String>) throws {
        guard !fingerprints.isEmpty else { return }
        let all = load().union(fingerprints)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try ConfigStore.createPrivateDirectory(url.deletingLastPathComponent())
        try ConfigStore.writePrivately(try encoder.encode(File(approved: all.sorted())), to: url)
    }
}
