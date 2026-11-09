# AGENTS.md

_Written by AI (Claude)._

macOS agent app (LSUIElement) showing a floating panel that lists every window on every Space. Logic lives in the
SwiftPM package (`Sources/WindowListCore`); `App/` is a thin XcodeGen shell.

## Commands

- Lint: `xcrun swift-format lint --strict -r App Sources Tests` (format with `xcrun swift-format format -i -r …`)
- Tests: `swift test` (pure suites take about 1 s; the live AX suites take about 7 min)
- Pure tests only: `swift test --skip LiveAXTests`
- App: `xcodegen generate && xcodebuild -project WindowList.xcodeproj -scheme WindowList -destination 'platform=macOS' -derivedDataPath .build/xcode build`

## Live AX tests (`Tests/WindowListAXTests`)

- They need Accessibility permission for the terminal and must run outside any sandbox.
- They need ≥2 desktop Spaces and the Mission Control "Move left/right a space" shortcuts enabled. They read the keys
  from system settings; never assume the defaults.
- Quit WindowList, AltTab and other window-observing apps before running: they expose "unseen" windows.
- They switch Spaces, toggle full screen and steal focus. Don't use the machine while they run.
- `propertyCheck` silently discards errors thrown by its body: wrap every body in `Live.failOnThrow`.

## Conventions

- Strong types (`ProcessID`, `WindowID`, `SpaceID`, …) with typed throws; no raw pids or window IDs in APIs.
- Property tests (x-sheep/swift-property-based): one property per `@Test`, a message on every `#expect`/`#require`.
- Never skip a test: check preconditions with `#require` and a message saying how to fix them.
- Private APIs (`PrivateAPIs.swift`) are written fresh, not copied, from AltTab (GPL-3). Link the AltTab source on
  every borrowed declaration.
- The panel's window configuration lives in `PanelStyle`, shared by the app and the fixture tests.
