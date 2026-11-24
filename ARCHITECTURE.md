# Architecture

OpenGestures reads raw trackpad touches, recognizes gestures from them, looks up the binding for the gesture, and runs its action. Everything that can be pure is pure, so `swift test` covers it without a trackpad.

## Modules

Defined in `Package.swift`. Each is a library target with its own test target, except `CMultitouch`, which has none of its own (`MultitouchBridgeTests` covers it through the bridge). The app and `og-record` have no tests.

- `Model` is shared value types: `Gesture` (with its string id), `Modifiers`, `Action`, `Binding`, `TouchFrame`. Pure.
- `Recognizer` takes touch frames and emits `GestureEvent` values. Pure. Thresholds live in `Tuning`.
- `Config` loads, saves, validates, migrates and watches the config file, resolves bindings (`BindingResolver`), warns about odd bindings (`Validator`) and detects clashes with macOS gestures (`SystemGestureConflicts`).
- `Windows` has the most-recently-used window list (`WindowHistory`), display ordering and window frame math (`DisplayGeometry`), and the saved-frame memory for layouts (`RestoreMemory`), all pure. The Accessibility glue is `AX`, `WindowTracker`, `WindowController` and `RestoreWatcher`.
- `Actions` runs a `Model.Action`. Everything with a side effect sits behind a protocol in `Seams.swift` (window commands, event posting, process launching, opening URLs and files), with real implementations in `Live.swift` and fakes in the tests.
- `CMultitouch` declares the private MultitouchSupport functions. `MultitouchBridge` wraps them and turns device callbacks into `TouchFrame` values.
- `AppCore` is the app logic without UI: per-device recognition and dispatch, the editor models, display names. Pure, and tested.
- `OpenGestures` is the app: menu bar item, settings window, first-run screen. It wires the modules together.
- `og-record` records touch frames to JSON for fixtures.

`WindowHistory` keeps `order[0]` as the current window. The first `previous` goes to `order[1]`, the first `next` to the least recent window. That starts a walk over a frozen snapshot, and each further call moves one step older or newer, wrapping. The walk ends when the user activates a window themselves, and the walked-to window is then recorded as used before the picked one. Activations within half a second of a step are our own focus change echoing back and are ignored.

`RestoreMemory` stores, per window, the frame it had before our first layout, for at most 50 windows (the oldest is forgotten first, and so are the windows of an app that quits). Applying the layout it is already in restores that frame. `RestoreWatcher` holds one `AXObserver` per remembered window. A resize that is not ours, or the window closing, drops the saved frame. A drag restores the saved size under the cursor. `placed` records the frame the app really accepted, so windows that snap to a grid or enforce a minimum size still count as already in the layout.

## Data flow

```
MultitouchBridge  ->  GestureRecognizer (one per device)  ->  BindingResolver  ->  ActionRunner
   TouchFrame             GestureEvent                        Binding              side effect
```

The bridge opens every multitouch device, registers a contact-frame callback on each, and rescans after wake from sleep and when a device connects. A rescan that finds no device is retried after 1, 2, 4, 8 and 16 seconds (`RescanSchedule`). Each device gets its own recognizer, because finger counts and positions must not mix across devices.

A discrete gesture produces one `GestureEvent`. A continuous one (`edgeslide.*`) produces repeated events with a signed delta.

