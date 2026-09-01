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
- Arabic shell localization, RTL-safe semantic layout, and bidirectional isolation for financial values.
- Debug-only deterministic launch fixtures use an ephemeral SwiftData store to exercise populated expenses, a partial payment, three currencies, Summary, Noted, and grouped Options without contaminating production bootstrap.
- Accessibility-size layouts stack card metadata/actions, switch Expenses to an inline title, and remove the optional Quick Add accessory while retaining the toolbar Add action.
- Book management supports create, rename, active-book selection, recoverable archive, and restore. The active book cannot be archived, and production bootstrap repairs an invalid active-book reference.
- Expenses, Summary, and Noted are isolated to the active book; settlements and currency totals cannot leak across that boundary.
- Favorite currencies remain empty in production until the user explicitly enables them, with an explicit preferred-currency picker for new expense entry.

## Validation

- `swift test --disable-sandbox --scratch-path /private/tmp/pinbook-ios-swift-build` passed all 5 tests on Xcode 26.6 / Swift 6.3.3.
- The alternate scratch path was required because the managed environment denied SwiftPM's user cache and nested sandbox; this is an environment boundary, not a source failure.
- Unsigned generic iOS Simulator build passed against SDK 26.5 with deployment target 26.1.
- The iOS test bundle compiled, and all 3 in-memory SwiftData tests passed on a dedicated iPhone 17 Pro simulator: clean production bootstrap, persisted partial payment, and currency-separated summary totals.
- The clean-launch Expenses screen was visually inspected in English and Arabic RTL on that simulator; screenshots: `docs/evidence/pinbook-empty-expenses.png` and `docs/evidence/pinbook-empty-expenses-ar.png`.
- The final simulator suite passes 5/5 tests after adding deterministic fixture/configuration coverage; Swift package tests remain 5/5.
- Unsigned Debug and Release generic iOS Simulator builds pass. Release compilation excludes all fixture population code.
- Populated visual evidence now covers Paper Glass Expenses, Soft Pastel Summary, Night Ink Noted, grouped Options, Arabic RTL, accessibility extra-extra-large text, Increase Contrast, and Reduce Transparency. See `docs/VALIDATION.md` for the evidence map.
- Clean Ledger and Editorial now have accepted light/dark populated evidence. All skin backdrops adapt to color scheme; the initial Clean Ledger dark contrast defect was fixed before acceptance.
- The book milestone passes 7/7 simulator tests. Interactive acceptance created/selected a second book, proved its Expenses view was empty, switched back to prove the original records remained, then exercised rename, archive, and restore. Evidence: `docs/evidence/pinbook-books-management.png`.
- The Simulator accessibility tree exposes card labels, labeled remaining values, and Payment/Mark noted actions in logical order. Spoken VoiceOver, rotor, and physical-device focus behavior remain outside this evidence boundary.

## Limitations

- Drive/OAuth, receipt import, statements, notifications, conflict-recovery UI, and OCR are architectural seams only, not implemented features.
- iCloud/CloudKit is not implemented. The planned provider design treats it as an optional alternative to Google Drive, not a simultaneous second sync authority.
- Templates have a persisted model but template creation, Favorites, and template-backed Quick Add are not yet implemented.
- Arabic now covers the current iOS shell, forms, grouped options, validation copy, and accessibility labels. Full parity with Android's five locales remains unfinished, and user-authored content is not translated.
- Simulator validation does not prove physical-device behavior, Apple signing, TestFlight, Drive transfer, iCloud, notifications, or App Store acceptance.
- No Apple signing, OAuth credentials, external account settings, TestFlight, or App Store state has been created or changed.

## Exact next actions

1. Add templates, Favorites, and Quick Add.
2. Add privacy-friendly PhotosPicker receipt import copied into app-private storage with lifecycle tests.
3. Add per-person/per-currency PDF/CSV statements and local reminder delivery.
4. Complete an interactive physical-iPhone accessibility pass for spoken VoiceOver, rotor behavior, focus order, Reduce Transparency, Increase Contrast, and the five-skin light/dark matrix.
5. Implement Google Drive `drive.appdata` only after the local workflows and explicit OAuth/provider approval.
