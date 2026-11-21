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
    @ObservationIgnored private(set) lazy var engine = Engine { [weak self] message in self?.report(message) }
    /// Nil outside an app bundle. Shows the real status and the last failure.
    private(set) var loginItem = MainAppLoginItem.available ? LaunchAtLogin(MainAppLoginItem()) : nil
    @ObservationIgnored private var watcher: ConfigWatcher?

    var canEdit: Bool { configError == nil }

    func start() {
        isFirstRun = !FileManager.default.fileExists(atPath: store.url.path)
        do {
            apply(try store.load())
        } catch {
            configError = error.localizedDescription
            log.error("config: \(error.localizedDescription, privacy: .public)")
        }
        watcher = store.watch { [weak self] result in
            Task { @MainActor in self?.reloaded(result) }
        }
        engine.start()
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
            try store.save(next)
            apply(next)
        } catch {
            report(error.localizedDescription)
        }
    }

    func report(_ message: String) {
        log.error("\(message, privacy: .public)")
        notice = message
    }

    private func reloaded(_ result: Result<Configuration, ConfigError>) {
        switch result {
        case let .success(c):
            configError = nil
            apply(c)
        case let .failure(e):
            configError = e.localizedDescription
            log.error("config: \(e.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ c: Configuration) {
        config = c
        engine.configure(bindings: c.bindings, enabled: c.settings.enabled, sensitivity: c.settings.sensitivity)
        loginItem?.sync(wanted: c.settings.launchAtLogin)
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
