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
- Editable books, explicit favorite currencies, templates, Favorites, and Quick Add.
- Selected-photo-only receipts copied into app-private protected storage.
- On-device, one-person/one-currency PDF and exact-value CSV statements.
- Privacy-safe local reminders that request permission only during an explicit reminder save.

Google Drive, iCloud, conflict-recovery UI, and OCR are not implemented. Physical-device notification delivery and share-extension transfer remain acceptance boundaries. Their status is documented without presenting unverified behavior as working.

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
