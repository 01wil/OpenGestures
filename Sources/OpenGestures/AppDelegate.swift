// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Config
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusMenu: StatusMenu?
    private(set) lazy var settings = SettingsWindowController(model: model)
    private(set) var onboarding: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
        model.start()
        statusMenu = StatusMenu(model: model, delegate: self)
        if model.isFirstRun {
            showOnboarding()
        } else if !model.config.settings.showMenuBarIcon && !Self.launchedAtLogin {
            showSettings(nil)
        }
        #if DEBUG
        snapshotIfRequested()
        #endif
    }

    /// A login item is opened with an "open application" event that says so; a launch from Finder,
    /// Spotlight or the Dock is not. Only those should show a window when the menu bar icon is hidden.
    private static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        let reason = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        return reason == OSType(keyAELaunchedAsLogInItem) || reason == OSType(keyAELaunchedAsServiceItem)
    }

    /// Opening the app again while it runs is the way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(nil)
        return false
    }

    @objc func showSettings(_ sender: Any?) { settings.show(nil) }

    func showSettings(pane: Pane) { settings.show(pane) }

    func showOnboarding() {
        onboarding?.close()
        let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView { [weak self] in
            self?.onboarding?.close()
            self?.onboarding = nil
        }.environment(model)))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        onboarding = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func openConfigFile() {
        let url = model.store.url
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([model.store.url])
    }

    private static func mainMenu() -> NSMenu {
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: title)
            items.forEach { item.submenu?.addItem($0) }
            return item
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = modifiers
            return i
        }
        let main = NSMenu()
        main.addItem(menu("OpenGestures", [
            item("Settings…", #selector(showSettings(_:)), ","),
            .separator(),
            item("Quit OpenGestures", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(menu("Window", [item("Close", #selector(NSWindow.performClose(_:)), "w")]))
        return main
    }
}

/// Re-runs `apply` whenever an observed property it read changes.
@MainActor
func trackChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking(apply) {
        Task { @MainActor in trackChanges(apply) }
    }
}
