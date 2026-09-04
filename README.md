# Pinbook for iOS

Native SwiftUI companion to Pinbook, an offline-first notebook for periodic expenses that later need to be charged, deducted, settled, or noted.

The Android product remains the behavioral reference while this repository develops the iOS implementation using native Apple platform conventions. The current localization contract is Android Pinbook 0.5.0 at behavior commit `9ad28646f3ddb5ebfa874421b44e40b4cfda8a74`; this is not an iOS publication claim.

## Current foundation

- iOS 26.1 SwiftUI app with native Liquid Glass navigation and interactive controls.
- SwiftData local persistence with a clean production bootstrap.
- Expenses, currency-separated Summary, recoverable Noted, and grouped Options.
- Currency-safe signed 64-bit minor units and partial-payment balances.
- Shared backup-v8 models and deterministic conflict merge groundwork.
- Local Backup & Recovery center with native Files export/import, validated per-entity restore preview, pre-restore snapshots, exact recovery, and privacy-safe activity history.
- Five adaptive Pinbook visual skins with descriptive symbol/palette previews, automated light/dark contrast coverage, and accessible native motion.
- Complete 256-key catalogs for 16 languages, including separate Simplified/Traditional Chinese and Arabic/Urdu RTL. The 13 added locales are assistant-authored drafts, not native-reviewed translations.
- First-run and Options language controls with persistent choice, System Default reset, live layout updates, and localized validation messages. Only compiled locales are offered. See `docs/LOCALIZATION_REVIEW.md` for translation checks and release boundaries.
- A short, skippable, replayable first-run introduction; production starts with no sample financial records and never resets a returning user's local data.
- Editable books, a searchable 159-code Foundation ISO currency catalog with localized names and symbols, explicit favorites, templates, Favorites, and Quick Add.
- Two privacy-safe WidgetKit widgets: Quick Expense and Balance Overview. They deep-link into Pinbook without placing financial amounts on the Home Screen.
- Selected-photo-only receipts copied into app-private protected storage.
- On-device, one-person/one-currency print-safe PDF and exact-value, spreadsheet-safe CSV statements with explicit overflow failure.
- Privacy-safe local reminders that request permission only during an explicit reminder save.
- TestFlight release groundwork: a production App Store icon, Apple privacy manifest, export-compliance declaration, automatic-signing settings for the app and widget, and copy-ready App Store Connect metadata.

Google Drive, iCloud, OAuth, live widget data sharing, and OCR are not implemented. The widgets intentionally need no App Group and expose no financial data. Both native Files sheets have been opened on a physical iPhone, but a completed external Files save/import round trip, notification delivery, and share-extension transfer remain acceptance boundaries. Their status is documented without presenting unverified behavior as working.

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

See `docs/CODEX_HANDOFF.md` for exact validation evidence and limitations. `docs/TESTFLIGHT_SUBMISSION.md` contains the copy-ready TestFlight/App Store Connect fields and upload checklist; `docs/PRIVACY_POLICY.md` is the publish-ready privacy-policy draft.
