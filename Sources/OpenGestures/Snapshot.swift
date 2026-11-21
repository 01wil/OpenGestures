// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit
import SwiftUI

extension AppDelegate {
    /// Design review without Screen Recording permission: with OG_SNAPSHOT_DIR set, renders every settings
    /// pane, the binding editor and the onboarding window in light and dark mode to PNG files there, then quits.
    func snapshotIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["OG_SNAPSHOT_DIR"] else { return }
        let editor = model.config.bindings.last.map {
            NSWindow(contentViewController: NSHostingController(rootView: BindingEditor(binding: $0, isNew: false).environment(model)))
        }
        Task {
            for (name, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                NSApp.appearance = NSAppearance(named: name)
                if let onboarding {
                    try? await Task.sleep(for: .milliseconds(500))
                    Self.write(onboarding, to: "\(dir)/onboarding-\(suffix).png")
                }
                if let editor {
                    editor.orderFront(nil)
                    try? await Task.sleep(for: .milliseconds(500))
                    Self.write(editor, to: "\(dir)/editor-\(suffix).png")
                    editor.orderOut(nil)
                }
                for pane in Pane.allCases {
                    showSettings(pane: pane)
                    try? await Task.sleep(for: .milliseconds(700))
                    Self.write(settings.window, to: "\(dir)/settings-\(pane.title.lowercased())-\(suffix).png")
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static func write(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
