# Pinbook iOS Codex handoff

Updated: 2026-09-01 (Asia/Shanghai)

## Ownership and source

- iOS repository: `zaidsafa/verbose-winner`
- Android read-only product reference: `zaidsafa/studious-potato`
- Android release reference: Pinbook 0.4.2, `versionCode 8`, source `442ae6a5bd2dc8ee26d6a1006dd9dda9fe4c0985`
- Initial iOS `main` bootstrap: `7b7fb061e22539632a13b9b5aa5c378235c83684`
- Active feature branch: `codex/pinbook-ios-foundation`

## Implemented scope

- Swift package foundation with Android backup-v8-compatible records.
- ISO currency-aware minor-unit money parsing and formatting.
- Deterministic newest-record merge with local-wins-ties behavior.
- Explicit service boundaries for Drive backup, receipts, statements, reminders, and later OCR.
- Native iOS 26.1 SwiftUI application and unit-test targets.
- SwiftData persistence for books, expenses, settlements, templates, receipt metadata, appearance, favorite currencies, reminders, and cross-platform timestamps.
- Working expense entry, partial payments and remaining balance, reversible noted flow, currency-separated summary, five visual skins, and grouped Options.
- Native Liquid Glass tab bar, minimizing behavior, bottom accessory, toolbar/buttons, sheet presentation, and grouped custom glass actions; information cards stay on stable themed surfaces.
- Localization-ready strings with initial Arabic shell translations and RTL-safe semantic layout.

## Validation

- `swift test --disable-sandbox --scratch-path /private/tmp/pinbook-ios-swift-build` passed all 5 tests on Xcode 26.6 / Swift 6.3.3.
- The alternate scratch path was required because the managed environment denied SwiftPM's user cache and nested sandbox; this is an environment boundary, not a source failure.
- Unsigned generic iOS Simulator build passed against SDK 26.5 with deployment target 26.1.
- The iOS test bundle compiled, and all 3 in-memory SwiftData tests passed on a dedicated iPhone 17 Pro simulator: clean production bootstrap, persisted partial payment, and currency-separated summary totals.
- The clean-launch Expenses screen was visually inspected in English and Arabic RTL on that simulator; screenshots: `docs/evidence/pinbook-empty-expenses.png` and `docs/evidence/pinbook-empty-expenses-ar.png`.

## Limitations

- Drive/OAuth, receipt import, statements, notifications, conflict-recovery UI, and OCR are architectural seams only, not implemented features.
- iCloud/CloudKit is not implemented. The planned provider design treats it as an optional alternative to Google Drive, not a simultaneous second sync authority.
- Books and templates have persisted models but only the default book is exposed in the initial UI; template creation and additional book management are not yet implemented.
- Arabic translations currently cover the top-level shell only; full parity with Android's five locales remains unfinished.
- Simulator validation does not prove physical-device behavior, Apple signing, TestFlight, Drive transfer, iCloud, notifications, or App Store acceptance.
- No Apple signing, OAuth credentials, external account settings, TestFlight, or App Store state has been created or changed.

## Exact next actions

1. Complete simulator visual/accessibility checks for all four sections, five skins, light/dark, Arabic RTL, and accessibility settings.
2. Add editable books/templates and receipt-file storage without changing the backup schema boundary.
3. Implement statements and local reminders behind their existing ports, with focused tests and simulator/device acceptance.
4. Implement Google Drive `drive.appdata` as the first sync adapter only after OAuth/provider decisions and explicit credential approval.
