# Pinbook personal cloud sync v1 — inactive contract

Updated 2026-09-05. This is a provider-neutral safety contract, not an enabled
Google Drive or iCloud feature. No OAuth client, entitlement, token, remote file,
automatic schedule or user-facing cloud claim is added by this checkpoint.

## Provider decision

- Google Drive is the first planned provider because the existing backup-v8 data
  model is shared by Android and iOS. Use only the narrow
  `https://www.googleapis.com/auth/drive.appdata` scope.
- iCloud may implement the same contract later as an alternative selected by the
  user. Drive and iCloud must not replicate automatically at the same time until
  a tested cross-provider authority and conflict design exists.
- Manual Files export/import remains available and is not described as automatic
  cloud sync. Selecting iCloud Drive or another Files destination is a user-led
  file transfer, not a Pinbook provider connection.

## Immutable remote model

Never overwrite one mutable `pinbook-backup.json` after a read. Every successful
sync appends an immutable backup-v8 snapshot with a random operation identity,
creation time, exact byte count and SHA-256. The client persists the operation
identity before starting the upload. A lost response retries that same identity;
it must not create a new logical snapshot or silently report success.

For Google Drive, reserve and persist a pre-generated file ID before upload so an
ambiguous create can be retried idempotently. Never use an undocumented ETag or a
last-modified timestamp as a correctness guard. Conflicting bytes under the same
operation identity fail closed and require recovery, rather than choosing a winner.

## Read and merge rules

- Search only `appDataFolder`. Follow every `nextPageToken`; a first page is not
  a complete inventory. Bound pages, objects, cursor bytes, metadata and total
  work per run. Reject duplicate logical identities with changed metadata.
- Bound every response while streaming. A declared or observed payload above the
  existing 128 MiB local backup ceiling fails before decode or local mutation.
- Authenticate the full downloaded bytes against their recorded SHA-256, then use
  the existing backup-v8 decoder, validation, deterministic preview/merge,
  pre-restore snapshot and transactional apply path. Provider bytes never bypass
  those gates.
- Local data wins equal `updatedAt` ties. Money remains separated by ISO currency;
  no conversion is introduced by sync. Receipt bytes and references must validate
  together or the entire candidate fails.
- Automatic application must still create a recoverable local pre-sync snapshot
  and privacy-safe history entry. A failed download, decode, merge, local commit or
  upload keeps the last known local state and never deletes the remote snapshots.

Remote pruning/compaction is disabled until multiple-device crash, late-response,
concurrent-append, duplicate, pagination restart and restore tests prove that at
least one complete recoverable generation survives every interruption.

## Credentials, privacy and release gates

OAuth access is explicit and revocable. Access/refresh material belongs only in
memory or protected system credential storage and must never enter SwiftData,
backup JSON, logs, analytics, Git or TestFlight notes. Disconnect stops future
work but does not silently delete local records or provider data.

Before release: configure real provider clients, test consent/revocation and token
expiry, update App Privacy and `PRIVACY_POLICY.md`, localize all provider states,
and run Android-to-iOS-to-Android physical recovery with synthetic data. Until
then the production UI must continue to say that no cloud provider is connected.

Official implementation references:

- https://developers.google.com/workspace/drive/api/guides/appdata
- https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list
- https://developers.google.com/workspace/drive/api/guides/manage-uploads

## Implemented inactive guard and evidence

`BackupTransport` now exposes only paginated inventory, bounded download and
immutable append. It has no update or delete method. `BackupTransportGuard`
validates redacted opaque metadata, follows every page, rejects cursor loops and
duplicate object/operation identities, caps inventory, verifies exact byte count
and SHA-256 after download, and rejects an append receipt that does not match the
persisted operation identity, creation time, bytes and digest.

- Focused guard tests: **5/5 PASS**.
- Complete Swift core: **337/337 PASS**, 30 suites.
- Signed iOS 26.5 Simulator app-host: **362 PASS + 4 expected physical-only
  SKIPS**, 366 total, 0 failures.
- Ordinary unsigned production Release: **BUILD SUCCEEDED** with unchanged bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.

Exact paths and the initial sandbox-blocked attempt are recorded in
`VALIDATION.md`. This source still has no Drive/iCloud adapter, token, scheduler,
remote bytes, automatic merge or production UI entry.
