# OpenGestures

<p align="center"><img src="Resources/AppIcon-1024.png" width="128" alt="OpenGestures icon"></p>

Free, open-source gestures for your Mac's trackpad, built-in or Magic Trackpad, mapped to whatever you want.

OpenGestures is a small menu bar app. You pick a gesture, optionally hold modifier keys, optionally limit it to one app, and choose what it does. Everything lives in one readable config file that you can keep in git.

## What it does

Out of the box, two sets of gestures are bound.

- Swipe left or right with 4 fingers to jump to the previous or next recently used window. There is no switcher UI, it goes straight there, including to windows of other apps and other Spaces.
- Hold ⌘ and swipe left or right with 4 fingers to move the focused window to the previous or next display.

Both are ordinary bindings. Edit them, remove them, or add your own in the settings window (⌘,) or in the config file.

## Supported gestures

Each gesture has an id, which is how it appears in the config file. Any gesture can be combined with a set of modifier keys, and the same gesture with different modifiers is a different trigger.

```
swipe.<2-5>.<left|right|up|down>   swipe with 2 to 5 fingers
tap.<1-5>                          tap with 1 to 5 fingers
pinch.<2-5>.<in|out>               pinch with 2 to 5 fingers
rotate.<cw|ccw>                    two-finger rotate, clockwise or counterclockwise
tiptap.<left|right>                one finger rests, another taps to its left or right
edgeswipe.<left|right|top|bottom>  one finger swipes in from an edge
cornertap.<topleft|topright|bottomleft|bottomright>
                                   one finger taps in a corner
edgeslide.<left|right|top|bottom>  one finger slides along an edge (continuous)
```

An edge slide reports a value while you move, so it only pairs with the adjust action (volume or brightness). Every other gesture fires once.

## Supported actions

Keyboard and system

- keyboardShortcut: press a key combination, for example ⌘⇧T
- systemKey: playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute, brightnessUp, brightnessDown, missionControl, appExpose, launchpad, showDesktop
- adjust: volume or brightness, for edge slides
- mouseClick: left, right or middle click at the cursor

Open and run

- openApp: by bundle identifier
- openURL
- openFile
- shellScript: runs through `/bin/zsh -lc`
- appleScript
- shortcut: runs a shortcut from the Shortcuts app by name

Windows and displays

- previousWindow, nextWindow: most recently used order
- previousDisplay, nextDisplay: move the focused window to the neighbouring display. Displays are ordered left to right and wrap around. The window keeps its size, shrunk to fit if needed, and its relative position. A window that fills its screen fills the new one.
- cursorToNextDisplay
- windowLayout: maximize, center, leftHalf, rightHalf, topHalf, bottomHalf, topLeft, topRight, bottomLeft, bottomRight

A binding runs one action. Window layouts are triggered by a gesture only. There is no drag-to-edge snapping.

## Requirements

- macOS 27 or later. Older versions may work, but they are not supported.
- Apple Silicon.
- A trackpad, built-in or Magic Trackpad. Magic Mouse is not supported.
- Command Line Tools for Xcode, to build it.

## Install

OpenGestures is installed by building it from source. Signed and notarized downloads need a paid Apple Developer account, which costs $99 a year. I would rather not pay that before I know anyone wants the app. If it turns out to be useful to enough people, a signed download will follow. A star on the repository or an issue telling me what you use it for helps show that.

Install the Command Line Tools if you do not have them:

```
xcode-select --install
```

Clone the repository, create a local signing certificate (once), build the app and install it to `~/Applications`:

```
git clone https://github.com/01wil/OpenGestures.git
cd OpenGestures
./scripts/make-signing-cert.sh
./scripts/build-app.sh
./scripts/install.sh
```

Open OpenGestures from `~/Applications` and click Allow Access when asked, then turn OpenGestures on in System Settings › Privacy & Security › Accessibility. The status in the app updates live, so no restart is needed.

### Why the signing certificate

macOS ties the Accessibility grant to the app's signature. `make-signing-cert.sh` creates a self-signed "OpenGestures Local Dev" certificate in your login keychain (macOS asks for your password once), and `build-app.sh` signs with it automatically. That keeps the signature identity the same across rebuilds, so the grant survives updates.

Without the certificate the build is ad-hoc signed, and an ad-hoc signature changes with every build. The switch in System Settings then still looks on, but macOS no longer honours it and no gesture action runs. To fix that, remove OpenGestures from the Accessibility list with the minus button and add it again. You can also sign with any other identity: `OG_SIGN_IDENTITY="Your Identity" ./scripts/build-app.sh`.

## Configuration

The settings window and the config file are two views of the same data. Changes in the window are written to the file, and edits you make in a text editor are picked up within a moment, with no restart.

