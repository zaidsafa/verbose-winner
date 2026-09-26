# Default-off local team workspace checkpoint

Updated: 2026-09-27 (Asia/Shanghai)

## 2026-09-27 recovery-key readiness guidance

- The recovery screen reads the device-only key store and displays a single
  checking, saved, missing or unavailable status.
- Saved guidance keeps the archive and separate key-copy requirement visible.
  Missing guidance explains that a separately saved key can still import and that
  Pinbook cannot decrypt the archive without it.
- Unavailable custody is never treated as missing, deleted or replaced.
- Complete serial Swift **424/424 in 39 suites**, localization **423 keys across
  16 locales**, and unsigned arm64+x86_64 Release Simulator build pass.

## 2026-09-27 recovery privacy and imported-key retention

- Recovery content is privacy-sensitive and receives an opaque inactive-scene
  cover before the user returns to the app.
- Imported keys are never saved by default. A separate unchecked toggle grants
  explicit consent for device-only retention after archive authentication.
- A different existing key is never replaced. Exact repeats and ambiguous
  matching Keychain insertion are reconciled by exact read-back.
- A retention failure cancels the prepared preview and prevents restoration.
- Complete serial Swift **424/424 in 39 suites**, localization **416 keys across
  16 locales**, and unsigned arm64+x86_64 Release Simulator build pass. Physical
  privacy acceptance, full archive recovery and cross-platform acceptance remain
  open.

## 2026-09-27 connected recovery integration

- A connected Team workspace now receives one exact recovery context containing
  its account ID, protected inbox, device-only recovery-key custody and guarded
  recovery session.
- The visible workspace shows one simple received-note recovery link only while
  that exact context is available. Disabled, disconnected and deletion-blocked
  runtimes expose no recovery destination.
- Export, import preview and restore confirmation recheck the account-global
  deletion gate. Retaining a previously issued context cannot recreate or export
  account data after deletion starts.
- Recovery remains intentionally limited to received text notes. It does not
  restore remote authority, sent drafts, revisions, attachments or ACK receipts.
- Complete serial Swift **420/420 in 39 suites**, localization **392 keys across
  16 locales**, and unsigned arm64+x86_64 Release Simulator build pass. No live
  Team origin, provider, server, signing, device or TestFlight state changed.

## 2026-09-27 durable new-note drafts

- The connected composer restores one protected exact-enrollment note draft and
  exposes explicit Save draft and Discard draft actions.
- Saving is local. It does not accept Terms, finalize an event, encrypt content,
  upload bytes, or create a review decision.
- Sending after Terms acceptance updates and finalizes the same draft identity,
  then continues through the existing exact JWE retry path. A failed submission
  remains in the protected outbox.
- Discard removes only the new-note draft. Correction and review drafts remain
  untouched and hidden until their shared encrypted payload is approved.
- Complete serial Swift **422/422 in 39 suites**, localization **397 keys across
  16 locales**, and unsigned arm64+x86_64 Release Simulator build pass.

## 2026-09-27 localized action guidance

- Dynamic workspace status now uses localizable keys rather than verbatim English.
- Typed failures provide a direct safe next step for Terms, busy work,
  unavailable setup, deletion, connection, reauthentication, missing items,
  uncertain results, full outbox and protected-store failure.
- Guidance never includes identifiers, endpoints, credentials or raw provider and
  server errors.
- Localization was complete at **408 keys across 16 locales** at this checkpoint.
  The later recovery privacy checkpoint supersedes the aggregate count.

## Implemented locally

- Options now contains a polished Team workspace screen describing connection,
  invitation, encrypted note, inbox, safety and account actions. Production
  actions remain disabled until an authenticated runtime is injected.
- A validated `TeamInvitationLink` is the single source for both QR bytes and
  `ShareLink`; no second token copy or alternate URL grammar is accepted.
- Team Terms acceptance is explicit, versioned, account/team scoped and stored
  locally without credentials or note content. The send coordinator checks it
  before creating any upload work.
- Manual text-note preparation creates a durable plaintext event, encrypts the
  canonical payload for the exact current audience, freezes the canonical JWE
  and submit intent in the protected SQLite outbox, and reuses those exact bytes
  after failure. Only exact authenticated accepted/cleanup/purged status retires
  the outbox item.
