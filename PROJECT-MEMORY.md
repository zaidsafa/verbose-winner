# Pinbook iOS project memory

Last updated: 2026-09-27

This file is the durable, secret-free memory for Pinbook iOS. Update it with every meaningful release and whenever an architecture, invariant, ownership boundary, recovery method, or release gate changes. Keep older decisions and release facts as dated history. Do not store credentials, tokens, certificates, provisioning profiles, account data, private records, device identifiers, or raw logs here.

## Repository and verified baseline

- Repository: `zaidsafa/verbose-winner`
- App bundle: `com.zaidsafa.pinbook.ios`
- Widget bundle: `com.zaidsafa.pinbook.ios.widgets`
- GitHub foundation branch: `codex/pinbook-ios-foundation`
- GitHub baseline inspected for this memory: `f78d112eda13275b1a81647e2a042874698cfbc7`
- GitHub baseline application version: `0.1.0`, build `1`
- Stack: Swift 6, SwiftUI, SwiftData, WidgetKit, UserNotifications, PhotosUI
- Deployment target: iOS 26.1
- Shared backup envelope: Android-compatible version 8
- Android behavioral reference at the GitHub baseline: Pinbook Android 0.4.2, `versionCode 8`, commit `442ae6a5bd2dc8ee26d6a1006dd9dda9fe4c0985`

Later local history through `4c8087b0bb3b021dd5f78c43b343eec5236875f4` records sixteen-language drafts, persistent language controls, TestFlight build 2 preparation, upload, and validation. That history was present in a local source repository but was not present on GitHub when this file was created. Treat it as a local successor record, not the remote source baseline and not current store-availability proof.

## Product boundary

Pinbook is a native, offline-first personal expense notebook for iPhone and iPad. It follows the same financial and backup semantics as Android while using native Apple navigation, controls, Files workflows, SwiftData, WidgetKit, and accessibility behavior.

SwiftData is authoritative while the app runs. The GitHub baseline implements local Files backup and recovery. Google Drive, iCloud, CloudKit, OAuth, central team sync, and OCR are not implemented in that baseline.

## Architecture

### Application and presentation

- `Pinbook/PinbookApp.swift` creates the SwiftData container and application scene.
- `Pinbook/AppShellView.swift` owns onboarding, language environment, deep links, the tab shell, and global presentation state.
- `Pinbook/ExpenseViews.swift` owns the primary Expenses list, expense cards, payments, and receipt entry.
- `Pinbook/ExpenseEditorView.swift` owns new expense entry and the established validation and save flow.
- `Pinbook/SummaryAndNotedViews.swift` owns currency-separated Summary and recoverable Noted views.
- `Pinbook/OptionsView.swift` owns grouped settings and its navigation destinations.
- `Pinbook/TemplatesAndQuickAddViews.swift` owns templates, Favorites-driven Quick Add, and fresh-entry creation.
- `Pinbook/StatementAndReminderViews.swift` owns statement selection and reminder overview.
- `Pinbook/ReceiptViews.swift` owns selected-photo receipt presentation.
- `Pinbook/BackupRecoveryView.swift` owns local backup health, Files export/import, restore preview, activity, and recovery.
- `Pinbook/PinbookTheme.swift` owns skin tokens and adaptive presentation roles.
- `Pinbook/OnboardingView.swift` owns the brief, skippable, replayable first-run introduction.

### Persistence and domain

- `Pinbook/PersistenceModels.swift` owns SwiftData records and schema membership.
- `PinbookCore` owns platform-neutral backup models, currency-safe money, validation, deterministic merge planning, and service ports.
- `Pinbook/BackupRecoveryService.swift` owns complete local backup capture, validation, restore preview, transactional apply, snapshots, recovery, and privacy-safe activity records.
- `Pinbook/ReceiptFileStore.swift` owns app-private receipt bytes and file-safety checks.
- `Pinbook/StatementAndReminderServices.swift` owns local PDF/CSV generation and local-notification scheduling.
- `PinbookWidgets/PinbookWidgets.swift` owns two privacy-safe deep-link widgets. Neither widget reads nor displays financial data.
- `Pinbook/LaunchConfiguration.swift` owns debug-only ephemeral fixtures and test launch configuration.

## Route ownership

