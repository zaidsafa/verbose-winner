# Pinbook iOS project memory

Updated: 2026-09-27, Asia/Shanghai

This file is the secret-free continuity record for Pinbook iOS. Exact test logs,
screenshots, commands, and chronological implementation detail remain in
`docs/VALIDATION.md` and `docs/CODEX_HANDOFF.md`.

Never add OAuth tokens, refresh tokens, passwords, private keys, signing assets,
provisioning profiles, customer records, private notes, raw sessions, tester
contact details, or unredacted provider output to this file.

## Maintenance contract

Update this file in the same pushed milestone as every meaningful release or
architecture change. A meaningful milestone includes:

- a user-facing feature or fix;
- a data, backup, synchronization, security, or route-contract change;
- a version or build-number change;
- a signed candidate, TestFlight state change, or store decision;
- a provider, server, infrastructure, entitlement, or capability change;
- an accepted or rejected product decision;
- a new recovery point or a superseded recovery point.

For each milestone:

1. Fetch the current application branch and current `TC-Company-Control`
   guidance.
2. Update the baseline, architecture, routes, invariants, decisions, recovery
   points, evidence, limitations, and next actions here.
3. Add detailed evidence to `docs/CODEX_HANDOFF.md` and `docs/VALIDATION.md`.
4. Update `TC-Company-Control/projects/pinbook-ios.md` and its registry entry.
5. Commit, push `origin/codex/team-delivery-foundation`, and verify the remote
   hash exactly.
6. Report source validation, signed packaging, upload, provider processing,
   tester availability, external review, and public release as separate facts.

Do not silently rewrite history. Add a dated entry that supersedes an older
fact. If a gate is not independently verified, mark it open.

## Authority and ownership

| Concern | Authority |
| --- | --- |
| Native iOS source, client behavior, local storage, builds, and client QA | This repository, branch `codex/team-delivery-foundation` |
| Detailed iOS evidence | `docs/CODEX_HANDOFF.md`, `docs/VALIDATION.md`, and focused documents under `docs/` |
| Personal financial data while the app runs | Local SwiftData store and protected app-private files |
| Cross-platform backup format and behavior reference | Android Pinbook backup-v8 contract, with iOS validation at the import boundary |
| Personal Google Drive replication | User-authorized Google Drive `appDataFolder`; local state remains usable without Drive |
| Team service routes, migrations, deployment, and recovery | TC Infrastructure and the admitted Team backend, not the iOS repository alone |
| Store and provider state | Apple, Google, and their consoles; re-verify before any current-state claim |
| Company-wide architecture and coordination | `technicalcenter-dev/TC-Company-Control` |
| Pinbook Android application state | Android repository and its owner; iOS may coordinate only within explicitly approved Pinbook scopes |

This is a personal companion project. Do not apply Technical Center branding or
copy personal data into company memory unless the owner explicitly requests it.

## Current baseline

### Remote repository baseline

| Item | Verified value |
| --- | --- |
| Repository | `https://github.com/zaidsafa/verbose-winner.git` |
| Branch | `codex/team-delivery-foundation` |
| Source before this memory | `0637a20d6bf23586e90c1cba40e062ed80f1c5ea` |
| Product | Native SwiftUI periodic-expense ledger and recovery companion |
| Platform | iPhone, iOS 26.1+, Swift 6 |
| Bundle | `com.zaidsafa.pinbook.ios` |
| Version/build | `0.1.0 (3)` |
| Current remote Team state | Source-complete bounded composition, default-off, no live Team origin committed |
| iCloud sync | Not implemented |

The last recorded provider history says TestFlight build 3 was available to the
configured testing groups and the owner reported it working well. That is dated
project evidence, not a fresh App Store Connect verification on 2026-09-27. No
later TestFlight build may be uploaded until the complete agreed update passes
the final acceptance gates.

### Paused local candidate

The working tree contains an uncommitted candidate based on `0637a20`. It is not
remote source and is not a TestFlight release. Its recorded 2026-09-13 evidence:

- 419 Swift tests in 39 suites passed in a serial run;
- 392 localization keys passed across English plus 15 translated locales;
- unsigned Release Simulator build passed for arm64 and x86_64;
- bundle, version, and build remained `com.zaidsafa.pinbook.ios`, `0.1.0`, and `3`;
- all nine Team production configuration values remained empty;
- plist, entitlement, project, diff, and generated AASA checks passed;
- no signing, provider, server, device, or TestFlight state changed.

