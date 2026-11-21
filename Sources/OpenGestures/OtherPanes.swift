// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Config
import SwiftUI

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    /// 0 = Easy (reacts to small movements) … 1 = Precise; the config stores sensitivity the other way round.
    @ViewState private var precision: Double?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: setting(\.launchAtLogin))
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
                DisclosureGroup("Advanced") {
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
        }
        .formStyle(.grouped)
        .disabled(!model.canEdit)
        .frame(width: Design.paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    private func setting(_ key: WritableKeyPath<Config.Settings, Bool>) -> Binding<Bool> {
        .init(get: { model.config.settings[keyPath: key] }, set: { value in model.update { $0.settings[keyPath: key] = value } })
    }
}

/// Live Accessibility status; polls once a second while on screen because macOS sends no change notification.
struct AccessibilityStatus: View {
    @SwiftUI.Binding var granted: Bool

    var body: some View {
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
                granted = System.accessibilityGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

struct PermissionsPane: View {
    @ViewState private var granted = System.accessibilityGranted

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    AccessibilityStatus(granted: $granted)
                } label: {
                    Text("Accessibility")
                    Text("Lets OpenGestures switch, move and resize windows and send keys and clicks.")
                }
                if !granted {
                    LabeledContent("") {
                        Button("Open System Settings…", action: System.requestAccessibility)
                    }
                }
            } footer: {
                if !granted {
                    Text("After rebuilding the app, macOS may need the switch turned off and on again.")
                        .foregroundStyle(.secondary)
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
