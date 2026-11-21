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
        syncLaunchAtLogin(c.settings.launchAtLogin)
    }

    /// SMAppService only works from an app bundle; `swift run` builds skip it.
    private func syncLaunchAtLogin(_ wanted: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let service = SMAppService.mainApp
        let registered = service.status == .enabled || service.status == .requiresApproval
        guard wanted != registered else { return }
        do {
            if wanted { try service.register() } else { try service.unregister() }
        } catch {
            report("Couldn’t change launch at login: \(error.localizedDescription)")
        }
    }
}
