// SPDX-License-Identifier: GPL-3.0-or-later

import AppCore
import CoreGraphics
import Model
import SwiftUI

struct BindingEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let original: GestureBinding
    private let isNew: Bool
    @ViewState private var draft: GestureDraft
    @ViewState private var modifiers: Modifiers
    @ViewState private var specificApps: Bool
    @ViewState private var apps: [String]
    @ViewState private var action: Action
    @ViewState private var name: String
    @ViewState private var recording = false
    /// Why the last Save or Delete did not happen; the sheet stays open.
    @ViewState private var problem: String?

    init(binding: GestureBinding, isNew: Bool) {
        original = binding
        self.isNew = isNew
        _draft = State(initialValue: GestureDraft(binding.gesture))
        _modifiers = State(initialValue: binding.modifiers)
        _specificApps = State(initialValue: !binding.apps.isEmpty)
        _apps = State(initialValue: binding.apps)
        _action = State(initialValue: binding.action)
        _name = State(initialValue: binding.name ?? "")
    }

    private var fields: BindingFields {
        BindingFields(gesture: draft.gesture, modifiers: modifiers, apps: specificApps ? apps : [], action: action, name: name)
    }

    private var result: GestureBinding { fields.applied(to: original) }

    var body: some View {
        let others = model.config.bindings.filter { $0.id != original.id }
        VStack(spacing: 0) {
            Form {
                if let problem {
                    Section { Label(problem, systemImage: "xmark.octagon").foregroundStyle(.red) }
                }
                Section {
                    TextField("Name", text: $name, prompt: Text("Optional"))
                    Picker("Gesture", selection: $draft.kind) {
                        ForEach(GestureKind.allCases, id: \.self) { Text($0.title) }
                    }
                    if let range = draft.kind.fingers {
                        Picker("Fingers", selection: $draft.fingers) {
                            ForEach(Array(range), id: \.self) { Text("\($0)") }
                        }
                        .pickerStyle(.segmented)
                    }
                    GestureParameter(draft: $draft)
                    LabeledContent("Hold") {
                        HStack(spacing: Design.spacing) {
                            ForEach(Modifiers.ordered, id: \.1) { modifier, symbol in
                                Toggle(symbol, isOn: .init(
                                    get: { modifiers.contains(modifier) },
                                    set: { if $0 { modifiers.insert(modifier) } else { modifiers.remove(modifier) } }))
                                .toggleStyle(.button)
                            }
                        }
                    }
                    LabeledContent("Or perform it") {
                        Button(recording ? "Waiting for a gesture…" : "Record", action: toggleRecording)
                    }
                }
                Section {
                    Picker("Works in", selection: $specificApps) {
                        Text("All apps").tag(false)
                        Text("Chosen apps").tag(true)
                    }
                    if specificApps {
                        ForEach(apps, id: \.self) { id in
                            HStack {
                                AppLabel(bundleID: id)
                                Spacer()
                                Button("Remove", systemImage: "minus.circle") { apps.removeAll { $0 == id } }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                            }
                        }
                        Menu("Add App") {
                            ForEach(System.runningApps.filter { !apps.contains($0.id) }, id: \.id) { app in
                                Button(app.name) { apps.append(app.id) }
                            }
                            Divider()
                            Button("Choose from Applications…") { apps += System.chooseApps(multiple: true).filter { !apps.contains($0) } }
                        }
                        if apps.isEmpty { Hint("Add at least one app") }
                    }
                }
                Section {
                    Picker("Action", selection: .init(get: { action.kind }, set: { if $0 != action.kind { action = $0.defaultAction } })) {
                        ForEach(ActionGroup.allCases, id: \.self) { group in
                            Section(group.title) {
                                ForEach(ActionKind.allCases.filter { $0.group == group }, id: \.self) { Text($0.title) }
                            }
                        }
                    }
                    ActionFields(action: $action)
                    if let hint = action.missingField { Hint(hint) }
                }
                NotesSection(notes: Notes(others + [result], only: result.id))
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        if model.update({ $0.remove(id: original.id) }) { dismiss() } else { problem = notSaved }
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(action.missingField != nil || (specificApps && apps.isEmpty))
            }
            .padding()
        }
        .frame(width: Design.paneWidth, height: Design.editorHeight)
        .onDisappear { if recording { model.engine.cancelRecording() } }
    }

    private var notSaved: String {
        model.canEdit ? "Couldn’t save the config file." : "The config file has an error — fix or delete it first."
    }

    /// Saved onto the binding as it is stored now, not the copy this sheet opened with.
    private func save() {
        var gone = false
        if !model.update({ gone = !$0.save(fields, to: original, isNew: isNew) }) {
            problem = notSaved
        } else if gone {
            problem = "This gesture was removed from the config file meanwhile. Cancel to close."
        } else {
            dismiss()
        }
    }

    private func toggleRecording() {
        if recording {
            model.engine.cancelRecording()
            recording = false
            return
        }
        recording = true
        model.engine.record { gesture, held in
            draft = GestureDraft(gesture)
            modifiers = held
            recording = false
        }
    }
}

