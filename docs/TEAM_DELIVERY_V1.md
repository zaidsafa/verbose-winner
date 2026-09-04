# Pinbook Team Delivery v1 — implementation contract, draft 2

Date: 2026-09-04. Owner: Pinbook Android; peer: Pinbook iOS (`zaidsafa/verbose-winner`).
Status: **local foundation only; no network feature enabled, no deployment or release**.
This is a cross-platform protocol baseline for review, not a claim of completed team sync.

## Product boundary

- Optional invite-only pilot, initially one team with at most ten members. Personal books,
  existing Room schema 9 and private Drive `drive.appdata` backup remain unchanged.
- OVH + IDrive only for the proposed shared service. No Firebase or public registration.
- Device archives are the lasting content copies. Relay expiry MUST NOT delete an archive.
- Content is made unavailable once every intended recipient has durably saved it, or at
  `acceptedAt + 2,592,000,000` milliseconds, whichever happens first. The thirty days start
  at server acceptance, never first download or last retry. Server time is authoritative.
- A note submission, correction, and review action are distinct immutable delivery events;
  reading/downloading is NOT approval. Reviewer transitions require authorized server checks
  against an expected revision. No last-write-wins for review decisions. Review/event APIs
  are not implemented in this first slice.

## Infrastructure response and ownership

TC Infrastructure replied **NEEDS_INFO** on 2026-09-04. `pinbook` is recorded locally as
REQUESTED, not allocated on the host. No live resource is reserved or provisioned.
Reference: `tc-infrastructure/docs/decisions/PINBOOK_TEAM_DELIVERY_ADMISSION_20260904.md`,
SHA-256 `694a04d820325481f60f281f5c5fdb8e9e7f88d0adf440aba767c636335875e8`.

Infrastructure alone owns admission, buckets/keys, DNS/TLS, host execution, resource limits,
monitoring and infrastructure evidence. Do not connect/deploy directly, reuse a TC database,
network, bucket or key, or alter shared backup jobs. Proposed ceilings remain API 0.25 CPU /
512 MiB and dedicated Postgres 0.5 CPU / 1 GiB. These are not reservations.

**Important correction:** a separate VPS delivery database still enters whole-host snapshots.
Therefore all temporary payloads, including text/title, media, captions and original filenames,
must be client-encrypted objects in a NEW private, never-versioned IDrive delivery bucket.
The backed VPS control database holds only opaque IDs, membership, authorization, revisions,
deadlines and bounded lifecycle metadata. No plaintext payloads, content-derived plaintext
hashes, decryptable message keys, presigned URLs or request bodies in that DB or logs.
Do not mistake provider encryption-at-rest for client/end-to-end encryption.

## Recipient semantics (pilot baseline; pending Infrastructure/iOS review)

- One explicitly enrolled receiving device per member in the pilot; Android and iOS are peers.
  This limits simultaneous devices, not supported platforms. Multi-device fan-out is future work.
- Freeze member + opaque device + enrollment/key-epoch ID. Never reuse an enrollment after
  replacement/reinstall/key rotation. A device ID alone cannot authenticate an old obligation.
- Snapshot all intended peer member/device IDs transactionally at submission. The sender already
  has an atomic local archive and is excluded from recipient ACK obligations. No peers means
  local-only, not an empty-audience server upload. Validate current membership again at access.
- Joining members never extend old delivery lifetimes and do not automatically receive history.
- Membership removal revokes future grants immediately. A removed recipient may be explicitly
  marked CANCELLED by the authorized server membership transaction; cancellation is recorded
  separately from ACK (actor, time, reason) and must not be presented as downloaded. Never
  silently shrink targets. Cancellation authority and the user-facing business rule need pilot
  acceptance; reject contradictory ACKED + CANCELLED state rather than silently choosing one.
- Device replacement does not forge an old-device ACK or reset expiry. Old history comes from
  the member's own archive transfer/backup; missed deliveries need deliberate authorized resend.
- No saved copy + no backup + expired relay means unrecoverable through the relay. Clearly show
  missing/expired items and backup health. Never acknowledge merely because a push was received.

## Delivery and deletion state machine

1. Sender saves an immutable local event; later authenticated submission receives server-issued
   IDs, acceptance time and fixed deadline. Idempotent retries never reset that deadline.
2. Recipient fetches a bounded manifest; access/grants require current membership AND an active
   delivery. A grant must expire within 60 seconds and never after the content deadline.
3. Recipient authenticates/decrypts, validates manifest and every file, atomically persists the
   archive/index and queues its ACK in the same local database transaction. Storage failure,
   invalid key/hash, unsupported version, unavailable attachment or partial download => no ACK.
4. ACK transmission happens only AFTER local commit. Retry on disconnect/process restart.
   Backend derives account/device from verified session, checks exact delivery binding, and
   processes duplicate ACKs idempotently. Self-reported hashes are integrity checks, not proof
   against a malicious recipient. For encrypted wire delivery ACK uses ciphertext/envelope
   identity; the local plaintext text checksum in this foundation MUST NOT be sent to OVH.
5. All targets ACKED/CANCELLED, or deadline reached => access closes, deletion queued immediately.
   Healthy-operation proposal: first purge attempt <=60 seconds, verified provider-API absence
   <=15 minutes. Provider failure => PURGE_OVERDUE + alert, not a false DELETED status.
6. A terminal response retires the local receipt only. The archive is preserved. An in-flight
   verified download finishing after deadline can still be saved locally; server rejects late
   ACK/upload resurrection. Pending mutation must not become a new event automatically.