| Surface | Owner | Notes |
| --- | --- | --- |
| Expenses | `AppShellView.swift`, `ExpenseViews.swift` | Primary list and record actions |
| Summary | `AppShellView.swift`, `SummaryAndNotedViews.swift` | Active-book, currency-separated totals |
| Noted | `AppShellView.swift`, `SummaryAndNotedViews.swift` | Recoverable archive |
| Options | `AppShellView.swift`, `OptionsView.swift` | Grouped settings root |
| New expense | `AppShellView.swift`, `ExpenseEditorView.swift` | Large sheet reached from Add or `pinbook://expense/new` |
| Quick Add | `AppShellView.swift`, `TemplatesAndQuickAddViews.swift` | Uses templates or Favorites to open a fresh expense draft |
| Appearance | `OptionsView.swift`, `PinbookTheme.swift` | Native appearance mode and five skins |
| Books and currencies | `OptionsView.swift`, persistence models | Active-book management and explicit currency favorites |
| Templates | `OptionsView.swift`, `TemplatesAndQuickAddViews.swift` | Create, edit, tombstone, and reuse templates |
| Statements | `OptionsView.swift`, `StatementAndReminderViews.swift` | One person and one ISO currency per export |
| Reminders | `OptionsView.swift`, `StatementAndReminderViews.swift` | Local reminder overview |
| Backup and Recovery | `OptionsView.swift`, `BackupRecoveryView.swift`, service | Native Files export/import, preview, snapshot, apply, and recovery |
| Payments | `ExpenseViews.swift` | Partial payment sheet and remaining balance |
| Receipts | `ExpenseViews.swift`, `ReceiptViews.swift` | PhotosPicker and app-private copies |
| Widgets | `PinbookWidgets.swift`, deep-link handler | Quick Expense and Balance Overview navigation only |

The compact shell has four stable tabs: Expenses, Summary, Noted, and Options. Add is an action, not a fifth tab. Options uses navigation links for detailed settings. Temporary tasks use sheets or system Files workflows without inventing duplicate navigation stacks.

## Invariants

1. SwiftData remains the offline source of truth. Remote transport must stay optional.
2. Money uses signed 64-bit minor units. Floating point is not used for persisted money.
3. Amounts from different ISO currencies are never combined into one total. No implicit exchange rate exists.
4. Every expense belongs to exactly one book. Expenses, Summary, Noted, templates, Favorites, and totals remain isolated by active book.
5. Production bootstrap creates one usable book, repairs an invalid active-book reference, and never creates sample financial records.
6. Returning-user data is never reset by onboarding, language, appearance, or presentation changes.
7. Favorite currencies begin empty. The user explicitly enables them and selects a preferred currency.
8. Quick Add creates a fresh, unstarred, open expense with a new identifier and current occurrence time. It never mutates the source.
9. SwiftData uses `isTombstoned` for soft deletion. Backup serialization retains the Android-compatible `isDeleted` field.
10. Stable identifiers and timestamps drive deterministic merge behavior. Newer records apply; equal-timestamp differences keep the local record.
11. Receipt photos come only from system PhotosPicker selection, are copied into app-private protected storage, and never require broad photo-library access.
12. Receipt import and deletion coordinate file bytes with metadata. A failed metadata write must not leave live metadata pointing to missing bytes.
13. Statements are generated locally for one active-book person and one ISO currency, exclude private notes, preserve exact minor units, protect spreadsheet consumers, and fail on overflow rather than clamp.
14. Reminder authorization is requested only during an explicit reminder-bearing save. Notification text remains generic and private.
15. Local backup exports the complete version-8 envelope. Import fully validates data and references before any financial mutation.
16. Restore preview is non-mutating. A confirmed restore saves an exact pre-restore snapshot before applying changes.
17. Snapshot recovery replaces the saved financial domain while retaining backup history and snapshots.
18. The baseline widgets expose navigation only. Financial widget data requires a separately approved App Group, versioned snapshot contract, privacy review, signing changes, and physical acceptance.
19. Liquid Glass is reserved for navigation and controls. Records, financial values, forms, and recovery content stay on stable readable surfaces.
20. Dynamic Type, RTL, Reduce Motion, Increase Contrast, and Reduce Transparency remain first-class acceptance dimensions.
21. Arabic and Urdu use RTL. User-authored content is not translated.
22. Simulator, unsigned build, archive, upload, processing, TestFlight availability, physical acceptance, and public App Store release are separate evidence states.
23. Presentation work must not alter models, calculations, validation, defaults, permissions, backup formats, or restore semantics without a separate decision.

## Recovery points

