# WindowList.app

A macOS app listing all the open windows, for easy navigation between them.

## Use of Private macOS APIs

The code uses Apple's private macOS APIs, as there are no public APIs to enumerate windows on other
Spaces, say which Space a window belongs to, what the Space layout per display is, or raising and
focusing a specific window (and not the app as a whole).

## Building

Requires macOS 26, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. It is prudent to validate tests pass before trusting the app. See [AGENTS.md](AGENTS.md) for
   instructions on how to run the tests.
2. Run `make release`: it would build the app in the `bin` directory.
3. Launch the app and grant it accessibility permissions when asked.

## Acknowledging AI Use

This software was written with assistance from the following AI models:

- Claude Sonnet 5.5 (Anthropic)
- Claude Opus 5.5 (Anthropic)

## License

This software is licensed under the terms of the [GPL-3.0 license](LICENSE), matching
[AltTab](https://github.com/lwouis/alt-tab-macos), which served as a study guide for macOS
internals.