Thirty days is an **access/retention deadline**, not a promise of physical media sanitization
at an exact instant. Already-issued/in-flight transfers cannot be recalled instantly. Purge
must reconcile outstanding grants, multipart parts, aborted uploads and orphaned objects.
No temporary-payload backup, replication, object lock or version history. Exact deletion
wording, provider guarantees and purge SLO are launch gates, not yet accepted production facts.

## Implemented Android foundation

- `TeamDeliveryRules` / `DeliveryRetention`: bounded thirty-day reference policy, exact expiry,
  frozen targets, explicit revocation, validation and fail-closed unsupported payload handling.
  This is a local reference for server/iOS parity, NOT an executing server cleanup job.
- `TeamInboxDatabase`: separate Room `pinbook-team-inbox.db`, version 1, scoped by account/team/
  delivery. Existing personal DB and Drive serializers do not include these tables.
- `TeamInboxRepository`: validates a **decrypted local text envelope**, then persists archive +
  pending receipt atomically. It does not authenticate, decrypt, call APIs or sign grants.
- Current text ceiling 32 KiB UTF-8, case-sensitive opaque ASCII IDs <=128 chars, integer UTC
  epoch milliseconds. Exact lowercase SHA-256 over unnormalized UTF-8 body. No trimming or
  locale normalization before hashing. JSON implementations must reject invalid Unicode.
- Attachments fail closed (`attachmentCount != 0`). Types exist for future work; no misleading
  media receipt or full-sync UI. No app entry point opens the team DB yet.
- JVM policy/repository tests plus Android Room instrumentation tests. Evidence recorded in handoff.

## Shared local-envelope fields

These fields describe the authenticated/decrypted object inside the app, NOT a public API:
`protocolVersion=1`, `teamId`, `deliveryId`, `noteId`, `authorUserId`,
`recipient={userId,deviceId,enrollmentId}`, `body`, `bodySha256`, `acceptedAt`, `expiresAt`,
`attachmentCount=0`. See `shared/team-delivery-v1-vectors.json` for cross-platform fixtures.
Never expose plaintext body or its digest to the proposed server control-plane contract.

## Recovery and security gates before real users

- Select audited cross-platform authenticated-encryption/key distribution design. Do NOT invent
  a group cryptographic protocol. Specify device enrollment, member removal/key rotation,
  recovery credentials and authenticated reporting without disclosing whole-team archives.
- Select account login, invites, roles, revocation, abuse/report/block and account-deletion APIs.
  Verify identity server-side; never embed server credentials. No public rollout until App Store
  login/privacy/UGC requirements and Google Play declarations are addressed.
- Portable encrypted archive format (not native Room/Swift DB) including media, IDs/revisions,
  integrity manifest, version and recovery information. Test Android -> iOS -> Android restore.
  Own-cloud backup is opt-in and separate from personal Drive merge. Cloud-provider authentication
  and key recovery are separate; a recovered local archive cannot restore revoked server access.
- Exclude team content from incidental OS backup until intentional portable backup consent exists.
  No destructive local cleanup or replacement of private books; restore stages and verifies before
  import. Include manual export/transfer in pilot; cloud backup may follow, not a false recovery claim.
- Provisional admission caps for later review: 10 MiB/object, 5 attachments/note, total 25 MiB/note,
  250 MiB uploaded/team/day, 2 in-flight uploads/device. Only JPEG/PNG/WebP and bounded audio
  MIME allowlist after implementation; currently text-only. No executables, transcription or OCR.
- Bounded retry/queue sizes and rate limits; 500 text submissions/team/day is a pilot quota, not
  a throughput guarantee. Content-free logs proposed 7 days, aggregate metrics 30 days, live
  receipt/dedup metadata through acceptedAt+37 days, all subject to Infrastructure review.
- Infrastructure R2 confirms these are source-planning caps only. Add ciphertext/wire size,
  upload reservations/reconciliation, independent download/retry/abort quotas before enabling
  media; the proposed media ceiling can reach 7.324 GiB stored over thirty days and 2.25 GiB/day
  of nine-recipient downloads before retries. Do not infer zero cost from the text pilot.
- Whole-host snapshots may retain control metadata longer. Define account/metadata retention,
  a content-free deletion journal outside snapshot rollback, and restore fail-closed until terminal
  events/time are verified. No expired payload resurrection after restore. RPO/RTO and personal
  alert recipient still need agreement before deployment.
- Worldwide distribution is intent, not compliance certification. Review target storefronts,
  regional hosting/connectivity constraints and retention exceptions before public activation;
  report material regional blockers to Zaid instead of silently enabling or excluding regions.

## Next implementation slices

1. iOS ports local policy/archive+ACK transaction and runs identical fixtures; coordinate changes here.
2. Agree crypto/auth/recovery and complete non-secret Infrastructure intake; build local backend
   contract, migrations, deterministic expiry/ACK/outbox/restore tests without shared-host access.
3. Android+iOS opt-in team UX, authenticated transport and backup/restore. Complete attachment
   persistence before allowing media ACKs. Validate partial download, disk full, crash, replay,
   foreign team, lost device, expired invite, duplicate send and exact-deadline races.
4. Only after isolated staging admission: synthetic multi-client tests, physical Android+iOS
   acceptance, provider deletion checks and restore rehearsal. Then one-team pilot; observe seven
   representative days before expansion. No signed release scope/version authorized this turn.
