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

## Evidence

- Focused `TeamWorkspaceTests`: **6/6 pass**.
- Complete Swift package: **392 tests in 38 suites pass**.
- `PrivacyInfo.xcprivacy` and `project.pbxproj`: `plutil` pass.
- Unsigned Release iOS Simulator build: **BUILD SUCCEEDED** for arm64 and x86_64
  using `/private/tmp/pinbook-workspace-derived`.
- `git diff --check`: pass.

## Explicit boundary

The visible screen is a default-off local shell, not working production sync.
No production origin, session, server moderation/deletion route, runtime adapter,
push schedule, phone, provider, TestFlight or release action was enabled. The
server must finish and freeze journal-v2 acceptance and moderation/account
contracts before these controls can become active. The new workspace copy also
needs complete 16-language localization and visual/accessibility acceptance
before a final TestFlight candidate.
