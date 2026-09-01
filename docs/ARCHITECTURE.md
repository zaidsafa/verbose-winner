# Pinbook iOS architecture

## Product boundary

Pinbook is offline-first. Local persistence is authoritative while the app runs. Synchronization is an explicit replication concern, not a replacement for the local store. Money is stored as signed 64-bit minor units and totals are never combined across ISO currency codes.

The compatibility reference is Android Pinbook 0.4.2 (`versionCode 8`) at `442ae6a5bd2dc8ee26d6a1006dd9dda9fe4c0985`. Backup decoding supports format versions 1 through 8 and models the fields in `shared/pinbook-backup-v8.schema.json` from that source.

## Layers

- `PinbookCore`: platform-neutral records, backup decoding, currency-safe money, deterministic merge policy, and service ports.
- `Pinbook`: SwiftUI app, SwiftData persistence, local preferences, and feature presentation.
- Platform services: future adapters for Google Drive `appDataFolder`, receipt files, PDF/CSV statements, local notifications, and Vision OCR.

## Book and currency invariants

- Every expense belongs to exactly one book through `bookID`.
- Expenses, Summary, and Noted are filtered by `AppearanceSettingsItem.activeBookID`; records from another book never contribute to counts or currency totals.
- The active book cannot be archived. Archived books remain recoverable and can be renamed or restored.
- Production bootstrap creates one unarchived `Pinbook` book and repairs an invalid active-book reference without creating sample financial records.
- Favorite currencies start empty. Users explicitly enable currencies and choose the preferred currency used to seed new expense entry.
- Expense Favorites and templates are separate concepts, matching the backup model: starring an expense makes it a Quick Add source, while a named template stores reusable expense fields. Both are isolated to the active book.
- Quick Add always creates a fresh, unstarred, open expense with a new identifier and current occurrence timestamp; it never mutates the source favorite or template and never copies reminder delivery state.
- SwiftData models use `isTombstoned` for soft-deletion state because `isDeleted` collides with SwiftData model lifecycle state. Backup records continue to encode the Android-compatible `isDeleted` field at the serialization boundary.

## Planned boundaries, not implemented claims

- Drive will use per-user authorization with only `drive.appdata`; tokens must remain in memory or protected system storage and no central Pinbook backend is planned.
- Google Drive is the first planned transport because it preserves Android/iOS interoperability. Apple does not require iCloud for App Store distribution.
- A future iCloud/CloudKit adapter may implement the same `BackupTransport` port as an alternative provider. Automatic Google Drive and iCloud replication must not run simultaneously until a single-authority and cross-provider conflict design is proven.
- Sync will stage remote data, present a restore preview, retain undo snapshots, and apply deterministic merge results transactionally.
- Receipts will be copied into app-private storage and represented in backup data.
- Statements will remain grouped by person and currency.
- Reminders will use local notifications only after explicit permission.
- OCR will be an optional on-device enhancement behind `ReceiptTextRecognizing`.

No adapter above is implemented in the initial foundation, and the UI must label unavailable actions accordingly.

## Localization and accessibility

SwiftUI strings use localized keys and a string catalog seeds English plus Arabic top-level navigation. Layout code uses semantic leading/trailing alignment and system Dynamic Type. The validation plan requires RTL, VoiceOver, Reduce Transparency, Increase Contrast, light/dark, and accessibility-size checks before release.
