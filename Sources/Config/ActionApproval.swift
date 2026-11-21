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

    /// What an approval covers: the action and when and where it runs. Not the id, name or enabled switch.
    private struct Approved: Encodable {
        var action: Action
        var gesture: Gesture
        var modifiers: Modifiers
        var apps: [String]
    }

    /// Identifies the action's content and its trigger and scope, so a changed script or URL, or the same one
    /// moved to another gesture or app, is a new action.
    public static func fingerprint(_ binding: Binding) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let approved = Approved(action: binding.action, gesture: binding.gesture, modifiers: binding.modifiers, apps: binding.apps.sorted())
        let data = (try? encoder.encode(approved)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The fingerprints of every binding that needs approval, enabled or not: the approvals worth keeping.
    public static func fingerprints(_ bindings: [Binding]) -> Set<String> {
        Set(bindings.filter { requiresApproval($0.action) }.map(fingerprint))
    }

    /// Enabled bindings that need approval and do not have it. They must not run.
    public static func pending(_ bindings: [Binding], approved: Set<String>) -> [Binding] {
        bindings.filter { $0.enabled && requiresApproval($0.action) && !approved.contains(fingerprint($0)) }
    }

    /// What an edit made in the app approves: bindings it added, or whose action, gesture, modifiers or apps it
    /// changed, because the editor showed exactly that. Switching a binding on or renaming it approves nothing.
    public static func approvedByEdit(old: [Binding], new: [Binding]) -> Set<String> {
        let before = Dictionary(old.map { ($0.id, fingerprint($0)) }, uniquingKeysWith: { first, _ in first })
        return Set(new.filter { requiresApproval($0.action) }.compactMap { b in
            let f = fingerprint(b)
            return before[b.id] == f ? nil : f
        })
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

    /// Adds `fingerprints` and, when `current` is given, drops every approval not in it (bindings that are gone).
    /// Writes only when that changes something.
    public func add(_ fingerprints: Set<String>, keepingOnly current: Set<String>? = nil) throws {
        let old = load()
        var all = old.union(fingerprints)
        if let current { all.formIntersection(current) }
        guard all != old else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try ConfigStore.createPrivateDirectory(url.deletingLastPathComponent(), tightenExisting: true)
        try ConfigStore.writePrivately(try encoder.encode(File(approved: all.sorted())), to: url)
    }
}