Force clicks do not come from the touch frames. `Engine` listens with a listen-only event tap for the pressure events macOS sends (they arrive as gesture events, type 29) (stage 2 is a force click, judged with the user's click pressure setting) and asks `GesturePipeline.forceClick` how many fingers are down. The pressure event does not name the device, so the trackpad with the most fingers wins. That touch is then claimed, so lifting the fingers is not also a tap. The tap needs Accessibility and is created again once access is granted.

The resolver receives the gesture, the modifier keys held at that moment, and the frontmost app's bundle identifier. It considers enabled bindings whose gesture and modifiers match exactly. A binding limited to the frontmost app wins, otherwise the first global one. The runner then executes the binding's single action. Failures go to an error callback instead of throwing, and scripts run out of process with a 30 second timeout.

Config changes flow the other way. `ConfigStore.watch` watches the directory and the file, debounces by 50 ms, and delivers either a new `Configuration` or a `ConfigError`. The app swaps in a valid configuration and keeps the previous one on error. The settings window edits the same `Configuration` and saves through `ConfigStore`, so the file and the editor stay in sync.

Actions that run code (shell script, AppleScript, Shortcut, file, URL) are gated by `ActionApproval`. `AppModel` keeps bindings whose action is not approved out of the engine and shows them as waiting. Editing a binding in the editor approves it, because the editor shows the action, gesture, modifiers and apps; switching a row on or renaming it approves nothing, and everything else waits for the dialog. The dialog shows every pending action in full, with invisible and direction-changing characters written out as `\u{...}`. An approval is a fingerprint of the action together with its gesture, modifiers and apps, so the same script moved to another gesture or made global waits again. Fingerprints live in `approved.json` (`ApprovalStore`), outside the config, and the ones that no longer match a binding are dropped when the app saves.

## Config schema

```
Configuration  { version: Int, settings: Settings, bindings: [Binding] }
Settings       { enabled, showMenuBarIcon, launchAtLogin: Bool, sensitivity: 0...1 }
Binding        { id: UUID, gesture: String, modifiers: ["cmd","shift","ctrl","opt"],
                 apps: [bundle id], action: Action, enabled: Bool, name: String? }
Action         { "type": <kind>, ...fields }   flat, the fields depend on the kind
```

Decoding is lenient on optional fields so hand-written files stay short, and strict on the rest: an unknown gesture id, modifier or action type is an error that names the problem. `version` is the schema version. Older files are migrated in `Configuration.decode`, newer ones are rejected. Encoding uses sorted keys and pretty printing, so the file produces small diffs in git. Saving from the settings window rewrites the file in this canonical form and drops any key the app does not know, such as a hand-added note, so keep comments elsewhere. If the config path is a symlink, `save` writes to the target and keeps the link. The default configuration, with fixed UUIDs, is `Configuration.default`, and it must round-trip unchanged.

## Testing

The strategy is to keep logic out of the parts that need hardware.

- The recognizer is a pure function of touch frames. Tests build frames with a synthesizer (`Synth.swift`) and replay recorded fixtures.
- Fixtures are JSON arrays of frames, recorded from a real trackpad, in `Tests/RecognizerTests/Fixtures`, named `<gesture-id>__<name>.json`. `FixtureTests` runs every file and expects exactly that gesture. A file named `none__<name>.json` must yield no gesture, which is how near misses are pinned. The ones recorded so far are a resting palm or thumb and slow pointer movement. Record one with:

```
swift run og-record Tests/RecognizerTests/Fixtures/swipe.4.left__laptop-1.json
```

Perform the gesture within 120 seconds of starting it. Recording begins at the first touch and ends 0.3 seconds after all fingers have lifted. There is no duration argument. `og-record --guided <directory>` records the whole guided set of gestures, one file each. Pause or quit OpenGestures first, so its actions do not fire while you record.

- Config parsing, validation, migration, binding resolution, conflict detection, window history, display ordering and frame math are unit tests on plain values.
- The action runner is tested against fake seams, so no key press or window move happens.
- What cannot be automated, such as real devices, the Accessibility permission, multiple displays and the UI, is covered by [docs/manual-test.md](docs/manual-test.md).

## Private APIs and their risk

None of these are covered by Apple's compatibility promises. Each can change or disappear in any macOS update.

- MultitouchSupport (`MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTDeviceStart`, `MTDeviceStop`, `MTDeviceIsBuiltIn`), linked from `/System/Library/PrivateFrameworks`. This is the only source of raw touches, so if it breaks, the app does nothing. Risk is high impact, low frequency. The struct layout in `CMultitouch.h` is reverse engineered, so a layout change would produce garbage coordinates before it produces a crash. `og-record` and the fixtures make that visible.
- `_AXUIElementGetWindow`, found at runtime with `dlsym`, maps an Accessibility window to a window id. If missing, window lookup fails and focus actions do nothing.
- `GetProcessForPID` and `_SLPSSetFrontProcessWithOptions`, also found with `dlsym`, bring forward a window on another Space, which public API cannot do. If missing, switching to such windows fails and the rest still works.

Symbols found with `dlsym` degrade to a no-op. The linked MultitouchSupport framework does not, because the app will not launch without it.

The public APIs involved are Accessibility (needs the user's permission), CGEvent for posting keys, clicks and media keys, and reading the trackpad preferences domains to detect conflicts.

## Security model

The config file is trusted input. A `shellScript` or `appleScript` action runs as the user, and the app holds the Accessibility permission, so whoever can write `config.json` can run code as you. The app does not sandbox these scripts; it runs them out of process with a timeout. The build is signed with the hardened runtime and no entitlements. The app makes no network connections. See [SECURITY.md](SECURITY.md).
