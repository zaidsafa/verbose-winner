# Pinbook iOS architecture

## Product boundary

Pinbook is offline-first. Local persistence is authoritative while the app runs. Synchronization is an explicit replication concern, not a replacement for the local store. Money is stored as signed 64-bit minor units and totals are never combined across ISO currency codes.

The compatibility reference is Android Pinbook 0.4.2 (`versionCode 8`) at `442ae6a5bd2dc8ee26d6a1006dd9dda9fe4c0985`. Backup decoding supports format versions 1 through 8 and models the fields in `shared/pinbook-backup-v8.schema.json` from that source.

## Layers

- `PinbookCore`: platform-neutral records, backup decoding/validation, currency-safe money, deterministic merge plans with per-entity previews, and service ports.
- `Pinbook`: SwiftUI app, SwiftData persistence, local preferences, versioned onboarding, deep-link routing, and feature presentation.
- `PinbookWidgets`: two privacy-safe WidgetKit entry points. Quick Expense routes to a new expense sheet and Balance Overview routes to Summary; neither reads or displays financial data.
- Platform services: implemented native Files backup documents, transactional local restore/recovery, private receipt files, local PDF/CSV statements, and local notifications, plus future adapters for Google Drive `appDataFolder`, CloudKit, and Vision OCR.

## Book and currency invariants

- Every expense belongs to exactly one book through `bookID`.
- Expenses, Summary, and Noted are filtered by `AppearanceSettingsItem.activeBookID`; records from another book never contribute to counts or currency totals.
- The active book cannot be archived. Archived books remain recoverable and can be renamed or restored.
- Production bootstrap creates one unarchived `Pinbook` book and repairs an invalid active-book reference without creating sample financial records.
- Favorite currencies start empty. Users search Foundation's complete common ISO currency catalog and see a deterministic symbol tile, ISO code, and localized name before explicitly enabling currencies and choosing the preferred currency used to seed new expense entry. Ambiguous symbols never replace the ISO code.
- Expense Favorites and templates are separate concepts, matching the backup model: starring an expense makes it a Quick Add source, while a named template stores reusable expense fields. Both are isolated to the active book.
- Quick Add always creates a fresh, unstarred, open expense with a new identifier and current occurrence timestamp; it never mutates the source favorite or template and never copies reminder delivery state.
- SwiftData models use `isTombstoned` for soft-deletion state because `isDeleted` collides with SwiftData model lifecycle state. Backup records continue to encode the Android-compatible `isDeleted` field at the serialization boundary.

## Local service boundaries

- Receipt photos use system `PhotosPicker`, which grants access only to the item a user selects. Bytes are copied immediately to `Library/Application Support/Receipts` under generated UUID filenames with complete-until-first-authentication file protection; SwiftData stores only attachment metadata.
- Receipt imports compensate by removing the copied file if metadata persistence fails. Removal persists the metadata tombstone before deleting private bytes, so a failed save retains a live file/reference pair; a later file-removal failure can leave only a recoverable orphan, never live metadata pointing to a missing file. Traversal-style filenames are rejected by the store boundary.
- Statements are generated on device and contain exactly one active-book person and one ISO currency. CSV uses exact minor-unit integers with a UTF-8 BOM and CRLF rows, prefixes formula-leading user fields (`=`, `+`, `-`, or `@`) with an apostrophe, and never silently clamps arithmetic overflow. PDF pages always paint a fixed white print background with black/dark-gray text regardless of app appearance, format values for reading, and state that no exchange rate was applied. Generated files live in temporary, backup-excluded storage until the system share workflow consumes them.
- Reminder authorization is requested only when the user saves an expense with a reminder. The notification title/body are generic and contain no purpose, person, amount, or currency. Pinbook cancels the pending request when the reminder is cancelled or the expense is marked noted; a failed SwiftData save compensates by cancelling any request scheduled for that expense.
- Manual backup exports the Android-compatible version-8 envelope through the system Files workflow, including receipt bytes. Import fully decodes, validates identifiers/currencies/receipt content and record references, then presents deterministic add/update/unchanged/conflict counts before any financial mutation. Newer records apply, equal-timestamp differences keep the local record, and currencies remain attached to individual records without conversion.
- Every confirmed restore persists an exact local pre-restore snapshot before applying the merge. Snapshot recovery replaces the financial domain with that saved state while retaining backup history and snapshots. Receipt bytes are staged before SwiftData mutation, failed operations roll back and remove staged files, and privacy-safe activity stores only action/status/time/format/counts and opaque error codes.

## Planned synchronization boundaries, not implemented claims

- Drive will use per-user authorization with only `drive.appdata`; tokens must remain in memory or protected system storage and no central Pinbook backend is planned.
- Google Drive is the first planned transport because it preserves Android/iOS interoperability. Apple does not require iCloud for App Store distribution.
- A future iCloud/CloudKit adapter may implement the same `BackupTransport` port as an alternative provider. Automatic Google Drive and iCloud replication must not run simultaneously until a single-authority and cross-provider conflict design is proven.
- The inactive cross-platform safety contract uses immutable append-only snapshots,
  complete bounded pagination and a persisted idempotent upload identity instead
  of overwriting one mutable remote file. See `PERSONAL_CLOUD_SYNC_V1.md`.
- A future sync adapter must feed remote bytes into the implemented validation, restore-preview, snapshot, and transactional-apply boundary rather than bypassing it.
- OCR will be an optional on-device enhancement behind `ReceiptTextRecognizing`.

Drive, CloudKit, OAuth, and OCR adapters remain unavailable. The implemented Backup & Recovery UI is provider-independent and local-only.

## Localization and accessibility

SwiftUI strings use localized keys with complete English, Arabic, and Simplified Chinese coverage for the implemented workflows, onboarding, accessibility labels, and widgets. Layout code uses semantic leading/trailing alignment and system Dynamic Type. The validation plan requires RTL, VoiceOver, Reduce Transparency, Increase Contrast, Reduce Motion, light/dark, and accessibility-size checks before release.

The onboarding completion flag is versioned (`pinbook.onboarding.completed.v1`), so a new user receives four short task-oriented pages while a returning user's financial store is preserved. Skip and completion persist the flag; Options can clear only that presentation flag to replay the introduction. Debug UI fixtures remain ephemeral and explicitly skip onboarding unless a test override requests it.

All five skins resolve accent, content surface, and backdrop colors from the active light/dark trait. Primary text stays semantic, the selector uses distinct SF Symbols plus palette previews and descriptions, and native transitions become static when Reduce Motion is enabled. Widget layouts use system families, tint-compatible SwiftUI content, and privacy-safe copy.

Live widget balances would require a separately approved App Group plus a carefully versioned shared snapshot boundary. No App Group, iCloud container, or developer-account capability is enabled in this milestone.

Scrollable Forms and Lists that end behind the floating Liquid Glass tab bar reserve a shared 128-point content clearance. UI automation verifies the final Books row, Statements help card, and Backup & Recovery privacy footer can be scrolled to a hittable frame fully above the tab bar.
