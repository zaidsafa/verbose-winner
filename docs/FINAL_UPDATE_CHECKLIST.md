# Final Pinbook iOS update gate

Owner instruction September 4, 2026: build 0.1.0 (3) is good; no incremental
TestFlight uploads. Next update must cover the complete agreed scope and final
regression. This checklist distinguishes shipped capabilities from unfinished
ones; neither compiled source nor a placeholder counts as a completed feature.

## Preserve and revalidate in the final candidate

- [x] Native Liquid Glass navigation, elegant motion, Reduce Motion and Dynamic
      Type. Exact-current UI regression passed; prior visual accessibility matrix
      remains source-identical and includes accessibility XXXL, Increase Contrast
      and Reduce Transparency evidence.
- [x] Fresh first-run experience without deleting existing users' records; simple,
      skippable introduction with clear language selection.
- [x] All 16 language catalogs, including both Chinese scripts; live switching,
      RTL, translated errors and onboarding; no missing format arguments.
- [x] Five themes: readable text/controls in light and dark appearance, clear
      names, descriptions and symbols at selection.
- [x] Currency catalog with localized names, symbols and unambiguous ISO codes;
      search, favorites, selection and correct localized amount precision.
- [ ] Bright app icon in the installed app, widget gallery and App Store Connect.
      The colorful glass pinwheel is verified in the installed Simulator app and
      Pinbook widget gallery; the exact next App Store Connect candidate remains
      open until the one final build is uploaded and processed.
- [x] Expenses, settlements, balances, notes, templates, receipts, reminders,
      statements, personal backup-v8 preview/merge/recovery without data loss.
- [x] Both iPhone widgets: clear privacy behavior and verified Simulator
      installation/deep links. The gallery exposes Quick Expense and Balance
      Overview in small/medium families; their installed widgets open New Expense
      and Summary. Cross-routing now dismisses stale sheets authoritatively.
      Current Balance Overview is an entry point, not live shared-container data.
      Live balances require explicit App Group/capability and privacy integration.
      Physical Lock Screen/Always On behavior remains in the physical-only gate.

These items exist in the published baseline to varying documented extents; final
checkboxes deliberately remain open until checked against the exact next candidate.

## Unfinished functionality: not allowed to disappear from scope

- [ ] Personal cloud integration: Google Drive is implemented as the first optional
      provider with explicit consent, private `appDataFolder` scope, protected
      device-only refresh-token custody, manual and open-time automatic sync,
      bounded verified backup-v8 merge, pre-apply recovery and immutable idempotent
      snapshots. iCloud remains a possible later alternative; it must not become a
      simultaneous second automatic authority. Simulator and physical iPhone suites
      pass 47/47, complete UI passes 30/30, and the full signed app-host regression
      passes 404 + 4 expected physical-only skips. This checkbox stays open until
      independent Drive download/revocation acceptance, owned HTTPS privacy/support
      pages, production Google OAuth audience/branding, published Apple privacy
      metadata, and Android -> iOS -> Android synthetic-data interoperability pass.
      Android has the exact contract and must not repeat its earlier first-page,
      unbounded-read or mutable-write risks. See `PERSONAL_CLOUD_SYNC_V1.md`.
- [ ] Invite-only team sign-in, account/session admission, enrollment, roles,
      revocation and account lifecycle. Apple+Google direction accepted from the
      owner's direct "proceed" response to that proposed choice; Android notified.
      Actual credentials/client IDs, provider setup and validation remain gates.
      Do not send duplicate provider-choice prompts.
- [ ] Reviewed group-encryption library/provider, crash-safe crypto state, bounded
      untrusted input, key rotation, offline catch-up and authorized rejoin.
- [ ] Durable outgoing notes/drafts, revisions and reviews as distinct events;
      no implicit approval just because a delivery was read or saved.
- [ ] Team inbox and authenticated retries/ACKs, account/team/enrollment isolation,
      expiry/missing-item explanations and preservation of local archives.
- [ ] Supported media with complete verification before ACK; explicit caps and
      interrupted-download/upload recovery. Current local foundation is text only.
- [ ] Recovery-key custody/consent, secure Files export/import and cleanup, preview,
      lost-key/backup-health explanations, sender/revision/media coverage, and
      Android -> iOS -> Android full recovery without restoring remote authority.
- [ ] Isolated Infrastructure admission/staging, privacy metadata and accurate
      retention/deletion wording, provider purge/restore tests. No direct shared
      infrastructure access or deployment outside its owning task.

