// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
@preconcurrency import ApplicationServices

/// Thin wrappers around system services the views and menu share.
@MainActor
enum System {
    static let trackpadSettings = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!
    static let accessibilitySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let repository = URL(string: "https://github.com/01wil/OpenGestures")!

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    private static var prompted = false

    /// The first time per launch, the system prompt, which adds the app to the Accessibility list and offers
    /// to open it; after that, straight to the list. Never both, so the user dismisses one thing at most.
    static func requestAccessibility() {
        if prompted {
            NSWorkspace.shared.open(accessibilitySettings)
        } else {
            prompted = true
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    static func appName(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
        }
    }

    static func appIcon(_ bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Bundle identifiers picked in an open panel rooted at /Applications.
    static func chooseApps(multiple: Bool) -> [String] {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = multiple
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    static func chooseFile() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    static var runningApps: [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
}