| Risk | Recovery point |
| --- | --- |
| Bad source change | Revert the exact Git commit or branch. Never reset an owner's dirty checkout. |
| SwiftData change | Preserve schema compatibility and prove migration or clean bootstrap behavior before release. |
| Invalid backup | Decode and validate before mutation. Reject corrupt, unsupported, or referentially invalid content. |
| Restore mistake | Use the exact pre-restore snapshot created before apply. |
| Restore failure | Transactional apply and staged receipt files must roll back without partial financial mutation. |
| Receipt import failure | Remove copied bytes when metadata save fails. |
| Receipt removal failure | Persist the tombstone before deleting bytes, allowing at worst a recoverable orphan. |
| Release regression | Retain the last accepted TestFlight or App Store build. Never claim recovery from an unprocessed local archive. |
| Visual pilot rejection | Discard the isolated premium pilot worktree. The GitHub foundation baseline and user data remain unchanged. |

## Decisions that must be preserved

- iOS remains native SwiftUI and SwiftData. Android is the behavior reference, not a UI template.
- Google Drive is the preferred future cross-platform transport because Android already uses `drive.appdata`, but it is not implemented in the GitHub baseline.
- iCloud or CloudKit may later implement the same transport boundary as an alternative. Two automatic sync authorities must not run together without a proven authority and conflict design.
- Any future remote bytes must pass through the existing validation, preview, snapshot, and transactional recovery boundary.
- There is no active central Pinbook team-sync backend in the GitHub baseline. Infrastructure or team-delivery prototypes are not production evidence.
- OCR remains an optional, on-device later enhancement behind the existing service boundary.
- Widgets remain privacy-safe navigation unless a separate data-sharing decision is approved.
- The product stays simple: stable primary tabs, grouped settings, one clear Add action, and no duplicate dashboard shortcuts.
- New visual accents should prefer green when a new product choice is required. Existing accepted colors are not changed only to satisfy that preference.

## Current work snapshot

As observed on 2026-09-27, the isolated local branch `codex/premium-experience-pilot` contains uncommitted presentation-only changes across nine SwiftUI/theme files. The Quiet Ledger direction improves stable financial cards, hierarchy, adaptive layouts, settings, statements, reminders, templates, Quick Add, and receipts. A full dedicated-simulator run passed 29 core/application tests and 10 UI tests with zero failures. Final documentation and some continuation screenshots remained incomplete when work paused. The pilot is not committed, pushed, released, or physically accepted and is not part of the GitHub baseline above.

## Durable history

### 2026-09-01

- The repository was bootstrapped and gained `PinbookCore` with currency-safe minor units, Android backup-v8 decoding, validation, and deterministic merge planning.
- A native SwiftUI and SwiftData application foundation added Expenses, Summary, Noted, Options, partial payments, books, currencies, templates, Favorites, Quick Add, receipts, statements, reminders, local Backup and Recovery, widgets, onboarding, accessibility fixtures, and five adaptive skins.
- Automated tests covered clean bootstrap, book isolation, currency separation, backup round trips, recovery, receipts, statements, reminders, accessibility layouts, and system Files presentation.
- TestFlight groundwork prepared version `0.1.0` build `1`, privacy metadata, encryption declaration, app icon, signing settings, and copy-ready submission documentation. This preparation did not itself prove provider processing or tester availability.

### 2026-09-02

- The app icon was brightened at GitHub commit `f78d112`.

### 2026-09-04 local successor record

- Local commits added persistent first-run and Settings language controls plus draft parity for sixteen languages.
- Local handoff records TestFlight build 2 upload and validation. GitHub did not contain these commits when this memory was created, and current App Store Connect status was not independently refreshed here.

### 2026-09-13 to 2026-09-27

- A local premium presentation pilot was built and tested in an isolated worktree. It remains review-only and is not a release claim.
- This root project memory was established as the cumulative architecture and release continuity record.

Detailed validation evidence and limitations remain in `docs/CODEX_HANDOFF.md`, `docs/VALIDATION.md`, and `docs/ARCHITECTURE.md`. This file summarizes durable facts and does not replace those evidence records.

## Meaningful-release memory checklist

For every meaningful release, append a dated entry and update the baseline above with:

1. Version, build number, branch, tag, source commit, and tree state.
2. What changed and why.
3. Architecture or route ownership changes.
4. Invariants added, removed, or revalidated.
5. SwiftData and backup-format compatibility.
6. Swift package, app test, UI test, build, analysis, and archive results.
7. Signing and artifact identity references without secret or profile material.
8. App Store Connect upload, processing, group assignment, TestFlight availability, and public release stated separately.
9. Exact-build physical-device acceptance and unverified paths.
10. Privacy, entitlement, provider, and localization changes.
11. Recovery and rollback points.
12. Exact next actions and remaining risks.

Commit this file with the release documentation and push it to the same GitHub repository. Then update the Pinbook entry in `TC-Company-Control` with a short, secret-free cross-project status. A release is not complete merely because this file changed.