## Current local implementation checkpoint

- The committed Android/server delivery-fetch source contract now has a matching
  inactive iOS transport boundary. It signs the exact delivery ID/body through the
  current account/device/enrollment proof, uses dedicated challenge/fetch routes,
  accepts only an exact immutable 30-day encrypted response, verifies canonical
  base64url/size/SHA-256 and caps decoded/HTTP bytes. Focused **21/21**, complete
  exact-current Simulator **408 + 4 expected physical-only skips** and unchanged-
  identity unsigned production Release pass. This does not yet decrypt, archive,
  ACK, display or reconcile a team delivery and does not activate production
  infrastructure. See `TEAM_DELIVERY_FETCH_IOS.md`.

- Personal Google Drive sync is wired into the production runtime and localized
  Backup & Recovery UI. It remains disconnected until explicit user consent and is
  isolated from team sign-in. The protected non-synchronizing Keychain stores the
  refresh credential and pending immutable-upload authority; access tokens remain
  memory-only. The active merge path verifies every bounded snapshot, preserves
  local equal-time values, saves a recovery snapshot before changes and appends a
  new immutable backup only when content changed. Live Google and cross-device
  acceptance remain open; no new TestFlight build has been uploaded.
  See `PERSONAL_CLOUD_SYNC_V1.md`.

- ACCEPT, ACK and CANCEL journal metadata now has inactive iOS parity with the
  committed server contract. ACCEPT derives deterministic event/object identity,
  binds exact canonical submit-intent/JWE/audience/timestamps and freezes ordered
  target user/device/enrollment/agreement-key identity. ACK/CANCEL freeze that
  same four-field target. Independent Node and Swift canonical hashes match;
  complete core/Simulator app-host/physical iPhone QA/Release pass. No journal,
  provider or route is active.
  See `TEAM_DELIVERY_JOURNAL_EVENT_IOS.md`.

- Canonical submit-intent metadata now has exact inactive iOS parity. It pins the
  delivery ID, complete-audience digest, membership revision and exact JWE bytes/
  hash, with independent expected-binding and canonical decode checks. This is not
  an upload, sender authorization or server acceptance path. See
  `TEAM_DELIVERY_SUBMIT_INTENT_IOS.md`.

- The frozen canonical payload and multi-recipient JWE now have exact inactive
  iOS parity. The plaintext binds the team, delivery, author and body hash; the
  A256GCM protected header binds the complete frozen agreement-key audience, and
  each recipient has a distinct P-256 ECDH-ES+A256KW ephemeral. Both shared vectors,
  both recipients and a physical Secure Enclave decrypt pass. This does not prove
  sender authentication, server metadata, archive-before-ACK or live sync. See
  `TEAM_DELIVERY_JWE_IOS.md`.

- The frozen Android/server agreement-possession contract now has inactive exact
  iOS parity. The separate agreement key is registered-device signed and also
  proves its private-key possession through fresh-server-ephemeral P-256 ECDH,
  frozen Concat KDF and canonical HMAC. The public vector is byte-identical;
  clean core, signed Simulator, physical QA iPhone and ordinary unsigned Release
  pass. Every audience target still requires distinct valid signing/agreement
  credentials. This closes the prior source/physical possession gap, not live
  server staging or encrypted delivery. See `TEAM_AGREEMENT_ENROLLMENT_IOS.md`.

- Durable local outgoing drafts now use version compare-and-swap and atomically
  finalize into immutable, distinct note/correction/approval/changes-requested
  events. Reading/saving does not approve, exact enrollment owns its queue,
  finalized draft identities cannot be reused while their pending event exists,
  and no unauthenticated event-retirement path exists. This remains inactive and
  has no encrypted wire/submission/reconciliation UI. See `TEAM_OUTGOING_IOS.md`.

- `TEAM_AGREEMENT_CONFIRMATION_PROPOSAL.md` is superseded historical design. Its
  proposed bytes must not replace the accepted shared possession contract.

- Reviewed standard ECDH-ES Concat KDF/A256KW vectors and a separate non-exported
  Secure Enclave agreement identity now pass locally and in the isolated physical
  QA app. The key is exact enrollment scoped and cannot reuse the signing API.
  This is still inactive: the later checkpoint now supplies agreement-key
  registration/required audience/possession, while canonical envelope, delivery
  and two-device sync remain open. See
  `TEAM_DELIVERY_CRYPTO_IOS.md` and `TEAM_AGREEMENT_KEY_CUSTODY_IOS.md`.

