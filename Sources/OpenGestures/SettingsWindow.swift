// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

enum Pane: Int, CaseIterable {
    case gestures, general, permissions, about

    var title: String {
        switch self {
        case .gestures: "Gestures"
        case .general: "General"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .gestures: "hand.draw"
        case .general: "gearshape"
        case .permissions: "lock"
        case .about: "info.circle"
        }
    }

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .gestures: GesturesPane()
        case .general: GeneralPane()
        case .permissions: PermissionsPane()
        case .about: AboutPane()
        }
    }
}

@MainActor
final class SettingsWindowController {
    private static let paneKey = "SettingsPane"
    private let tabs = PaneTabs()
    let window: NSWindow

    init(model: AppModel) {
        tabs.tabStyle = .toolbar
        for pane in Pane.allCases {
            let host = NSHostingController(rootView: pane.view.environment(model))
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = min(UserDefaults.standard.integer(forKey: Self.paneKey), Pane.allCases.count - 1)
        tabs.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
        window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show(_ pane: Pane?) {
        if let pane { tabs.selectedTabViewItemIndex = pane.rawValue }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private final class PaneTabs: NSTabViewController {
        override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
            super.tabView(tabView, didSelect: item)
            UserDefaults.standard.set(selectedTabViewItemIndex, forKey: SettingsWindowController.paneKey)
            // The window title follows the content view controller's title.
            title = item?.label
        }
    }
}
