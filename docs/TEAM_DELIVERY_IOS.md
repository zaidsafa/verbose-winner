# Team delivery: inactive iOS local foundation

Date: 2026-09-04. Branch: `codex/team-delivery-foundation`.

## Scope and shared contract

This is source-only implementation, not a new release or enabled feature. No app
entry point opens `TeamInboxStore`; no team screens, server client, credentials,
enrollment service, encryption protocol, ACK transport, or infrastructure resources
are introduced. Personal SwiftData models, backup-v8 serializers, app version,
signing settings and existing financial records are untouched.

`TEAM_DELIVERY_V1.md` is the Android-owned draft2 snapshot. The identical fixture
is copied to `Tests/PinbookCoreTests/Fixtures/team-delivery-v1-vectors.json`, bundled
only into tests and consumed by both Swift package and Xcode tests. Update the
shared fixture with Android before changing field semantics.

The mandatory recipient identity is `{userId, deviceId, enrollmentId}`. A fresh
enrollment is required on replacement/reinstall/key rotation. No default enrollment
is synthesized. Policy targets are frozen values, exclude the sender, require one
device/enrollment per member, and reject empty audiences. Authenticated cancellation
is distinct from ACK; contradictory ACK + cancellation sets are rejected. Neither
the local policy nor its arguments authenticate a user or execute server deletion.

## Local persistence

`TeamInboxStore(applicationSupportDirectory:target:teamId:)` creates only a dedicated
`PinbookTeamInbox/team-inbox.sqlite` directory/database. It is not instantiated by
the production app. Before any content is written, both paths are excluded from
OS backup, directory/file permissions are restricted, and iOS Complete file
protection is requested and verified on hardware before opening the store. SQLite rollback journals inherit the containing backup
exclusion/protection boundary. The database is not SQLCipher and these OS controls
are not end-to-end encryption or the future portable encrypted backup format.

Persistence uses SQLite schema 1 with DELETE journaling, `synchronous=EXTRA`,
`fullfsync=ON`, foreign keys and memory-only temporary storage. A private lock plus
`BEGIN IMMEDIATE` serializes each archive/receipt transaction across both threads
and independent connections. The archive and outbox commit together or neither
does; storage errors propagate before successful receive. A failed rollback closes
and invalidates the connection so it cannot expose an indeterminate outbox. SQL failures expose
numeric codes, not bodies, SQL text, content hashes or credentials.

References: [SQLite synchronization guarantees](https://www.sqlite.org/pragma.html#pragma_synchronous)
and [Apple backup exclusion](https://developer.apple.com/documentation/foundation/urlresourcekey/isexcludedfrombackupkey).
Automated tests do not prove power-loss behavior or actual encrypted Finder/iCloud
backup restoration on a physical phone. The iOS 26.5 Simulator returns no hardware
file-protection attribute; the explicit hardware test is disabled only for Simulator
and remains a required physical-device gate. Backup exclusion and POSIX permissions
are still asserted on Simulator; no skipped check is counted as passed.

- Archive identity: account + team + delivery; immutable envelope includes the
  target enrollment, body digest, author, note, acceptance/deadline and media count.
- Incoming envelopes must match the store's expected account/device/enrollment/team.
  Exact duplicate delivery preserves `savedAt`; changed metadata/content is rejected.
- Body SHA-256 covers exact, unnormalized UTF-8 bytes, maximum 32 KiB. Invalid UTF-8
  JSON or unpaired escaped surrogates are rejected. The digest is LOCAL ONLY and the
  receipt type intentionally has no Codable/wire serializer.
- All media fails closed, including negative/nonzero attachment counts. No content
  receipt is emitted for missing/unverified attachments; media is not implemented.
- Pending receipts survive close/reopen. The queue is capped at 1,000 per
  account/device/enrollment; reads are scoped to team and capped at 1...100. A full
  queue rejects a new receive atomically without deleting any archived item.
- Receipt retirement requires exact account/team/delivery/device/enrollment/hash
  matching. The method assumes a future authenticated server result; it does not
  validate one itself. There is no archive deletion operation.
- Expiry never deletes archives. A verified in-flight download can commit after
  expiry; server eligibility for its ACK remains a server decision. New enrollments
  can read an existing own-account local archive but cannot send/retire the old
  enrollment's receipt or overwrite that immutable delivery.

## Required gates before activation

Infrastructure remains NEEDS_INFO; no shared host or IDrive access is permitted by
this slice. The backed control database must never contain plaintext text/media,
plaintext content hashes, decryptable keys, grants or payload-bearing logs. All
temporary content belongs in client-encrypted objects in a newly admitted private,
never-versioned bucket; no E2EE implementation or physical deletion SLA is claimed.

Agree audited crypto, authentication, enrollment/key rotation, recovery and
revocation before transport. Implement durable sender submission separately;
the current store handles received text only. Implement portable encrypted archive
export/import with Android -> iOS -> Android validation before real-user pilot.
Neither a raw SQLite copy nor existing personal backup-v8 fulfills that gate.

Remaining validation includes abrupt-process/power-loss and real disk-full faults,
hardware locked-device behavior, actual OS-backup exclusion, authenticated replay
and revocation, network retries, full durable media verification, encrypted archive
transfer and provider purge/restore rehearsal. Existing transaction-trigger fault
tests establish rollback, not every underlying storage/device failure mode.

Worldwide publishing remains an intent, not compliance certification. No release,
public activation, App Store metadata change, or phone connection is needed here.

## Evidence

See `CODEX_HANDOFF.md` and `VALIDATION.md` for the final commands, outcomes and
source-publication status. No physical-device result is claimed for this slice.