The file is `~/.config/opengestures/config.json`. If `XDG_CONFIG_HOME` is set, it is `$XDG_CONFIG_HOME/opengestures/config.json`. The app creates it with the defaults on first run. It is plain JSON with a schema version, so it works well in a dotfiles repo, and a symlink into that repo is fine. To set up a new Mac, copy the file over before you first launch the app.

If you save a file that is not valid, the app shows the error and keeps running with the last valid configuration. It never overwrites a file it could not read.

This is the default configuration:

```json
{
  "bindings" : [
    {
      "action" : { "type" : "previousWindow" },
      "apps" : [],
      "enabled" : true,
      "gesture" : "swipe.4.left",
      "id" : "0F1E2D3C-0001-4000-8000-000000000001",
      "modifiers" : [],
      "name" : "Previous window"
    },
    {
      "action" : { "type" : "nextWindow" },
      "apps" : [],
      "enabled" : true,
      "gesture" : "swipe.4.right",
      "id" : "0F1E2D3C-0002-4000-8000-000000000002",
      "modifiers" : [],
      "name" : "Next window"
    },
    {
      "action" : { "type" : "previousDisplay" },
      "apps" : [],
      "enabled" : true,
      "gesture" : "swipe.4.left",
      "id" : "0F1E2D3C-0003-4000-8000-000000000003",
      "modifiers" : [ "cmd" ],
      "name" : "Move window to previous display"
    },
    {
      "action" : { "type" : "nextDisplay" },
      "apps" : [],
      "enabled" : true,
      "gesture" : "swipe.4.right",
      "id" : "0F1E2D3C-0004-4000-8000-000000000004",
      "modifiers" : [ "cmd" ],
      "name" : "Move window to next display"
    }
  ],
  "settings" : {
    "enabled" : true,
    "launchAtLogin" : false,
    "sensitivity" : 0.5,
    "showMenuBarIcon" : true
  },
  "version" : 1
}
```

Modifiers are `cmd`, `shift`, `ctrl` and `opt`. Only `gesture` and `action` are required in a binding. `id`, `modifiers`, `apps`, `enabled` and `name` can be left out when you write a binding by hand. Sensitivity runs from 0 to 1, and higher reacts to smaller movements.

A binding limited to one app lists its bundle identifiers in `apps`. While that app is in front, it wins over a global binding for the same gesture and modifiers. This one turns a 3-finger tap into a new tab in Safari:

```json
{
  "gesture": "tap.3",
  "apps": ["com.apple.Safari"],
  "action": { "type": "keyboardShortcut", "key": "t", "modifiers": ["cmd"] }
}
```

A keyboard-shortcut binding with its own modifiers. Hold ⌥ and pinch out with 2 fingers to press ⌘⇧= in any app:

```json
{
  "gesture": "pinch.2.out",
  "modifiers": ["opt"],
  "action": { "type": "keyboardShortcut", "key": "=", "modifiers": ["cmd", "shift"] }
}
```

Keys are a lowercase character, or one of `return`, `tab`, `space`, `escape`, `delete`, `left`, `right`, `up`, `down`, `f1` to `f20`.

Other actions look like this:

```json
{ "type": "openURL", "url": "https://example.com" }
{ "type": "shellScript", "script": "open -a Terminal" }
{ "type": "systemKey", "key": "missionControl" }
{ "type": "windowLayout", "layout": "leftHalf" }
{ "type": "adjust", "target": "volume" }
```

## Conflicts with macOS gestures

macOS uses some of the same gestures. By default, 4-finger swipes switch between Spaces and full-screen apps, which clashes with the default bindings. When an enabled binding overlaps a macOS gesture that is switched on, OpenGestures shows a warning that says which one, with a button that opens Trackpad settings. The setting to change is in System Settings › Trackpad › More Gestures. OpenGestures reads those settings and never changes them.

## Privacy

OpenGestures makes no network connections and collects no telemetry. It needs one permission, Accessibility. It uses it to move and focus windows, and to send the key presses and clicks your bindings ask for. It does not log or store what you do on the trackpad.

## How it works

OpenGestures reads raw touches from the trackpad through Apple's private MultitouchSupport framework, the same source other gesture tools use. A recognizer turns those touches into gestures, the config decides which binding applies, and an action runs. Because the framework is private, a macOS update can break it. If gestures stop working after an update, please open an issue. See [ARCHITECTURE.md](ARCHITECTURE.md) for the details.

## Credits

Window switching and moving windows between displays are adapted from [Vorssaint](https://github.com/vorssaint/vorssaint-utils), which is GPL-3.0-or-later. OpenGestures is inspired by tools like BetterTouchTool. It is an independent project and is not affiliated with or endorsed by them.

## Contributing

Bug reports, fixtures of gestures that misbehave, and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
