# Team delivery: inactive iOS local foundation

Date: 2026-09-04. Branch: `codex/team-delivery-foundation`.

## Local inbox and restore preparation continuation

`TeamArchiveImport.prepare(fileURL:recoveryKey:expectedAccountId:)` now reads an
opened regular file in bounded chunks before authenticating the archive. It rejects
non-file URLs, NUL paths, final-component symlinks, directories/FIFOs, oversized
input and non-ASCII bytes. The descriptor closes on success/failure. Actual bytes
remain capped if the file grows or reported size is inaccurate. File-provider
coordination, security-scoped permissions, cancellation and background UI scheduling
remain the future Files caller's responsibility; no picker is wired to this API.

The prepared value retains authenticated immutable data, not a path or recovery key.
Standard string/debug descriptions are redacted. UI must discard it on cancellation
or completion; managed value/String copies do not guarantee physical zeroization.
Store preview takes one read snapshot and returns new/identical/conflicting counts
without changing archives or receipts. Confirming uses the same prepared content
and rechecks all current rows inside the write transaction. Stale preview conflicts
abort the whole import. Identical deliveries keep the original savedAt.

`archivePage` provides 1...100 own-account/team notes with a savedAt-descending,
deliveryId-descending keyset cursor. Cursor scope is checked. Reads preserve old
enrollment metadata and do not create ACKs, remove expired archives or grant access.
Each page has its own SELECT snapshot; it is not a snapshot across requests. Newer
notes appear on refresh rather than shifting an offset and repeating previous rows.
No schema, wire, personal-data, signing, version or production entry-point change.

Final release scope and hold: `FINAL_UPDATE_CHECKLIST.md`. Crypto research and its
remaining provider/state-storage gates: `OPENMLS_AUDIT_ADOPTION_20260904.md`.

### Inactive recovery-key custody

`TeamRecoveryKeyStore` adds account/purpose-scoped generic-password items through
Apple Security, with `WhenUnlockedThisDeviceOnly`, synchronizable false, the data
protection Keychain and no shared access group. `storeNew` accepts only 32-byte
keys and uses atomic SecItemAdd: an existing key is an error, never overwritten.
`load` distinguishes not-found from access/lock/decode failures and validates the
returned account, service, accessibility, sync policy and key length. It never
generates a key, and there is no production key deletion/replacement API.

This is convenience storage on the existing device, not off-device recovery.
Intentional recovery-key export/confirmation, consent, rotation/account removal,
loss explanations and device-lock testing remain gates. No key is stored by the
production app yet. Test keys are public fixture bytes in a unique test namespace;
real user Keychain items are never enumerated or modified. Swift/Foundation copies
cannot be promised fully zeroized even though mutable scratch buffers are cleared.
[Apple device-only accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly),
[Apple item lookup](https://developer.apple.com/documentation/security/searching-for-keychain-items).

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

## Implemented local portable archive slice

Android froze `TEAM_ARCHIVE_V1.md`. `TeamPortableArchive.swift` implements its narrow
JWE Compact `dir` / `A256GCM` profile using native CryptoKit: random 256-bit recovery
key, fresh provider-generated 96-bit nonce, 128-bit tag and exact protected-header
bytes. Header base64url ASCII is AAD. Only an empty encrypted-key segment, canonical
unpadded base64url, known header and fixed bounded JSON tuples are accepted. No
compression, alternate headers, passwords or caller-provided encryption nonces.
Authentication completes before plaintext decoding. Mutable plaintext buffers are
best-effort cleared; Swift String/copy zeroization is not guaranteed.

`TeamInboxStore.exportEncryptedAccountArchive` streams one account-wide SQLite
SELECT snapshot into a bounded encoder and returns ciphertext only. Restore
validates the whole authenticated archive before one atomic archive-only import.
Immutable conflicts roll back all inserts; identical records preserve local savedAt.
Historical enrollment remains metadata, not current authority. Existing receipts
and personal data are untouched. No ACK outbox entries, enrollment, membership or
revoked remote access are recreated. Production files/key custody are not wired up.

Node, iOS SQLite-export and Android Room/JCA-returned PUBLIC fixtures are checked
in and pass CryptoKit conformance plus SQLite restore/re-export. Android reports
Room/JCA consumption of the exact iOS fixture at `69822e1`. See
`VALIDATION.md` for hashes and final 36 core / 56 executed Simulator tests. All
fixtures are test-only; they contain no production keys. The ten-member pilot
permits nine peer recipients, excluding the sender.

References: [JWE Compact and authenticated data](https://www.rfc-editor.org/rfc/rfc7516.html),
[JWA algorithms](https://www.rfc-editor.org/rfc/rfc7518), and
[CryptoKit AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm).

This is received-text recovery only, not outgoing drafts, sender submissions,
reviews/revisions or media. Recovery-key custody, import preview/Files cleanup,
cross-platform end-to-end transfer, hardware protection and complete pilot recovery
remain activation gates. It is not a group-key protocol or cryptographic audit.
