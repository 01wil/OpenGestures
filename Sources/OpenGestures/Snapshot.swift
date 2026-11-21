// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import AppKit
import Model
import SwiftUI

extension AppDelegate {
    /// Design review without Screen Recording permission: with OG_SNAPSHOT_DIR set, renders every settings
    /// pane, the binding editor and the onboarding window in light and dark mode to PNG files there, then quits.
    func snapshotIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["OG_SNAPSHOT_DIR"] else { return }
        let samples: [(String, GestureBinding)] = [
            ("editor", model.config.bindings.last),
            ("editor-shortcut", GestureBinding(gesture: .swipe(fingers: 3, direction: .down), action: .keyboardShortcut(KeyCombo(key: "t", modifiers: [.command, .shift])))),
            ("editor-url", GestureBinding(gesture: .tap(fingers: 4), action: .openURL(""))),
            ("editor-preview", GestureBinding(gesture: .swipe(fingers: 4, direction: .left), action: .previousWindow(preview: true))),
        ].compactMap { name, binding in binding.map { (name, $0) } }
        let editors = samples.map { name, binding in
            (name, NSWindow(contentViewController: NSHostingController(rootView: BindingEditor(binding: binding, isNew: false).environment(model))))
        }
        Task {
            for (name, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                NSApp.appearance = NSAppearance(named: name)
                if let onboarding {
                    try? await Task.sleep(for: .milliseconds(500))
                    Self.write(onboarding, to: "\(dir)/onboarding-\(suffix).png")
                }
                for (name, editor) in editors {
                    editor.orderFront(nil)
                    try? await Task.sleep(for: .milliseconds(500))
                    Self.write(editor, to: "\(dir)/\(name)-\(suffix).png")
                    editor.orderOut(nil)
                }
                for (name, thumbnails) in [("switcher", false), ("switcher-thumbnails", true)] {
                    let switcher = SwitcherPanel()
                    switcher.show(Self.sampleCards(thumbnails: thumbnails), selected: 1, olderToTheLeft: true)
                    try? await Task.sleep(for: .milliseconds(500))
                    Self.write(switcher.window, to: "\(dir)/\(name)-\(suffix).png")
                    switcher.hide()
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

    /// Made-up windows of apps every Mac has; thumbnails are plain placeholders.
    private static func sampleCards(thumbnails: Bool) -> [SwitcherCard] {
        let windows = [("Safari", "OpenGestures — GitHub"), ("Mail", "Inbox"), ("Notes", "Groceries"), ("Finder", "Downloads"),
                       ("Calendar", "November 2026"), ("TextEdit", "Trackpad notes.rtf"), ("Terminal", "zsh — 120×40"),
                       ("Music", "Music")]
        return windows.enumerated().map { i, w in
            let path = ["/System/Applications/\(w.0).app", "/Applications/\(w.0).app", "/System/Applications/Utilities/\(w.0).app",
                        "/System/Library/CoreServices/\(w.0).app"].first { FileManager.default.fileExists(atPath: $0) }
            let thumbnail = thumbnails ? NSImage(size: CGSize(width: 320, height: 200), flipped: false) { r in
                NSColor.windowBackgroundColor.setFill(); r.fill()
                NSColor.separatorColor.setFill(); CGRect(x: 0, y: r.height - 28, width: r.width, height: 28).fill()
                return true
            } : nil
            return SwitcherCard(id: CGWindowID(i + 1), title: w.1, appName: w.0, icon: path.map { NSWorkspace.shared.icon(forFile: $0) }, thumbnail: thumbnail)
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