- Manual new-note drafting is now connected to the production-default-off
  workspace. Save and discard are explicit, reopening restores the saved body,
  and send finalizes that same draft rather than creating a duplicate.
- One bounded foreground inbox refresh lists pending deliveries, reconstructs
  the sender-excluded recipient audience, fetches/decrypts/imports, commits the
  protected archive plus receipt, and only then attempts ACK. Failed ACKs remain
  durable for the next manual refresh; the archive is never removed.
- Report-note, report-user, block-user and account-deletion coordinators validate
  local scope and call only injected interfaces. No HTTP paths were invented.
- The privacy manifest now declares linked, non-tracking user and device
  identifiers used for team functionality. Existing Sign in with Apple source
  adapter is surfaced only as disabled UI scaffolding; no entitlement changed.
- Every visible Team workspace, Terms, report, block, Apple sign-in and delete-
  account string now has a human translation in all 15 non-source catalogs,
  with English as the source language. Arabic and Urdu inherit the app's tested
  right-to-left environment; Simplified and Traditional Chinese are distinct.
- `TeamWorkspaceRuntimeConfiguration.productionDefault` is explicitly disabled.
  The injected account composition treats Apple and Google through the same
  challenge, exchange and exact-generation session path. A connected composition
  can only be constructed from an existing session, protected stores, agreement
  custody and a transport satisfying every workspace interface; it contains no
  built-in origin, credential or fallback endpoint.
- Every ordinary injected remote operation is checked against the exact live
  session generation before and after dispatch. Account deletion now uses a
  separate default-off, account-global recovery state machine matching migration
  027's one-deletion-per-account rule. Its immutable binding contains no team ID;
  cleanup implementations must enumerate every exact team-scoped item belonging
  to that account. All teams for the account share one startup gate.
- The restart journal is protected, backup-excluded SQLite using synchronous
  `EXTRA` commits, not UserDefaults. `PREPARED` and `DISPATCHED` checkpoints must
  commit before their following side effects; a failed save prevents dispatch.
  The 32-byte random status credential remains only in non-synchronizing,
  ThisDeviceOnly Keychain and is encoded as canonical 43-character unpadded
  base64url on the wire.
- Wire bodies exactly match frozen 027: authenticated request
  `{type,requestId,confirmation:'DELETE_ACCOUNT',statusToken}` and unauthenticated
  status `{type,deletionId,statusToken}`. The only states are
  `REVOCATION_REQUIRED`, `CLEANUP_SCHEDULING_REQUIRED`, `PENDING_ERASURE`, and
  `COMPLETED`; there is no successful rejection state. Transport and
  `invalid_credentials` outcomes remain ambiguous. A newly authenticated caller
  may repeat only the exact durable request ID/token after an ambiguous boundary.
- A real pre-session app-start seam enumerates account-global records without a
  live `TeamAccountSessionSnapshot`. Only an authoritative response with
  `authorityRevokedAt` begins idempotent local cleanup; recovery metadata and the
  status token remain until authoritative `COMPLETED`. The production runtime is
  still default-off pending server 028 and Infrastructure staging.

## Evidence

- Focused `TeamWorkspaceTests`: **16/16 pass**, including account-global gating,
  pre-session recovery, exact idempotent retry, failed-checkpoint no-dispatch,
  frozen-state progression, ambiguity preservation, durable SQLite reopening,
  exact-account isolation and idempotent cleanup-after-side-effect.
- Complete Swift package: **402 tests in 38 suites pass**.
- The compiled Release app contains all **16 `.lproj` catalogs**. Direct checks
  of Arabic, Urdu, Simplified Chinese and Traditional Chinese Team-workspace
  values match their source-catalog translations.
- `PrivacyInfo.xcprivacy` and `project.pbxproj`: `plutil` pass.
- Unsigned Release iOS Simulator build: **BUILD SUCCEEDED** for arm64 and x86_64
  using `/private/tmp/pinbook-account-global-deletion-derived`.
- `git diff --check`: pass.

## Explicit boundary

The visible screen is a default-off local shell, not working production sync.
No production origin, live session, HTTP deletion/status adapter, concrete secure
cleanup, push schedule, phone, provider, TestFlight or release action was enabled.
Migration 027 is the implemented client contract; server 028 revocation/cleanup
workers, Infrastructure staging, physical-device Keychain acceptance and actual
injected end-to-end behavior remain required before activation or a final candidate.