The local candidate adds concrete Apple and Google onboarding composition,
strict signed Team remote transport, persistent outbox retry/status UI,
account-scoped cleanup, agreement-scope enumeration, recovery-key deletion,
persisted block state, policy links, and action-specific status copy. These facts
must not be described as remote or released until committed, pushed, and verified.

The untracked `tmp/` directory is user-owned scratch state. Do not stage it.

## Architecture

### Runtime composition

1. `PinbookApp` builds the SwiftData model container and launches the SwiftUI
   shell.
2. `AppShellView` owns onboarding, deep links, app lifecycle, the native tab
   structure, and optional personal Drive and Team runtime injection.
3. SwiftUI feature views read and write SwiftData models through explicit local
   service boundaries.
4. `PinbookCore` owns platform-neutral money, backup, merge, Drive, identity,
   cryptography, membership, delivery, recovery, and strict wire contracts.
5. `PinbookWidgets` exposes privacy-safe Quick Expense and Balance Overview
   entry points. Widgets do not display financial amounts or require an App Group.

### Local data flow

```text
SwiftUI route
  -> feature service or PinbookCore plan
  -> validated SwiftData and protected-file transaction
  -> local authoritative result
  -> optional explicit export, Drive replication, or Team action
```

The app is offline-first. Sync extends the local store; it does not replace it.

### Personal Drive flow

```text
explicit user consent
  -> AppAuth with fresh state, nonce, and S256 PKCE
  -> refresh credential in device-only Keychain
  -> access token in memory
  -> complete bounded appDataFolder inventory
  -> exact SHA-256 verification
  -> backup-v8 preview and pre-apply snapshot
  -> deterministic transactional merge
  -> immutable idempotent snapshot append
```

There is no Google client secret in the app. Disconnect fences refresh before
revocation and preserves ambiguous cleanup for explicit recovery.

### Team flow

The remote branch contains a strict default-off Team foundation. The paused
local candidate completes more runtime composition but keeps production values
empty. The intended sequence is:

```text
explicit Apple or Google sign-in
  -> account challenge and protected session
  -> explicit team creation or invitation review
  -> protected device enrollment
  -> agreement-key enrollment
  -> exact current membership and audience lookup
  -> canonical encrypted delivery reservation and relay
  -> decrypt and archive locally before ACK
  -> exact retry or status recovery for uncertain outcomes
```

No Team runtime is production-ready until Infrastructure admits the backend,
migration 028 workers, origin, AASA, Apple capability, provider configuration,
and recovery evidence.

## Route ownership

| Route or responsibility | Primary source owner | Supporting boundary |
| --- | --- | --- |
| App launch, onboarding, tabs, deep links, runtime installation | `Pinbook/PinbookApp.swift`, `Pinbook/AppShellView.swift`, `Pinbook/LaunchConfiguration.swift` | `Pinbook/OnboardingView.swift` |
| SwiftData models, books, preferences, active book | `Pinbook/PersistenceModels.swift` | `Pinbook/OptionsView.swift` |
| Expense list and detail presentation | `Pinbook/ExpenseViews.swift` | SwiftData models |
| Expense create and edit transaction | `Pinbook/ExpenseEditorView.swift` | `PinbookCore/Money.swift`, reminder and receipt services |
| Summary and Noted | `Pinbook/SummaryAndNotedViews.swift` | Active-book and currency invariants |
| Options, language, themes, currencies, Team entry | `Pinbook/OptionsView.swift` | `Pinbook/PinbookTheme.swift`, runtime configuration |
| Templates, favorites, Quick Add | `Pinbook/TemplatesAndQuickAddViews.swift` | Active-book SwiftData models |
| Receipt import and protected storage | `Pinbook/ReceiptViews.swift`, `Pinbook/ReceiptFileStore.swift` | Selected-photo-only access |
| Statements, CSV/PDF, reminders | `Pinbook/StatementAndReminderViews.swift`, `Pinbook/StatementAndReminderServices.swift` | One-person and one-currency output |
| Manual backup, restore preview, snapshots, recovery | `Pinbook/BackupRecoveryView.swift`, `Pinbook/BackupRecoveryService.swift` | `Sources/PinbookCore/Backup.swift`, `BackupRecovery.swift`, `Merge.swift` |
| Personal Google Drive UI and composition | `Pinbook/PersonalGoogleDriveRuntime.swift` | `Sources/PinbookCore/PersonalGoogleDrive*.swift`, `GoogleDriveBackupTransport.swift`, `PersonalCloud*.swift` |
| Team identity, sessions, onboarding, membership | `Sources/PinbookCore/TeamNativeSignIn.swift`, `TeamAccount*.swift`, `TeamAppleIdentityAuthorizer.swift`, `TeamGoogle*.swift`, `TeamOnboardingHTTP.swift`, `TeamInvitedSignIn.swift`, `TeamJoinStore.swift`, `TeamMembership*.swift` | `Pinbook/TeamInvitationAccountView.swift`, `TeamDeviceRegistrationView.swift`, `TeamInvitationWorkflowView.swift`, `TeamMembershipView.swift` |
| Team device and agreement custody | `Sources/PinbookCore/TeamDevice*.swift`, `TeamAgreement*.swift` | Device-only protected key material and exact enrollment binding |
| Team delivery, outbox, inbox, archive, ACK | `Sources/PinbookCore/TeamDelivery*.swift`, `TeamOutgoingStore.swift`, `TeamInbox.swift`, `TeamPortableArchive.swift`, `TeamWorkspace.swift` | Canonical JWE, archive-before-ACK, exact retry |
| Widgets and widget deep links | `PinbookWidgets/PinbookWidgets.swift` | Privacy-safe route-only snapshots |
| Store metadata and release checklist | `docs/TESTFLIGHT_SUBMISSION.md`, `docs/FINAL_UPDATE_CHECKLIST.md` | Apple provider read-back remains separate |

