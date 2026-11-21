// SPDX-License-Identifier: GPL-3.0-or-later

import AppCore
import AppKit
import Config
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    /// 0 = Easy (reacts to small movements) … 1 = Precise; the config stores sensitivity the other way round.
    @ViewState private var precision: Double?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
                if let login = model.loginItem {
                    if let error = login.error {
                        Text("Couldn’t change launch at login: \(error)").foregroundStyle(.red)
                    }
                    if login.status == .requiresApproval {
                        LabeledContent {
                            Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        } label: {
                            Text("Requires approval in System Settings › General › Login Items.").foregroundStyle(.orange)
                        }
                    }
                }
                Toggle(isOn: setting(\.showMenuBarIcon)) {
                    Text("Show menu bar icon")
                    Text("When hidden, open OpenGestures again to get here.")
                }
            }
            Section {
                LabeledContent {
                    HStack {
                        Button("Reveal") { delegate?.revealConfigFile() }
                        Button("Open") { delegate?.openConfigFile() }
                    }
                } label: {
                    Text("Config file")
                    Text((model.store.url.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } footer: {
                Text("Keep it in a dotfiles repo and symlink it here to share your gestures.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Slider(value: .init(get: { precision ?? 1 - model.config.settings.sensitivity }, set: { precision = $0 }),
                       in: 0...1) {
                    Text("Sensitivity")
                } minimumValueLabel: {
                    Text("Easy")
                } maximumValueLabel: {
                    Text("Precise")
                } onEditingChanged: { editing in
                    guard !editing, let p = precision else { return }
                    model.update { $0.settings.sensitivity = 1 - p }
                    precision = nil
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!model.canEdit)
        .task { model.refreshLoginItem() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshLoginItem() }
        .frame(width: Design.paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    /// Shows the real login item state, not just the setting.
    private var launchAtLogin: Binding<Bool> {
        .init(get: { model.loginItem.map { $0.status != .notRegistered } ?? model.config.settings.launchAtLogin },
              set: { model.setLaunchAtLogin($0) })
    }

    private func setting(_ key: WritableKeyPath<Config.Settings, Bool>) -> Binding<Bool> {
        .init(get: { model.config.settings[keyPath: key] }, set: { value in model.update { $0.settings[keyPath: key] = value } })
    }
}

/// Live Accessibility status; polls once a second while on screen as a backup to the change notification.
struct AccessibilityStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let granted = model.accessibilityGranted
        Group {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label("Not granted", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
        .animation(Design.stateChange, value: granted)
        .task {
            while !Task.isCancelled {
                model.refreshAccessibility()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

struct PermissionsPane: View {
    @Environment(AppModel.self) private var model
    /// Nil until the user clicks: the help opens by itself while access is missing.
    @ViewState private var helpOpen: Bool?

    var body: some View {
        let granted = model.accessibilityGranted
        Form {
            Section {
                LabeledContent {
                    AccessibilityStatus()
                } label: {
                    Text("Accessibility")
                    Text("Lets OpenGestures switch, move and resize windows and send keys and clicks.")
                }
                if !granted {
                    LabeledContent("") {
                        Button("Allow Access…", action: System.requestAccessibility)
                    }
                }
            }
            Section {
                DisclosureGroup("Stopped working after a rebuild?", isExpanded: .init(get: { helpOpen ?? !granted }, set: { helpOpen = $0 })) {
                    VStack(alignment: .leading, spacing: Design.spacing) {
                        Text("macOS ties the permission to the app's signature, and a build without a signing certificate gets a new one each time. The switch can then look on while macOS ignores it.")
                        VStack(alignment: .leading, spacing: Design.spacing / 2) {
                            Text("1. Open Accessibility settings below.")
                            Text("2. Select OpenGestures and click the minus button.")
                            Text("3. Click the plus button and add ~/Applications/OpenGestures.app, or click Allow Access.")
                        }
                        Text("To avoid this, run ./scripts/make-signing-cert.sh once and rebuild. The README explains why.")
                        Button("Open Accessibility Settings…") { NSWorkspace.shared.open(System.accessibilitySettings) }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, Design.spacing / 2)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Design.paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AboutPane: View {
    var body: some View {
        VStack(spacing: Design.spacing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Design.aboutIcon, height: Design.aboutIcon)
            Text("OpenGestures").font(.title2).bold()
            Text("Version \(System.version) · Free software under GPL-3.0-or-later").foregroundStyle(.secondary)
            Link("github.com/01wil/OpenGestures", destination: System.repository)
            Button("Show Welcome…") { (NSApp.delegate as? AppDelegate)?.showOnboarding() }
                .padding(.top)
        }
        .padding()
        .frame(width: Design.paneWidth)
    }
}
