# Team workspace release-readiness audit

Audited: September 5, 2026

iOS source: `7e652856341a2fc7721bce1dd5c5abed4d412b4a`

Branch: `codex/team-delivery-foundation`

Server source inspected read-only: `6a09b19ad38bda2e4f1b0c5a4fa3b33fd89953d2`

## Decision

The iOS team workspace remains correctly **default-off** and is not ready to be
enabled or uploaded as the final TestFlight candidate. Do not add App/Universal
Links, provider endpoints, credentials, signing capabilities, or production
composition until every blocker below is closed against one frozen server commit.

The requested historical commit `341e4a4` is retained in this branch's history.
The remote branch currently resolves to the newer audited iOS commit above.

## Exact evidence at the audited commit

- Normal app composition uses `TeamWorkspaceRuntimeConfiguration.productionDefault`,
  whose value is `.disabled` (`Pinbook/OptionsView.swift:94`,
  `Sources/PinbookCore/TeamWorkspace.swift:596-607`). All visible workspace
  actions remain disabled (`Pinbook/OptionsView.swift:207-238`).
- The normal app URL handler accepts the personal Drive redirect and existing
  Pinbook custom deep links only; it does not consume team invitation links
  (`Pinbook/AppShellView.swift:281-289`).
- Invitation parsing is strict: exact injected HTTPS origin, exact
  `/join?invite=`, canonical 43-character unpadded base64url token, printable
  ASCII and a 1,024-byte bound (`Sources/PinbookCore/TeamOnboardingHTTP.swift:23-82`).
  QR and Share use the same canonical URL bytes
  (`Tests/PinbookCoreTests/TeamWorkspaceTests.swift:320-327`).
- There is intentionally no default `TeamWorkspaceRemoteTransport` conformer
  because moderation and deletion routes are not frozen
  (`Sources/PinbookCore/TeamWorkspace.swift:610-615`).
- Deletion records one stable operation before remote dispatch, preserves every
  local item after rejection or ambiguous failure, and resumes the five ordered
  cleanup steps after remote acceptance
  (`Sources/PinbookCore/TeamWorkspace.swift:401-577`). The focused tests cover
  same-operation retry and restart after a cleanup failure
  (`Tests/PinbookCoreTests/TeamWorkspaceTests.swift:257-302`).
- The privacy manifest declares linked User ID, Device ID, financial content,
  other user content, and photos/videos for app functionality, with no tracking
  (`Pinbook/PrivacyInfo.xcprivacy:16-82`). App Store Connect disclosures still
  require a release-time review against actual enabled behavior.
- The app and widget remain version `0.1.0` build `3`, signed by development team
  `F98S3VN5NL`, with bundle IDs `com.zaidsafa.pinbook.ios` and
  `com.zaidsafa.pinbook.ios.widgets`
  (`Pinbook.xcodeproj/project.pbxproj:933-960,1052-1073`). No Associated Domains
  entitlement or production team-link origin is configured.
- The server worktree inspected during this audit contains uncommitted migration,
  runtime, journal, projection, purge and test changes, including migration `026`.
  Therefore server commit `6a09b19` is not a frozen integration contract.

## Actionable blockers

### 1. Freeze the server contract

- [ ] Server owner commits and pushes the complete migration/runtime work.
- [ ] Record the exact server SHA and migration checksum set.
- [ ] Freeze request/response/error/idempotency behavior for invitation, account
      sign-in, audience, encrypted submit, pending/fetch/archive-before-ACK,
      delivery status, report, block, purge and account deletion.
- [ ] Provide a non-production staging origin and safe test identities through the
      approved secret channel; do not place credentials in source or this document.
- [ ] Reconcile the iOS client with that exact commit before enabling any UI.

### 2. Approve and prove invitation links

- [ ] Infrastructure approves one canonical HTTPS origin and owns its AASA file.
- [ ] AASA uses the exact application identifier
      `F98S3VN5NL.com.zaidsafa.pinbook.ios` and limits handling to `/join`.
- [ ] Only after approval, add the exact `applinks:<host>` Associated Domains
      entitlement and regenerate the affected signing profiles.
- [ ] Route the received URL through `TeamInvitationLink(validating:expectedOrigin:)`
      into the retained invitation workflow; never accept alternate hosts, paths,
      parameters, fragments, encodings or stale/account-mismatched invitations.
- [ ] On the exact signed candidate, open a link from Messages, Mail, QR and Share
      on a physical iPhone; verify valid acceptance and strict rejection cases.

### 3. Complete the production workspace composition

- [ ] Implement one authenticated `TeamWorkspaceRemoteTransport` against the frozen
      server contract; inject it only after session-generation validation.
- [ ] Implement native Apple and Google identity adapters through the same
      provider-neutral account path. Configure OAuth clients in provider consoles,
      never in source, and verify non-owner QA accounts where policy requires.
- [ ] Enable each UI action only when its full dependency set is ready. There must
      be no partial mode that can create invitations, keys, ciphertext or local
      acceptance without a recoverable server path.
- [ ] Decide whether attachments/media are part of this release. If promised, add
      and test them; otherwise remove the claim explicitly rather than silently
      dropping scope.

