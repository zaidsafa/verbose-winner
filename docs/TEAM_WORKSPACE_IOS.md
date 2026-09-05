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
  session generation before and after dispatch. Account deletion checks before
  dispatch, then records authenticated acceptance because success may revoke
  that session immediately. It records a stable operation before the remote
  call and requires an idempotent authenticated
  server result. Rejection preserves every local item. After acceptance, a
  restart-safe journal requires idempotent cleanup of the account/team cache and
  archive, agreement key, device signing identity, Terms acceptance and session.
  Completion is impossible while any stage remains pending; no partial built-in
  custody implementation can be mistaken for complete deletion.

## Evidence

- Focused `TeamWorkspaceTests`: **9/9 pass**.
- Complete Swift package: **395 tests in 38 suites pass**.
- The compiled Release app contains all **16 `.lproj` catalogs**. Direct checks
  of Arabic, Urdu, Simplified Chinese and Traditional Chinese Team-workspace
  values match their source-catalog translations.
- `PrivacyInfo.xcprivacy` and `project.pbxproj`: `plutil` pass.
- Unsigned Release iOS Simulator build: **BUILD SUCCEEDED** for arm64 and x86_64
  using `/private/tmp/pinbook-composition-derived`.
- `git diff --check`: pass.

## Explicit boundary

The visible screen is a default-off local shell, not working production sync.
No production origin, live session, server moderation/deletion route,
push schedule, phone, provider, TestFlight or release action was enabled. The
server must finish and freeze journal-v2 acceptance and moderation/account
contracts before these controls can become active. Full localization is complete;
visual/accessibility acceptance and actual injected end-to-end behavior remain
required before a final TestFlight candidate.