When responsibility moves, update this table in the same commit.

## Invariants that must not regress

### Product and UX

- Keep the interface simple, clean, and task-focused. Do not expose security or
  synchronization internals as a crowded settings panel.
- Preserve native SwiftUI navigation, system sheets, Dynamic Type, VoiceOver,
  RTL layout, Reduce Motion, and iOS Liquid Glass for interactive chrome.
- Dense financial content must remain readable on stable surfaces in light and
  dark appearance.
- Existing implemented theme colors stay unchanged. New default accent choices
  should prefer green instead of blue.
- New users receive the short versioned introduction. Returning users keep their
  data and must never be reset by onboarding changes.
- English plus 15 translated locales remain structurally complete. Arabic and
  Urdu use RTL. Simplified and Traditional Chinese remain separate.

### Money, books, and records

- Store money as signed 64-bit minor units. Never use floating-point money.
- Never aggregate different ISO currencies or apply an implicit exchange rate.
- Every expense belongs to exactly one book. Active-book screens and totals must
  not include another book.
- The active book cannot be archived. Archived books remain recoverable.
- Production startup creates no sample financial records.
- Quick Add creates a fresh unstarred open record and never mutates its source.
- Receipt metadata and bytes must commit or compensate together. Never leave live
  metadata pointing to a missing file.
- Reminder copy contains no purpose, person, amount, or currency.

### Backup and personal sync

- Backup-v8 input is fully decoded and validated before mutation.
- Import always shows deterministic add, update, unchanged, and conflict counts.
- Newer timestamps win; equal-time differences keep local data.
- Save an exact local pre-apply snapshot before restore or cloud merge.
- Google Drive access is limited to `drive.appdata`. No broader Drive scope is
  allowed.
- Refresh credentials stay in non-synchronizing device-only Keychain. Access
  tokens stay in memory. Credentials never enter SwiftData, backups, logs, Git,
  analytics, screenshots, or TestFlight notes.
- Remote snapshots are immutable. Ambiguous upload retries reuse the same exact
  operation identity and bytes.
- Do not enable simultaneous automatic Drive and iCloud replication until one
  cross-provider authority and conflict model is proven.
- iCloud remains optional future work. Apple publication does not require it.

### Team security and delivery

- Team production configuration is all-or-empty and default-off. Partial or
  malformed configuration fails closed.
- Apple and Google sign-in use the same bounded account/session path. Personal
  Drive authorization stays isolated from Team Google identity.
- Opening an invitation is read-only. Provider consent, device enrollment, and
  membership acceptance remain separate explicit actions.
- Session, account, device, enrollment, membership, audience, key, ciphertext,
  and deadline bindings must match exactly at every boundary.
