// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private unowned let delegate: AppDelegate

    init(model: AppModel, delegate: AppDelegate) {
        self.model = model
        self.delegate = delegate
        super.init()
        let image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "OpenGestures")
        image?.isTemplate = true
        item.button?.image = image
        item.menu = NSMenu()
        item.menu?.delegate = self
        trackChanges { [weak self] in
            guard let self else { return }
            item.isVisible = model.config.settings.showMenuBarIcon
            item.button?.appearsDisabled = !model.config.settings.enabled
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let notice = model.notice {
            menu.addItem(info(notice, symbol: "exclamationmark.triangle"))
        }
        if model.configError != nil {
            menu.addItem(entry("Config File Has an Error…", #selector(settings)))
        }
        if !System.accessibilityGranted {
            menu.addItem(entry("Allow Accessibility Access…", #selector(permissions)))
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }

        let enabled = entry("Enabled", #selector(toggleEnabled))
        enabled.state = model.config.settings.enabled ? .on : .off
        enabled.isEnabled = model.canEdit
        menu.addItem(enabled)
        menu.addItem(.separator())
        menu.addItem(entry("Settings…", #selector(settings), key: ","))
        menu.addItem(entry("Open Config File", #selector(openConfig)))
        let reveal = entry("Reveal Config File in Finder", #selector(revealConfig))
        reveal.isAlternate = true
        reveal.keyEquivalentModifierMask = .option
        menu.addItem(reveal)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit OpenGestures", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// The failure notice has been seen once the menu closes.
    func menuDidClose(_ menu: NSMenu) {
        model.notice = nil
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func info(_ title: String, symbol: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        i.isEnabled = false
        return i
    }

    @objc private func toggleEnabled() { model.update { $0.settings.enabled.toggle() } }
    @objc private func settings() { delegate.showSettings(pane: .gestures) }
    @objc private func permissions() { delegate.showSettings(pane: .permissions) }
    @objc private func openConfig() { delegate.openConfigFile() }
    @objc private func revealConfig() { delegate.revealConfigFile() }
}
