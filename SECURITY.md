# Security policy

## Supported versions

Only the latest commit on `main` gets fixes. There are no signed releases yet; you build from source.

## Reporting a vulnerability

Use GitHub private vulnerability reporting: open the Security tab of [github.com/01wil/OpenGestures](https://github.com/01wil/OpenGestures) and choose "Report a vulnerability". Please do not open a public issue for a security problem. I will answer as soon as I can, but this is a spare-time project, so I can't promise a deadline.

## Threat model

- The config file is trusted. `~/.config/opengestures/config.json` can run shell scripts and AppleScript as your user, with OpenGestures' Accessibility permission. Anyone who can write it can run code as you. Keep it at mode 0600 and review changes from shared configs.
- The app makes no network connections and sends no telemetry.
- The build is signed with the hardened runtime. The local signing certificate is self-signed and trusted for your user only. Its private key stays in your login keychain and is not pre-authorised for `codesign`, so each build asks for your password.
- The app reads touches through Apple's private MultitouchSupport framework, which a macOS update can change.
- Out of scope: an attacker who already runs code as you, or who has physical access to an unlocked Mac.