- Do not automatically replay an uncertain write. Recovery is read-only first,
  followed by one explicit identical retry only where the frozen contract allows.
- Incoming Team data is authenticated, decrypted, and durably archived before
  ACK. Failed ACK never removes the archive.
- Account deletion is account-global, restart-safe, and server-authoritative.
  Local cleanup begins only after authoritative revocation and remains recoverable
  until server completion.
- No live service host, fallback domain, private key, token, or provider secret is
  committed.

### Release and evidence

- Keep TestFlight build `0.1.0 (3)` available until a complete replacement is
  accepted. Do not publish incremental Team builds.
- A green unit suite is not a signed archive. A successful upload is not provider
  processing. Processing is not tester availability. Testing is not public release.
- Use the isolated Pinbook QA identity for physical development tests. Do not
  overwrite the working TestFlight installation or its records.
- Cross-platform claims require exact iPhone and Android evidence with synthetic
  data. A backup file transfer is not live synchronization acceptance.
- Preserve contributor work. Never force-push or discard another task's changes.

## Decisions ledger

| Date | Decision | Reason and consequence |
| --- | --- | --- |
| 2026-09-01 | Build Pinbook iOS natively with SwiftUI for iOS 26 | Native Apple interaction and Liquid Glass take priority over copying Android presentation |
| 2026-09-01 | Keep local persistence authoritative | Expense entry and recovery must work without a provider or server |
| 2026-09-01 | Use Android backup-v8 as the compatibility boundary | Preserves portable records while allowing native iOS architecture |
| 2026-09-01 | Store money as integer minor units | Prevents precision loss and cross-currency confusion |
| 2026-09-01 | Keep production bootstrap empty | New users need a clean ledger, not sample financial data |
| 2026-09-02 | Replace the generic launcher icon with the brighter Pinbook identity | Owner rejected the original generic icon |
| 2026-09-04 | Publish complete 16-language catalogs as draft translations | Broad accessibility was required, but native-language review remains a separate quality gate |
| 2026-09-04 | Keep build 3 as the working TestFlight baseline | Owner accepted it; later updates must be complete rather than incremental |
| 2026-09-05 | Use Google Drive as the first automatic personal-sync provider | It supports Android and iOS through private `appDataFolder`; iCloud may be added later as an alternative |
| 2026-09-05 | Use immutable snapshots and exact idempotent retry | A lost response must not create duplicate or conflicting backup authority |
| 2026-09-05 | Keep personal Drive and Team Google authorization isolated | Revocation and scope changes must not affect the other feature |
| 2026-09-05 | Approve Apple and Google as Team identity directions | Both feed one strict account/session contract; provider choice does not activate Infrastructure |
| 2026-09-05 | Install physical development builds under a separate Pinbook QA identity | Protects the working TestFlight app and records |
| 2026-09-05 | Keep Team production default-off | Backend migration, origin, AASA, capabilities, provider setup, and cross-device acceptance were not complete |
| 2026-09-27 | Make this file mandatory project continuity | Architecture, decisions, recovery, current truth, and future releases must survive beyond chat history |

## Recovery points

| Purpose | Git point | Recovery note |
| --- | --- | --- |
| Repository bootstrap | `7b7fb06` | Initial native iOS repository and project identity |
| Currency-safe core | `4870394` | Money, backup-v8, merge, and service boundaries |
| Onboarding, currencies, and widgets | `ce3ad27` | Clean first-run flow, global currency picker, privacy-safe widgets |
| Bright app icon | `f78d112` | Restore if later icon work regresses the accepted colorful identity |
| TestFlight build 2 source checkpoint | `4c8087b` | Historical release evidence only |
| TestFlight build 3 upload checkpoint | `04645c3` | Current retained TestFlight build lineage |
| Build 3 group confirmation | `3565864` | Dated provider evidence; re-verify before a current claim |
| Portable encrypted Team archive | `ce246cf` | Protected archive and cross-platform recovery boundary |
| Apple native identity adapter | `bc4d2e0` | Inactive exact-state Apple sign-in boundary |
| Google native Team identity adapter | `0f3c0bb` | Inactive isolated browser and code-exchange boundary |
| Protected device custody | `6262b24` | Device identity and durable proof recovery |
| Invitation workflow | `baa1d58` | Explicit account, device, and membership sequence |
| Team encrypted delivery reservation | `341e4a4` | Canonical authenticated submit contract |
| Personal Drive activation | `429944b` | Explicit private appDataFolder runtime |
| Live personal Drive upload evidence | `c0c5df5` | Owner-observed upload path, not full remote read-back or cross-platform acceptance |
| Restart-safe Team delivery checkpoint | `32d2b9d` | Durable deletion barrier and release acceptance framing |
| Current remote production composition | `0637a20` | Default-off strict Team composition and current branch base |
| Paused local candidate | uncommitted, based on `0637a20` | Preserve working tree; validate, review, commit, and push only when implementation resumes |