### 4. Complete account deletion

- [ ] Freeze an authenticated, idempotent server deletion result and retry contract.
- [ ] Implement `TeamAccountSecureCustodyDeleting` for all five steps: team
      cache/archive, agreement identity, device-signing identity, Terms acceptance
      and exact account session. Missing material must be treated as successful
      idempotent cleanup; unrelated accounts/teams must never be touched.
- [ ] Verify remote rejection and ambiguous network failure preserve all local
      material and reuse the same operation ID.
- [ ] After remote acceptance, force termination after every cleanup step and prove
      restart completes without repeating remote deletion or reporting success early.
- [ ] Verify Keychain persistence/reinstall behavior and update privacy policy,
      retention copy, App Privacy answers and Beta Review notes to match reality.

## Cross-platform staging acceptance

Use disposable accounts and encrypted test content only.

- [ ] iPhone sends; Android receives, durably archives, then acknowledges.
- [ ] Android sends; iPhone receives, durably archives, then acknowledges.
- [ ] Kill each app between archive and ACK; restart without loss or duplicate
      presentation.
- [ ] Disconnect during submit, fetch and ACK; retry preserves exact ciphertext and
      idempotency identity.
- [ ] Verify invitation expiry/revocation, membership removal, blocked users,
      recipient/device changes, stale sessions, pagination and server purge.
- [ ] Verify no plaintext note, invitation token, OAuth token, private key or
      recovery key appears in logs, defaults, URLs, crash reports or screenshots.

## Exact signed-device gate

Do not reserve a new upload merely by completing part of this list.

### Source and signing freeze

- [ ] Clean tracked iOS worktree at one reviewed SHA derived from the frozen server
      SHA; record both SHAs and dependency resolution.
- [ ] Keep marketing version `0.1.0`; change app and widget build numbers together
      from `3` to reserved final-candidate build `4` only after all integration gates
      pass.
- [ ] Keep bundle IDs `com.zaidsafa.pinbook.ios` and
      `com.zaidsafa.pinbook.ios.widgets`; do not create a duplicate app or Bundle ID.
- [ ] Confirm automatic distribution signing for team `F98S3VN5NL` on both targets.
- [ ] Audit final entitlements. Associated Domains is allowed only after the origin
      gate; no unexpected iCloud, App Group, push or Keychain groups may appear.

### Archive verification

- [ ] Run all Swift/app-host/UI/localization/accessibility suites and a clean Release
      build at the frozen SHA.
- [ ] Archive `Pinbook` for **Any iOS Device (arm64)** in Release configuration.
- [ ] Verify the archive contains app `0.1.0 (4)`, widget `0.1.0 (4)`, exact bundle
      IDs, distribution TeamIdentifier, expected entitlements, privacy manifest,
      16 localizations, app icon and widget extension.
- [ ] Review export-compliance answers against the exact binary and Apple's current
      guidance; do not infer the answer merely from the existing plist flag.
- [ ] Record archive path, creation time, source SHA, server SHA and SHA-256. An IPA
      file is not required for TestFlight; Xcode Organizer uploads the signed archive.

### Physical iPhone acceptance

- [ ] Install the exact archived or processed TestFlight build, not a different QA
      build. Test both clean install and upgrade from TestFlight build 3; existing
      financial data must remain intact.
- [ ] Validate onboarding, all 16 languages, Arabic/Urdu RTL, both Chinese scripts,
      five themes in Light/Dark, contrast, Dynamic Type, spoken VoiceOver and focus.
- [ ] Validate expense, payment, balance, currency, receipt, PDF/CSV, reminder,
      Files backup/restore and both widget workflows.
- [ ] Validate Google Drive on the release OAuth client with owner and non-owner test
      accounts if Drive remains in scope.
- [ ] Complete the invitation, relay, failure/recovery and deletion checks above with
      the physical Android device and the exact final Android QA build.

### TestFlight publication gate

- [ ] Publish support and privacy pages on owned HTTPS URLs; update Google branding,
      authorized domain and production audience before claiming external Drive sync.
- [ ] Correct the editable App Store version draft from `1.0` to `0.1.0`, unless an
      explicit decision changes both binaries to marketing version `1.0`.
- [ ] Update Beta description, What to Test, privacy answers and review notes to the
      exact enabled feature set. If team accounts are enabled, the current statement
      “No Pinbook account is required” must be replaced and a safe reviewer path
      provided without live credentials.
- [ ] Upload the single final archive through Xcode Organizer, wait for processing,
      answer export compliance, and attach only that build to the existing internal
      and external Zaid testing groups.
- [ ] Complete Beta App Review if requested, then verify the processed build shows
      **Testing** in both groups and installs successfully from TestFlight.
- [ ] Do not create a public link, duplicate app, duplicate Bundle ID, new tester or
      extra interim build unless separately authorized.

## Current next action

Wait for the server owner to provide the committed and pushed migration/runtime
contract SHA. Until then, the safe iOS state is the current default-off state and
there is no device, provider-console, signing or TestFlight action to perform.
