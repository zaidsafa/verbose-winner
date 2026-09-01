# Pinbook for iOS

Native SwiftUI companion to Pinbook, an offline-first notebook for periodic expenses that later need to be charged, deducted, settled, or noted.

The Android product remains the behavioral reference while this repository develops the iOS implementation using native Apple platform conventions. The current reference is Android Pinbook 0.4.2 (`versionCode 8`) at commit `442ae6a5bd2dc8ee26d6a1006dd9dda9fe4c0985`.

## Current foundation

- iOS 26.1 SwiftUI app with native Liquid Glass navigation and interactive controls.
- SwiftData local persistence with a clean production bootstrap.
- Expenses, currency-separated Summary, recoverable Noted, and grouped Options.
- Currency-safe signed 64-bit minor units and partial-payment balances.
- Shared backup-v8 models and deterministic conflict merge groundwork.
- Five Pinbook visual skins and localization-ready, RTL-safe layout.

Google Drive, iCloud, receipt files, statements, notification delivery, conflict-recovery UI, and OCR are not implemented. Their boundaries are documented without presenting them as working features.

## Build and test

Requirements: Xcode 26.1 or newer and an iOS 26.1+ simulator.

```sh
swift test
xcodebuild \
  -project Pinbook.xcodeproj \
  -scheme Pinbook \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

See `docs/CODEX_HANDOFF.md` for exact validation evidence and limitations.
