# Security policy

## Supported versions

Only the latest commit on `main` gets fixes. There are no signed releases yet; you build from source.

## Reporting a vulnerability

Use GitHub private vulnerability reporting: open the Security tab of [github.com/01wil/OpenGestures](https://github.com/01wil/OpenGestures) and choose "Report a vulnerability". Please do not open a public issue for a security problem. I will answer as soon as I can, but this is a spare-time project, so I can't promise a deadline.

## Threat model

- The config file can run code. `~/.config/opengestures/config.json` can hold shell scripts and AppleScript that run as your user, with OpenGestures' Accessibility permission. Keep it at mode 0600 and review changes from shared configs.
- Because of that, a shell script, AppleScript, Shortcut, file or URL action does not run until you approved that exact action on that exact gesture, modifier keys and apps. Moving it to another gesture or making it global asks again. What you change in the gesture editor counts as approved. Switching a gesture on does not. Anything that arrives any other way (a text editor, `git pull`, a copied file) is shown in a dialog and stays disabled until you click Allow. The dialog shows every waiting action in full, with invisible and text-direction characters written out as escapes such as `\u{202E}`. The approvals are hashes in `~/Library/Application Support/OpenGestures/approved.json` (folder mode 0700), never in the config. Approvals for gestures that no longer exist are dropped when the app saves the config. This protects you from a dotfiles or shared config changing under you. It does not protect against a program running as you: it can edit the approvals file too.
- The app makes no network connections and sends no telemetry.
- The build is signed with the hardened runtime. The local signing certificate is self-signed and trusted for your user only. Its private key stays in your login keychain and is not pre-authorised for `codesign`, so each build asks for your password.
- The app reads touches through Apple's private MultitouchSupport framework, which a macOS update can change.
- Out of scope: an attacker who already runs code as you, or who has physical access to an unlocked Mac.
