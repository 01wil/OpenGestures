# Manual test checklist

The parts `swift test` cannot reach. Run it on macOS 27 with the built-in trackpad, and for the display steps, with two monitors. Start from a fresh clone.

## Build and first run

- [ ] From a fresh clone, follow only the README: `xcode-select --install` (if needed), then `./scripts/build-app.sh` and `./scripts/install.sh`. OpenGestures.app appears in `~/Applications` and opens.
- [ ] The first-run screen explains Accessibility in one sentence and has a button that opens System Settings › Privacy & Security › Accessibility.
- [ ] Grant the permission. The screen changes to granted without restarting the app.
- [ ] A menu bar icon appears. Its menu has enable/pause, Settings… and Quit.

## Default gestures

Open three windows, two of them from different apps (say Safari, Notes and Terminal). Focus each in turn so they have a recent-use order.

- [ ] Swipe left with 4 fingers. The previous recently used window comes to the front, including when it belongs to another app.
- [ ] Swipe right with 4 fingers. The next window comes to the front.
- [ ] Put a window on another Space and repeat. It is brought forward too.
- [ ] With two monitors, focus a window and hold ⌘ while swiping left with 4 fingers. The window moves to the previous display (the one to the left, wrapping around). It stays on screen and keeps its size, shrunk only if the new display is smaller.
- [ ] Hold ⌘ and swipe right with 4 fingers. The window moves to the next display.
- [ ] Make a window fill its screen, then move it. It fills the new screen.

## Actions

Add a binding for each in the settings window, with any gesture you like, and fire it.

- [ ] Keyboard shortcut: for example ⌘⇧4 opens the screenshot selection.
- [ ] Open app: opens or focuses the app.
- [ ] Open URL: the page opens in the default browser.
- [ ] Open file: the file opens in its default app.
- [ ] Run shell script: `touch /tmp/og-test` creates the file.
- [ ] Run AppleScript: `display notification "hi"` shows a notification.
- [ ] Run a Shortcut: a shortcut from the Shortcuts app runs.
- [ ] Media and system keys: play/pause, volume up and down, brightness up and down, Mission Control, App Exposé, Launchpad, show desktop each work.
- [ ] Mouse click: left, right and middle click land at the cursor.
- [ ] Move cursor to next display moves the pointer.
- [ ] Window layouts: maximize, center, both halves, top and bottom halves and the four quarters place the focused window correctly.
- [ ] Adjust: an edge slide changes volume or brightness while you move, and stops when you lift.
- [ ] Each remaining gesture type (tap, pinch, rotate, TipTap, edge swipe, corner tap) triggers a binding.

## Modifiers and per-app bindings

- [ ] A binding with ⌘ does not fire without ⌘, and the binding without modifiers does not fire with ⌘ held.
- [ ] Add a binding for a gesture limited to one app. It fires with that app in front and does nothing elsewhere.
- [ ] Add a global binding for the same gesture and modifiers. The app binding fires in its app, the global one fires everywhere else.

## Config file

- [ ] `~/.config/opengestures/config.json` exists after first run and contains the four default bindings.
- [ ] Open the file in a text editor, change a binding's action, and save. Within 2 seconds the new action runs, with no restart.
- [ ] Change a binding in the settings window. The file changes to match.
- [ ] Save broken JSON. The UI reports the error, the previous bindings keep working, and the file is not overwritten.
- [ ] Fix the file. The error clears and the new content applies.
- [ ] Set `XDG_CONFIG_HOME` to another folder, launch the app, and confirm it uses `$XDG_CONFIG_HOME/opengestures/config.json`.
- [ ] Copy the file to a fresh user account's `~/.config/opengestures/` and launch the app there. All bindings are restored.
- [ ] Replace the file with a symlink to a file elsewhere. Edits in the window and in the editor still work, and the link remains.

## Settings window

- [ ] ⌘, opens it.
- [ ] Every pane fits without scrolling at the default size.
- [ ] Add a binding by choosing a gesture (or performing it), modifiers and an action.
- [ ] Bindings are grouped under Global and per app. Remove and disable work.
- [ ] Looks right in light mode and in dark mode.
- [ ] Advanced tuning is collapsed by default.
- [ ] The launch at login toggle works: log out and in, and the app starts.
- [ ] The menu bar icon can be hidden and shown again.

## Conflict warning

- [ ] In System Settings › Trackpad › More Gestures, set Swipe between full-screen apps to 4 fingers. With the default bindings enabled, OpenGestures shows a warning, and its button opens Trackpad settings.
- [ ] Turn the macOS gesture off or move it to 3 fingers. The warning goes away.
- [ ] OpenGestures never changed a system setting.

## Permissions and sleep

- [ ] Remove OpenGestures from the Accessibility list. The app shows it is missing, and gestures that need it do nothing.
- [ ] Add it back. It recovers without a restart.
- [ ] Put the Mac to sleep and wake it. Gestures work again.
- [ ] Connect a Magic Trackpad after launch. Gestures work on it.

## Rebuild

- [ ] Rebuild and reinstall with the default ad-hoc signature. If gestures stop, removing and re-adding the app in Accessibility restores them, as the README says.
- [ ] Rebuild with `OG_SIGN_IDENTITY` set to a self-signed certificate. After granting once, a second rebuild keeps the grant.

## Idle load

- [ ] With no fingers on the trackpad, watch OpenGestures in Activity Monitor for one minute. CPU stays below 1%.