## Dated history

### 2026-09-01 to 2026-09-02

- Bootstrapped native SwiftUI and SwiftData architecture.
- Added currency-safe money, Android-compatible backup-v8 decoding, books,
  expenses, Summary, Noted, templates, favorites, Quick Add, receipts,
  statements, reminders, local backup/recovery, onboarding, currencies, widgets,
  adaptive themes, and the brighter app icon.

### 2026-09-04

- Added persistent language control and complete 16-language draft catalogs.
- Uploaded TestFlight builds 2 and 3. Build 3 became the retained owner-accepted
  baseline.
- Added the inactive Team inbox, portable encrypted archives, recovery-key text,
  explicit recovery setup, native sign-in contracts, strict TLS auth/session
  custody, and provider-specific identity adapters.

### 2026-09-05

- Added protected Team device enrollment, invitation review, durable join
  recovery, membership consent, agreement keys, audience lookup, canonical JWE,
  submit intent, delivery journal, fetch, reservation, relay, archive-before-ACK,
  workspace composition, account deletion recovery, and final acceptance gates.
- Added personal Google Drive appDataFolder synchronization with explicit OAuth,
  protected credentials, immutable uploads, bounded verified merge, and manual
  recovery.
- Verified isolated iPhone QA paths and recorded limited Android coordination.
  Full live cross-platform Team acceptance remained open.

### 2026-09-13

- Built and validated the paused local onboarding and connected-runtime candidate:
  419 tests, 392 localized keys, and universal unsigned Release Simulator build.
- Kept all Team production values empty and made no TestFlight or provider change.

### 2026-09-27

- Established this root project memory as a required release artifact.
- No application source, build number, provider, device, infrastructure, or
  TestFlight state changed for this documentation milestone.

## Open gates and exact next actions

1. Resume the paused local candidate only on explicit owner instruction.
2. Review the complete dirty diff, preserve `tmp/`, rerun the full serial Swift
   suite, localization checks, lint, AASA generation, and unsigned Release build.
3. Commit and push the candidate separately from this memory milestone.
4. Have TC Infrastructure admit and deploy the exact Team service and migration
   028 workers with recovery evidence.
5. Supply the complete ignored Team build configuration, publish and verify AASA,
   enable the required Apple App ID capabilities and profiles, and finish Apple
   and Google provider setup.
6. Run signed isolated iPhone QA plus Android physical acceptance with synthetic
   records for sign-in, invitation, device registration, encrypted send, receive,
   archive-before-ACK, exact retry, block/report, deletion, and restart recovery.
7. Complete personal Drive remote read-back, disconnect/revocation, non-owner
   consent, and Android to iOS to Android recovery acceptance.
8. Close every item in `docs/FINAL_UPDATE_CHECKLIST.md` before calling the next
   build final.
9. Only after the complete candidate is accepted, request fresh authorization for
   archive, upload, TestFlight group changes, external review, or public release.

## Durable references

- `README.md`: product summary and build entry point.
- `docs/ARCHITECTURE.md`: local data and feature architecture.
- `docs/CODEX_HANDOFF.md`: detailed chronological handoff and limitations.
- `docs/VALIDATION.md`: exact validation evidence.
- `docs/FINAL_UPDATE_CHECKLIST.md`: final-candidate acceptance gates.
- `docs/PERSONAL_CLOUD_SYNC_V1.md`: personal Drive safety contract.
- `docs/TEAM_WORKSPACE_IOS.md`: Team workspace composition and recovery.
- `docs/TEAM_PRODUCTION_COMPOSITION_CHECKPOINT.md`: current default-off Team
  production boundary.
- `docs/TESTFLIGHT_SUBMISSION.md`: store metadata and submission process.
- `https://github.com/technicalcenter-dev/TC-Company-Control`: company protocol
  and cross-project coordination.
