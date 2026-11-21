// SPDX-License-Identifier: GPL-3.0-or-later

import AppCore
import Config
import AppKit
import Model
import Observation
import ServiceManagement
import os

let log = Logger(subsystem: "io.github.01wil.OpenGestures", category: "app")

/// The live configuration and everything the UI shows about it. The config file is the source of truth:
/// edits go through `update`, which saves; the watcher brings every save (ours or a text editor's) back in.
@MainActor @Observable
final class AppModel {
    let store = ConfigStore()
    private(set) var config = Configuration(bindings: [])
    /// The file on disk is invalid; `config` is the last good one and the editor is read-only until fixed.
    private(set) var configError: String?
    /// The last action that failed, until the menu has shown it.
    var notice: String?
    private(set) var isFirstRun = false
    private(set) var accessibilityGranted = System.accessibilityGranted
    @ObservationIgnored private(set) lazy var engine = Engine { [weak self] message, kind in self?.report(message, kind: kind) }
    /// Nil outside an app bundle. Shows the real status and the last failure.
    private(set) var loginItem = MainAppLoginItem.available ? LaunchAtLogin(MainAppLoginItem()) : nil
    @ObservationIgnored private var watcher: ConfigWatcher?
    @ObservationIgnored private let approvals = ApprovalStore()
    /// Enabled bindings with a code-running action nobody approved yet. They are kept out of the engine.
    private(set) var pending: [GestureBinding] = []
    /// What the dialog already asked about, so a reload does not ask again. The banner can always ask.
    @ObservationIgnored private var asked: Set<String> = []

    var canEdit: Bool { configError == nil }

    func start() {
        isFirstRun = !FileManager.default.fileExists(atPath: store.url.path)
        do {
            apply(try store.load())
        } catch {
            configError = error.localizedDescription
            log.error("config: \(error.localizedDescription, privacy: .private)")
        }
        watcher = store.watch { [weak self] result in
            Task { @MainActor in self?.reloaded(result) }
        }
        engine.start()
        Task { @MainActor in self.askIfNew() }
        log.info("accessibility \(self.accessibilityGranted ? "granted" : "not granted", privacy: .public)")
        // Posted when the Accessibility list changes; the new state is readable a moment later.
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self?.refreshAccessibility()
            }
        }
    }

    /// Picks up a grant or revoke; when access arrives the engine starts using it without a relaunch.
    func refreshAccessibility() {
        let granted = System.accessibilityGranted
        guard granted != accessibilityGranted else { return }
        accessibilityGranted = granted
        log.info("accessibility \(granted ? "granted" : "revoked", privacy: .public)")
        if granted { engine.accessibilityGranted() }
    }

    func update(_ change: (inout Configuration) -> Void) {
        guard canEdit else { return }
        var next = config
        change(&next)
        guard next != config else { return }
        do {
            // What the user changes in the window is approved by that act; the rest of the file is not.
            try approvals.add(ActionApproval.approvedByEdit(old: config.bindings, new: next.bindings))
            try store.save(next)
            apply(next)
        } catch {
            report(error.localizedDescription, kind: "save failed")
        }
    }

    /// The notice shows the message; the log gets only the kind publicly (messages can quote scripts, URLs, paths).
    func report(_ message: String, kind: String) {
        log.error("\(kind, privacy: .public): \(message, privacy: .private)")
        notice = message
    }

    private func reloaded(_ result: Result<Configuration, ConfigError>) {
        switch result {
        case let .success(c):
            configError = nil
            apply(c)
            askIfNew()
        case let .failure(e):
            configError = e.localizedDescription
            log.error("config: \(e.localizedDescription, privacy: .private)")
        }
    }

    private func apply(_ c: Configuration) {
        config = c
        pending = ActionApproval.pending(c.bindings, approved: approvals.load())
        let waiting = Set(pending.map(\.id))
        engine.configure(bindings: c.bindings.filter { !waiting.contains($0.id) }, enabled: c.settings.enabled, sensitivity: c.settings.sensitivity)
        loginItem?.sync(wanted: c.settings.launchAtLogin)
    }

    /// Asks once per new pending action; the Gestures pane banner asks again on demand.
    private func askIfNew() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OG_SNAPSHOT_DIR"] != nil { return }  // a modal dialog would block the renders
        #endif
        let now = Set(pending.map { ActionApproval.fingerprint($0.action) })
        guard !now.isSubset(of: asked) else { return }
        asked.formUnion(now)
        reviewPending()
    }

    /// Lists the pending actions in full. Allow approves exactly those; Not now leaves them waiting.
    func reviewPending() {
        let waiting = pending
        guard !waiting.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ApprovalPrompt.title(count: waiting.count)
        alert.informativeText = ApprovalPrompt.message
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 440, height: 220)
        scroll.borderType = .bezelBorder
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.string = ApprovalPrompt.details(waiting)
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Not now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try approvals.add(Set(waiting.map { ActionApproval.fingerprint($0.action) }))
            apply(config)
        } catch {
            report(error.localizedDescription, kind: "approval failed")
        }
    }

    func setLaunchAtLogin(_ wanted: Bool) {
        let changed = wanted != config.settings.launchAtLogin
        update { $0.settings.launchAtLogin = wanted }
        // The setting may already say `wanted` while the login item failed to follow; a click retries.
        if !changed { loginItem?.sync(wanted: wanted, retry: true) }
    }

    func refreshLoginItem() { loginItem?.refresh() }
}

/// SMAppService only works from an app bundle; `swift run` builds have no login item.
struct MainAppLoginItem: LoginItemService {
    static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .notRegistered
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}
