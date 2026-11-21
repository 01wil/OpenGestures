# Contributing

Thanks for helping. Issues and pull requests are both welcome. For anything bigger than a small fix, open an issue first so we can agree on the approach.

## Build and test

You need macOS 27, Apple Silicon and the Command Line Tools.

```
swift build
swift test
```

`swift test` runs without a trackpad and must pass with 0 failures. To build the app bundle, use `./scripts/build-app.sh`, and `./scripts/install.sh` to install it. See the README for signing.

## Tests first

Write the failing test before the code. Recognition, config, binding resolution, window history and frame math are pure modules, and a change to them needs a test that fails without it. A bug fix starts with a test that reproduces the bug.

Keep logic out of code that needs hardware. If something needs the trackpad, Accessibility or a display, put the decision in a pure function and keep the glue thin.

## Recording fixtures

If a gesture is missed or fires when it should not, record it and add it as a fixture. Run this from the repository root and perform the gesture:

```
swift run og-record Tests/RecognizerTests/Fixtures/<gesture-id>__<name>.json
```

The file name says what the recognizer must produce. For example `swipe.4.left__laptop-1.json` must yield exactly one 4-finger left swipe. Use `none__<name>.json` for a near miss that must yield nothing. Gesture ids are listed in the README.

## Style

- Every source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`. Code adapted from another project also names it and its license, as the Vorssaint-derived files do.
- Match the surrounding code. Prefer the plain, small change. No new dependencies without a reason.
- Comments explain why, not what.
- Do not copy code from closed-source tools or from projects whose license is incompatible with GPL-3.0-or-later.
- Contributions are licensed under GPL-3.0-or-later.

Before a pull request, run `swift test` and, if you touched behavior that tests cannot reach, the relevant steps in [docs/manual-test.md](docs/manual-test.md).

## Troubleshooting

With only the Command Line Tools installed, the toolchain sometimes loses the Swift Testing macro plugin ("plugin for module 'TestingMacros' not found"). Package.swift passes the plugin path to the test targets to prevent it. If you still see it, move `.build` out of the way and rebuild.

If the app's gestures stop doing anything after a rebuild, the Accessibility grant no longer matches the signature. Run `scripts/make-signing-cert.sh` once and rebuild; see the README.
