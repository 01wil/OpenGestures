// SPDX-License-Identifier: GPL-3.0-or-later

import AppCore
import Config
import Model
import SwiftUI

typealias GestureBinding = Model.Binding

/// Validator warnings and macOS gesture clashes for a set of bindings, as one list of calm notes.
struct Notes {
    var messages: [String] = []
    var hasConflict = false

    @MainActor init(_ bindings: [GestureBinding], only id: GestureBinding.ID? = nil) {
        let warnings = Validator.warnings(for: bindings).map { ($0.bindingIDs, $0.message) }
        let conflicts = SystemGestureConflicts.findOnThisMac(bindings).map { ($0.bindingIDs, $0.message) }
        for (ids, message) in warnings + conflicts where id.map(ids.contains) ?? true {
            messages.append(message)
        }
        hasConflict = conflicts.contains { ids, _ in id.map(ids.contains) ?? true }
    }
}

struct NotesSection: View {
    let notes: Notes

    var body: some View {
        if !notes.messages.isEmpty {
            Section {
                ForEach(notes.messages, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
                if notes.hasConflict {
                    Button("Open Trackpad Settings…") { NSWorkspace.shared.open(System.trackpadSettings) }
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}

struct GesturesPane: View {
    @Environment(AppModel.self) private var model
    @ViewState private var editing: Editing?

    struct Editing: Identifiable {
        var binding: GestureBinding
        var isNew: Bool
        var id: GestureBinding.ID { binding.id }
    }

    var body: some View {
        let bindings = model.config.bindings
        let notes = Notes(bindings)
        VStack(spacing: 0) {
            if bindings.isEmpty && model.canEdit {
                ContentUnavailableView {
                    Label("No Gestures", systemImage: "hand.draw")
                } description: {
                    Text("Add a gesture to switch windows, open apps or press shortcuts.")
                } actions: {
                    Button("Add Gesture…", action: add)
                }
            } else {
                Form {
                    if let error = model.configError {
                        Section {
                            Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
                            Text("Your last working gestures stay active. Fix the file and it reloads by itself.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NotesSection(notes: notes)
                    ForEach(BindingGroup.groups(bindings)) { group in
                        Section {
                            ForEach(group.bindings) { b in
                                BindingRow(binding: b) { on in
                                    model.update { $0.setEnabled(on, id: b.id) }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { if model.canEdit { editing = Editing(binding: b, isNew: false) } }
                                .contextMenu {
                                    Button("Edit…") { editing = Editing(binding: b, isNew: false) }
                                    Button("Delete", role: .destructive) { model.update { $0.remove(id: b.id) } }
                                }
                                .disabled(!model.canEdit)
                            }
                        } header: {
                            ScopeHeader(apps: group.apps)
                        }
                    }
                }
                .formStyle(.grouped)
                HStack {
                    Spacer()
                    Button("Add Gesture…", action: add).disabled(!model.canEdit)
                }
                .padding()
            }
        }
        .frame(width: Design.paneWidth, height: Design.gesturesPaneHeight)
        .sheet(item: $editing) { BindingEditor(binding: $0.binding, isNew: $0.isNew) }
    }

    private func add() {
        editing = Editing(binding: GestureBinding(gesture: .swipe(fingers: 3, direction: .up), action: .nextWindow), isNew: true)
    }
}

struct ScopeHeader: View {
    let apps: [String]

    var body: some View {
        if apps.isEmpty {
            Text("All Apps")
        } else {
            HStack(spacing: Design.spacing) {
                ForEach(apps, id: \.self) { AppLabel(bundleID: $0) }
            }
        }
    }
}

struct AppLabel: View {
    let bundleID: String

    var body: some View {
        Label {
            Text(System.appName(bundleID) ?? bundleID)
        } icon: {
            Image(nsImage: System.appIcon(bundleID)).resizable().frame(width: Design.appIcon, height: Design.appIcon)
        }
    }
}

struct BindingRow: View {
    let binding: GestureBinding
    let setEnabled: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(spacing: Design.spacing) {
            Image(systemName: binding.gesture.symbolName)
                .frame(width: Design.glyphWidth)
                .foregroundStyle(.secondary)
            Text(binding.gesture.title)
            ForEach(binding.modifiers.symbols, id: \.self) { ModifierChip(symbol: $0) }
            Spacer()
            Text(binding.action.summary(appName: System.appName)).foregroundStyle(.secondary)
            Toggle("Enabled", isOn: .init(get: { binding.enabled }, set: setEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .foregroundStyle(binding.enabled ? .primary : .tertiary)
    }
}

struct ModifierChip: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .padding(.horizontal, Design.chipPadding)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Design.chipRadius))
    }
}