- A one-flight current team-audience lookup now pins one reviewed account, exact
  registered device/enrollment and fresh membership revision through one typed
  challenge/sign/execute request. Account/device/proof authority is rechecked
  around every boundary and inside read-only custody signing. Local and physical
  QA pass through the complete 320-test app-host suite. This remains inactive and
  synthetic; it does not close live provider, encryption, delivery, two-device
  sync, final-candidate or TestFlight gates. See `TEAM_AUDIENCE_LOOKUP_IOS.md`.

- Shared device-authorized request v1 now has an inactive Swift exact-message/body-
  hash validator, byte-identical public fixture, and two strict authenticated typed
  transport methods. Cross-platform raw P-256 verification and intercepted routes
  pass locally and on the physical QA iPhone. It deliberately adds no live runtime
  route or generic transaction callback. Registered-custody/session audience
  ownership, fixed delivery coordinators, encrypted submit/fetch, archive-before-
  ACK and live two-device sync remain open. See TEAM_DEVICE_REQUEST_IOS.md.

- Native account transport now has bounded six-route parsing and one-use POST
  streams with synthetic and real localhost TLS failure tests. Separate protected
  session custody uses durable pending markers and generation-bound atomic pair
  replacement. Neither low-level foundation is a complete sign-in/session feature:
  Single-dispatch refresh orchestration is implemented/tested locally; remaining
  gates include concrete provider/controller adapters and UI, real client
  configuration/origin, revocation/enrollment and physical acceptance.
  Durable native sign-in orchestration (reservation→challenge→callback→exchange→
  generation-bound commit) is implemented/tested with synthetic identity and local
  TLS, not real provider issuance. No feature acceptance checkbox is closed by this.
  The concrete Apple controller adapter and Google runtime fake-driver tests now
  pass in the separate physical QA app. Google uses AppAuth3.0.0 browser ownership
  with app-owned bounded code exchange and no provider-token persistence; actual
  provider login and live setup remain gates. See DEVICE_QA_IOS.md.
  Internal P256 enrollment canonical bytes and public signature
  interoperability pass in both Node/Swift directions. Thirteen typed onboarding
  routes now compile and pass intercepted/localhost TLS tests, sharing the auth
  client's unresolved slot with strict 4 KiB/32 KiB parsing. Dedicated device
  custody now implements protected reservation/pending/recovery with same-key
  preservation and synthetic fault/race tests. A current access-only ticket and
  session/device-generation-bound registration owner now enforce wall/monotonic
  checks and fresh lookup/recovery without proof replay. Invitation account access
  now has read-only preview, exact committed/current account handoff and one-use
  wall/monotonic consent, tested synthetically and over private localhost TLS.
  It returns a memory-only intent, not membership authority. Durable scoped join
  metadata now supports exact pending/confirmation/recovery generations without
  storing the raw code. Separate current-account/device membership orchestration
  now performs fresh lookup, one-use consent, durable-before-accept and tokenless
  current-team recovery, tested synthetically and with local TLS/native drivers.
  A localized membership modal and retained UI model now compose that owner with
  unchecked consent and tokenless recovery; synthetic core tests and three native
  membership UI tests pass on the physical QA phone. No normal activation yet. See
  TEAM_MEMBERSHIP_UI_IOS.md. The invitation account preflight model/bridge/modal
  now exists with separate account consent, exact existing-account continuation,
  display-only one-use receipt, and permanent close/late-result cleanup. Its real
  bridge composes the invitation owner; the native DEBUG host is synthetic, not
  provider issuance. Physical287 app+24 UI passed; after core-only handoff refinements,
  rebuilt288 app+4 affected UI passed. All323 catalog entries match compiled app/
  widget resources. The retained parent presentation now connects exact account
  receipt → localized, separately consented device registration → one-use
  membership-screen transfer. The registration owner requires the reviewed account
  generation before any key write. Confirmed device registration is not membership;
  waiting/uncertain/retry-ready cannot advance or replay automatically, and each
  attempt needs fresh consent. Chinese/Arabic physical UI paths pass in the isolated
  QA app. Ordinary invitation entry/session-generation routing remains open. See
  TEAM_INVITATION_DEVICE_FLOW_IOS.md and TEAM_INVITATION_WORKFLOW_IOS.md. No final-
  feature gate is closed by this synthetic/privateTLS/QA presentation.
  the backend's source-only teams/acceptance route now has bounded iOS transport,
  durable same-identity explicit retry owner and localTLS tests; the native retry
  screen/bridge now composes that owner with new consent and original-link-only
  entry. Parent routing is not integrated. See TEAM_MEMBERSHIP_RETRY_IOS.md. Null must not become
  automatic retry or PENDING deletion. See TEAM_MEMBERSHIP_JOIN_IOS.md,
  TEAM_JOIN_RECOVERY_IOS.md and
  TEAM_INVITATION_CONSENT_IOS.md.
  Full account-to-membership navigation, complete hardware/protection/provider
  acceptance and live enrollment remain open. Separate physical QA verifies
  ephemeral Secure Enclave signing and file-protection attributes, not lifecycle
  recovery or real enrollment.
  See TEAM_DEVICE_REGISTRATION_IOS.md and VALIDATION.md: intermittent localhostTLS
  failures have occurred in sign-in, cancellation and invitation preview across
  separate runs. A concrete fixture port-file publication race is now eliminated
  with atomic readiness plus strict port parsing; three full245-test runs pass.
  This explains a possible default-port connection failure, but old runs did not
  record their port, so attribution of every historical failure remains unproven.
  Keep bounded diagnostics and watch for recurrence during final regression.
  See TEAM_DEVICE_CUSTODY_IOS.md; no normal navigation has been activated.
  See TEAM_ONBOARDING_HTTP_IOS.md; no acceptance checkbox is closed by this layer.