/// The one picker each gesture kind needs besides finger count.
private struct GestureParameter: View {
    @SwiftUI.Binding var draft: GestureDraft

    var body: some View {
        switch draft.kind {
        case .swipe:
            choice("Direction", $draft.direction, Gesture.Direction.allCases) { $0.rawValue.capitalized }
        case .pinch:
            choice("Direction", $draft.pinch, Gesture.PinchDirection.allCases) { $0 == .pinchIn ? "In" : "Out" }
        case .rotate:
            choice("Direction", $draft.rotation, Gesture.Rotation.allCases) { $0 == .clockwise ? "Clockwise" : "Counterclockwise" }
        case .tipTap:
            choice("Tap side", $draft.side, Gesture.Side.allCases) { $0.rawValue.capitalized }
        case .edgeSwipe, .edgeSlide:
            choice("Edge", $draft.edge, Gesture.Edge.allCases) { $0.rawValue.capitalized }
        case .cornerTap:
            choice("Corner", $draft.corner, Gesture.Corner.allCases) { $0.title.capitalized }
        case .tap:
            EmptyView()
        }
    }

    private func choice<T: Hashable>(_ title: String, _ selection: SwiftUI.Binding<T>, _ values: [T], _ name: @escaping (T) -> String) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { Text(name($0)) }
        }
        .pickerStyle(.segmented)
    }
}

/// Only the fields the chosen action needs.
private struct ActionFields: View {
    @SwiftUI.Binding var action: Action

    var body: some View {
        switch action {
        case let .windowLayout(layout):
            Picker("Layout", selection: .init(get: { layout }, set: { action = .windowLayout($0) })) {
                ForEach(WindowLayout.allCases, id: \.self) { Text($0.title) }
            }
        case let .keyboardShortcut(combo):
            LabeledContent("Shortcut") { ShortcutRecorder(combo: combo) { action = .keyboardShortcut($0) } }
        case let .openApp(id):
            LabeledContent("App") {
                HStack {
                    if !id.isEmpty { AppLabel(bundleID: id) }
                    Button("Choose…") { if let picked = System.chooseApps(multiple: false).first { action = .openApp(bundleID: picked) } }
                }
            }
        case let .openURL(url):
            TextField("URL", text: .init(get: { url }, set: { action = .openURL($0) }), prompt: Text("https://"))
        case let .openFile(path):
            LabeledContent("File") {
                HStack {
                    Text(path.isEmpty ? "None" : (path as NSString).lastPathComponent).foregroundStyle(.secondary)
                    Button("Choose…") { if let picked = System.chooseFile() { action = .openFile(path: picked) } }
                }
            }
        case let .shellScript(script):
            ScriptField(title: "Script", text: .init(get: { script }, set: { action = .shellScript($0) }))
        case let .appleScript(script):
            ScriptField(title: "Script", text: .init(get: { script }, set: { action = .appleScript($0) }))
        case let .shortcut(name):
            TextField("Shortcut name", text: .init(get: { name }, set: { action = .shortcut(name: $0) }), prompt: Text("As named in Shortcuts"))
        case let .systemKey(key):
            Picker("Key", selection: .init(get: { key }, set: { action = .systemKey($0) })) {
                ForEach(SystemKey.allCases, id: \.self) { Text($0.title) }
            }
        case let .adjust(target):
            Picker("Adjusts", selection: .init(get: { target }, set: { action = .adjust($0) })) {
                ForEach(AdjustTarget.allCases, id: \.self) { Text($0.rawValue.capitalized) }
            }
        case let .mouseClick(button):
            Picker("Button", selection: .init(get: { button }, set: { action = .mouseClick($0) })) {
                ForEach(MouseButton.allCases, id: \.self) { Text($0.rawValue.capitalized) }
            }
            .pickerStyle(.segmented)
        case .previousWindow, .nextWindow, .previousDisplay, .nextDisplay, .cursorToNextDisplay:
            EmptyView()
        }
    }
}

/// Why Save is unavailable, next to the field that needs filling.
private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Label(text, systemImage: "info.circle").foregroundStyle(.secondary)
    }
}

private struct ScriptField: View {
    let title: String
    @SwiftUI.Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body.monospaced())
            .frame(height: Design.scriptHeight)
            .accessibilityLabel(title)
    }
}

/// Click, then press the shortcut. Escape cancels.
private struct ShortcutRecorder: View {
    let combo: KeyCombo
    let onChange: (KeyCombo) -> Void
    @ViewState private var monitor: Any?

    var body: some View {
        Button(monitor != nil ? "Type shortcut…" : combo.key.isEmpty ? "Record Shortcut" : combo.display, action: toggle)
            .onDisappear(perform: stop)
    }

    private func toggle() {
        if monitor != nil { return stop() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let held = Modifiers(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
            if event.keyCode != 53 || !held.isEmpty,
               let combo = KeyCombo(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "", modifiers: held) {
                onChange(combo)
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
