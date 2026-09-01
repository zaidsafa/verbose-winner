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
- Users can create, edit, and soft-delete active-book templates. Expenses can be starred or unstarred as Favorites directly from their cards.
- Quick Add presents active-book Favorites and templates in a native half-height sheet and copies the selected source into a fresh, open, unstarred expense with a new identity and current date.
- SwiftData tombstones use `isTombstoned` internally to avoid the framework's `isDeleted` lifecycle collision; cross-platform backup records retain the Android-compatible `isDeleted` field.
- Expense cards open a private receipt sheet. Apple PhotosPicker grants only the selected image, which is copied to app-private Application Support storage under a UUID filename with protected file attributes; no broad photo-library permission is requested.
- Receipt import and removal coordinate file bytes with SwiftData metadata, compensate failed metadata saves, reject traversal filenames, and retain a confirmation step before UI deletion.
- Statements generate on-device PDF and CSV for exactly one active-book person and one currency. CSV retains exact minor-unit integers; both formats exclude private notes and never apply an implicit exchange rate.
- Statement files are temporary and backup-excluded, and become externally visible only if the user activates the native ShareLink workflow.
- PDF rendering is appearance-independent for printing: every page is explicitly white with black/dark-gray ink. CSV protects spreadsheet consumers by neutralizing formula-leading user fields, and both formats surface arithmetic overflow instead of clamping.
- Receipt removal persists its tombstone before deleting private bytes. If persistence fails, rollback keeps both live metadata and the file; a later byte-removal failure can leave an orphan but cannot leave live metadata pointing to a missing file.
- Books and Statements reserve shared bottom scroll clearance, and UI automation proves their final identified content can be moved fully above the floating Liquid Glass tab bar.
- Local reminders request notification authorization only during an explicit reminder-bearing save. Scheduled notification copy is generic, and pending requests are cancelled when a reminder is cancelled or its expense is marked noted.

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
- The Templates/Favorites/Quick Add milestone passes 9/9 simulator tests with unique ephemeral stores for parallel isolation. Interactive acceptance verified accessible star controls, both Quick Add source groups, and a fresh expense created from the fixture template. Evidence: `docs/evidence/pinbook-quick-add.png`.
- The receipt milestone passes 11/11 simulator tests. Interactive PhotosPicker acceptance imported a deterministic image, displayed its attachment metadata, and verified the copied 2,853,668-byte UUID-named PNG inside Pinbook's private Simulator container. Evidence: `docs/evidence/pinbook-private-receipt.png`.
- The statement/reminder milestone passes 14/14 simulator tests. Interactive acceptance generated a 178-byte exact-value CSV and a 28,996-byte one-page PDF for one person/currency scope without opening the share sheet. The reminder overview showed generic privacy guidance and a future fixture date. Evidence: `docs/evidence/pinbook-statements.png` and `docs/evidence/pinbook-reminders.png`.
- The follow-up complete scheme passes 20/20 on the dedicated iPhone 17 Pro simulator (19/19 isolated tests plus 1/1 XCUITest). It covers dark-mode print-safe PDF pixels, CSV formula neutralization, explicit statement-overflow failures, receipt tombstone-save failure ordering, and final-row/help reachability above the tab bar. Evidence: `docs/evidence/pinbook-statements-dark-reachability.png` and `docs/evidence/pinbook-dark-generated-statement-pdf.png`.
- The Simulator accessibility tree exposes card labels, labeled remaining values, and Payment/Mark noted actions in logical order. Spoken VoiceOver, rotor, and physical-device focus behavior remain outside this evidence boundary.

## Limitations

- Drive/OAuth, conflict-recovery UI, and OCR remain unimplemented.
- iCloud/CloudKit is not implemented. The planned provider design treats it as an optional alternative to Google Drive, not a simultaneous second sync authority.
- Statements are generated locally, but successful transfer through a chosen share extension was not exercised. Reminder request construction is implemented, but authorization and real notification delivery were deliberately not triggered during simulator acceptance.
- Arabic now covers the current iOS shell, forms, grouped options, validation copy, and accessibility labels. Full parity with Android's five locales remains unfinished, and user-authored content is not translated.
- Simulator validation does not prove physical-device behavior, Apple signing, TestFlight, Drive transfer, iCloud, notifications, or App Store acceptance.
- No Apple signing, OAuth credentials, external account settings, TestFlight, or App Store state has been created or changed.

## Exact next actions

1. Complete an interactive physical-iPhone accessibility pass for spoken VoiceOver, rotor behavior, focus order, Reduce Transparency, Increase Contrast, the five-skin light/dark matrix, share-extension transfer, and real local-notification delivery.
2. Implement Google Drive `drive.appdata` only after explicit OAuth/provider approval, with restore preview, history, undo snapshots, and deterministic conflict recovery.
