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
- https://developers.google.com/identity/protocols/oauth2/native-app
- https://developers.google.com/identity/openid-connect/reference#revoke

## Implemented inactive guard and evidence

`BackupTransport` now exposes only paginated inventory, bounded download and
immutable append. It has no update or delete method. `BackupTransportGuard`
validates redacted opaque metadata, follows every page, rejects cursor loops and
duplicate object/operation identities, caps inventory, verifies exact byte count
and SHA-256 after download, and rejects an append receipt that does not match the
persisted operation identity, creation time, bytes and digest.

`PersonalCloudUploadOwner` now owns the crash-safe write boundary. It first asks
the selected provider for an idempotent create identity, then stores that identity,
creation time, exact byte count and SHA-256 in the app's protected,
non-synchronizing Data Protection Keychain before upload. An ambiguous failure or
app restart can reuse that identity only for the same bytes and timestamp.
Different content and a second concurrent dispatch fail closed; the reservation
clears only after an exact verified provider receipt. Backup bytes, account
identity, filenames and credentials never enter this state.

`GoogleDriveBackupTransport` implements the inactive Drive v3 wire boundary with
only the `drive.appdata` scope: pre-generated `appDataFolder` file IDs, complete
page-token inventory, strict private `appProperties`, exact bounded media reads,
and multipart immutable create. A 409 retry is accepted only after both metadata
and remote bytes match the reserved operation. Its ephemeral bearer is redacted;
bounded fresh sessions reject redirects, cookies and compressed responses.

`PersonalGoogleDriveOAuthRequest` and `PersonalGoogleDriveTokenClient` now provide
the next disconnected authorization boundary. They require a real allocated iOS
client ID and registered reversed-client callback, use fresh AppAuth state/nonce
and S256 PKCE, request only `drive.appdata` with explicit offline consent, send no
client secret, and strictly parse single-flight, one-use code/refresh exchanges.
Concurrent requests fail busy, and access plus optional refresh lifetimes are
bounded. Personal Drive grants are redacted and remain isolated from team Google
sign-in. Refresh tokens now persist only in the non-synchronizing, device-only
Data Protection Keychain. Stored records bind a client-ID hash, generation,
time, optional expiry and active/revocation-pending phase; access tokens remain
memory-only. Refresh rotation is generation-bound.

Explicit disconnect first writes a durable revocation-pending fence so refresh
cannot race remote revocation. The one-use bounded revocation client accepts only
Google's authoritative empty 200 or exact already-invalid response before deleting
that same Keychain generation. Failure/cancellation retains the fenced token for
an explicit retry. This is intentionally isolated from team Google authorization;
the real personal-Drive client should use a dedicated Google project because
revocation can invalidate every OAuth scope granted to that project.

`PersonalGoogleDriveAuthorizer` now owns the disconnected AppAuth presentation
boundary. It requires explicit consent, the allocated reversed-client scheme in
the installed bundle and a usable foreground presenter. One pending request keeps
its exact state and S256 verifier; only a bounded matching callback is handed to
AppAuth and it is consumed once. The ephemeral browser is cancelled on background,
caller cancellation or a monotonic ten-minute deadline. If cancellation races a
successful code exchange, the driver attempts isolated refresh-token revocation
before settling. It returns a redacted in-memory grant only; its connection owner
must durably save it, or revoke it on any save/ownership failure, before reporting
connection success.

`PersonalGoogleDriveConnectionOwner` now closes that custody gap. It refuses an
existing active or fenced record before opening the provider and allows one
attempt at a time. After authorization, the refresh token is atomically persisted
as an unusable revocation-pending Keychain generation before a second exact CAS
activates it. Cancellation or activation failure performs revocation outside the
cancelled caller and deletes only that fenced generation. Ambiguous cleanup stays
fenced and returns `cleanupRequired`; it never becomes a connected state.

- Focused transport/owner/Drive tests: **15/15 PASS** on the separate physical
  iPhone QA app, including a real Keychain reopen/clear; Drive wire tests use an
  isolated synthetic executor and make no real provider call.
- Complete personal Drive browser/authorization/custody/revocation boundary:
  signed Simulator and separate physical iPhone QA app **26/26 PASS**, including
  real staged Keychain activation/reopen/delete. No provider request was made.
- Complete Swift core: **366/366 PASS**, 35 suites.
- Earlier pre-connection signed iOS 26.5 Simulator app-host baseline: **372 PASS
  + 4 expected physical-only SKIPS**, 376 total, 0 failures. The exact current
  connection source is covered by the focused signed 26/26 run above.
- Ordinary unsigned production Release: **BUILD SUCCEEDED** with unchanged bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.

Exact paths and the initial sandbox-blocked attempt are recorded in
`VALIDATION.md`. The Drive adapter is not connected: this source still has no
allocated personal-Drive client configuration, production callback wiring,
iCloud adapter, scheduler, real remote
bytes, automatic merge or production UI entry. The existing TestFlight build was
not replaced.