- Personal Files import now coordinates/read-checks off-main, is cancellable and
  bounds actual file bytes to 128 MiB. Export uses the same limit. Legacy backups
  larger than this limit need an accepted recovery path before final sign-off;
  schema remains v8. No automatic cloud sync is implied by provider coordination.
- Both privacy-only widgets have Lock Screen family layouts and adaptive
  tinted/background-removed colors. The actual Simulator gallery, installed
  Home Screen widgets and both deep links now pass. A discovered cross-widget
  presentation bug was fixed: opening Summary after New Expense closes the
  expense/Quick Add presentations instead of leaving a stale sheet over Summary.
  Always On and physical locked-device acceptance remain open.
- Received-text local store and restricted encrypted portable archive implemented;
  public cross-platform fixture round trip passed. No production entry point.
- Bounded file reader and immutable authenticated restore candidate implemented.
  Preview is read-only; confirmation revalidates conflicts atomically.
- Bounded local inbox paging and device-only recovery-key custody implemented
  behind inactive APIs. No normal app screen opens the team store or creates keys.
- Shared human-readable recovery-key parser and single-use preview session now
  implemented, plus an inactive received-text Files screen and public DEBUG UI
  test host. Background teardown rejects late operations and preserves an uncertain
  restore warning until a fresh authoritative preview. Key setup/copy now requires
  explicit consent, file read-back and separate-copy confirmation before custody.
  Final UI/provider/physical acceptance, imported-key retention, secure-screen
  policy and full archive coverage remain open; this is not complete team recovery.
- See `VALIDATION.md` for exact tested checkpoints. This is not a complete user
  recovery flow or a physical-device acceptance claim.
- Crypto audit/version/fix assessment: `OPENMLS_AUDIT_ADOPTION_20260904.md`.

## Final publication gates

- [ ] Resolve scope/provider/access decisions without silently dropping features.
- [ ] Complete implementation and integration, not disabled foundations.
- [x] Full automated app/UI suites, localization and structural accessibility
      checks. Exact-current evidence: Simulator app-host **353 PASS + 4 expected
      physical-only SKIPS** (357 total,0 failures), physical app-host **357/357**,
      native UI **29/29**,
      localization **336 keys x 15 locales plus English** with compiled app/widget
      parity. Spoken VoiceOver/rotor and physical focus remain under the separate
      physical-only gate below.
- [ ] Synthetic cross-platform full-workflow and staging failure/recovery acceptance.
- [ ] Resolve physical-only acceptance separately; owner may keep phone disconnected
      during development. Simulator passes do not close hardware gates.
- [ ] Review privacy/review notes, version/build, archive signature and upload artifact.
- [ ] Only then publish one final candidate to all existing TestFlight groups and
      verify processing, group availability and any required external review.

No new upload, version increment, release archive or signing mutation is authorized
merely by completing one checkbox. Never label this whole checklist complete based
on the owner's positive feedback about build 3.
