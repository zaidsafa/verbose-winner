# Default-off local team workspace checkpoint

Updated: 2026-09-05 (Asia/Shanghai)

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
