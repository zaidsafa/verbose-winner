# Pinbook iOS Codex handoff

Updated: 2026-09-05 (Asia/Shanghai)

## Owner release gate — no incremental TestFlight updates

- Owner declined WooOrders coordination: **No, keep the tasks separate**. Do not
  send WooOrders coordination/status messages or route them indirectly. Earlier
  Woo GUI requests are historical, not instructions to repeat rejected messages.
  Owner subsequently explicitly authorized Pinbook Android coordination for actual
  two-physical-device notes-sync testing and reported Android connected. A scoped
  QA/testing message to the verified Pinbook Android task now succeeded. This
  supersedes the older Android outbound-status permission hold for that testing
  scope, not for unrelated tasks/data. Use synthetic notes/separate QA installs;
  real notes delivery is NOT working yet and fixture/backup transfer is not live
  sync acceptance. Preserve Infrastructure activation and release gates. Do not
  infer permission to disrupt another task's UI/resources. Owner also now offers
  a physical iPhone. Initial listings were unavailable/offline; latest devicectl
  reports **available (paired)**. Owner explicitly approved a separate **Pinbook QA**
  development identity/profiles/install to preserve the working TestFlight app and
  records. This permits only that isolated development path, not a new TestFlight
  upload or replacement of the working installation. Separate QA install and
  physical tests now completed as recorded in DEVICE_QA_IOS.md; historical
  offline/compiled-only notes below are superseded by that evidence.
- Latest owner response was "proceed towards the goal" directly after being asked
  to approve Apple and Google sign-in. Treat that response as approval of the
  proposed Apple+Google pilot sign-in direction, rather than holding indefinitely
  for the same choice. This interpretation was explicitly communicated to the
  owner and Android task. It supersedes older "provider pending" notes below.
  Account connections remain opt-in. Real client IDs/console setup, validation
  contracts, credentials/access and all crypto/activation gates remain required;
  provider selection alone does not authorize shared Infrastructure mutations.
- Owner reports checking the published build 3 and finding it good. This is
  owner feedback, not a claim of complete physical-device regression coverage.
- Keep build `0.1.0 (3)` available. Do not upload or distribute further interim
  TestFlight builds. The next update must contain the complete agreed feature set
  and pass final integration/regression checks before publication.
- Continue local implementation and validation. Reconcile the agreed scope with
  a feature acceptance checklist before declaring the final candidate ready;
  inactive foundations do not count as completed user-facing features.
- Outstanding provider choices, access requirements and security activation gates
  still apply. Do not bypass them to call a build final or silently reduce scope.
- Track the complete final candidate in `FINAL_UPDATE_CHECKLIST.md`; unchecked
  gates are not complete merely because build 3 was accepted by the owner.

## Active local implementation after release hold

- Invitation account screen now has a real retained owner bridge, display-only
  review/receipt, explicit shown-account continuation or new unchecked sign-in
  consent, one-use private intent handoff and permanent close with pending-work
  draining. Native preflight is DEBUG-testable only; ordinary routing stays gated.
  Eleven messages translated across all15 locales+English (323 keys). Focused
  25/25, initial full260/260 PASS. Self-review added a failing time-after-Keychain
  regression (access/invitation expiry and rollback); post-read recheck fixed it,
  final full261/261 PASS22.442s. Kept bridge busy through public state commits;
  another complete261/261 PASS28.078s. Initial physical287 app+24 UI PASS (311,
  zero skips/failures), Chinese/Arabic screenshots visually checked. That full UI
  run preceded the core handoff refinement; final rebuilt physical288 app+4
  affected UI PASS (292, zero skips/failures). Signed QA and final unsigned Release
  builds PASS;323 compiled app/widget entries match source. QA normal launch after
  tests succeeded. See TEAM_INVITATION_CONSENT_IOS.md/VALIDATION.md. Do not infer
  real provider issuance or that all24 UI were rerun after the core-only fix.
  Next: parent account/device/membership flow and registration screen. Concrete
  prerequisite: TeamDeviceRegistration.register(consent:) currently captures the
  account at dispatch, not the account shown in the invitation UI. Add an exact
  expected-ticket path checked BEFORE custody.prepare/key writes, preserving all
  existing post-await/current-generation checks. Do not rely on a final UI account
  comparison to undo wrong-account key creation. Parent must retain the bridge,
  consume its receipt before source dismissal, then close/drain it; keep the raw
  intent private in workspace ownership. Teardown/recreate on session replacement.
  No normal team activation, production identity/version change or TestFlight push.
  Latest Android partner reports owner invitation issuance/share at a3af32e and
  remote list/revoke at4435fcf (PR31), contracts TEAM_ANDROID_INVITATION_UI.md and
  TEAM_ANDROID_INVITATION_REVOCATION.md in its delivery checkout. Read the actual
  contracts before implementing iOS owner screens. Reported revoke is separate
  from member removal; lost reply requires explicit fresh list, no auto replacement.
  Do not contact WooOrders or infer shared Infrastructure activation permission.

- Explicit original-link retry now connects native model/bridge to the real
  membership owner. Check previous join can finish without another accept, or
  present previous-attempt guidance and NEW unchecked consent before one exact
  retry. Bridge clears original code before attempt/on recovery/confirmation/close;
  uncertain attempt offers tokenless Check, not replay. Five new model +three
  real composition tests; focused42/42 PASS. Six new messages translated across
  all15 locales+English (312 total catalog keys), source and compiled QA/Release
  parity PASS. Initial physical six UI tests PASS; stale306 catalog assertion
  corrected to312 and all six new keys checked. Final full physical QA **272 app
  +20 UI PASS**,292 total, no skips/failures. Shared disabled native button uses semantic text
  over its neutral surface. Both QA test build and ordinary unsigned Release PASS.
  See TEAM_MEMBERSHIP_RETRY_IOS.md and VALIDATION.md. Parent invitation/account
  screens and workspace/session lifecycle routing are NEXT, not live activation.
  Integration detail: TeamInvitedSignIn.clear cancels/invalidate its pending flow
  but does not itself await every preview task. Its screen wrapper must retain and
  drain real pending work, reject late results, and close permanently on session
  replacement. Keep raw join intents/tokens inside service/workspace ownership,
  not displayed or persisted UI state. Device enrollment still needs its separate
  explicit consent; completing account access must not silently register or join.
  Initial full244-core run failed with existing localhostTLS -1004 errors; found
  and fixed a concrete fixture startup race (existence before port contents), with
  atomic port-file publication +strict port parsing/regression. Full245/245 PASS
  three times20.221s/17.294s/19.769s. Old failures lack port evidence, so do not
  claim this proves every historical cause. No production transport/trust/timeout
  changes or source push/TestFlight/shared runtime changes.
  Android supplied an exact public Samsung Keystore signature fixture; copied
  SHA256 matches producer, Swift focused7/7 and subsequent full246/246 PASS.
  Exact Android public vector now verifies on physical iPhone0.001s; all273 app
  tests PASS8.533s, zero skips/failures. Full20 UI preceded that test-only rebuild.
  QA launched normally afterward. No new runtime feature/code in that addition.
  See TEAM_DEVICE_ENROLLMENT_WIRE_IOS.md for byte-level interoperability scope.

- Separate signed Pinbook QA app/widget now installed on iPhone16Pro/iOS26.6.1:
  distinct `.qa` app identity, `pinbook-qa` links, default Keychain/container
  isolation, no App Group/sharing entitlement. Production defaults remain
  unchanged; ordinary unsigned Release PASS. Physical app-host **263/263 PASS**,
  membership UI **3/3 PASS**, including real file-protection attribute check and
  Chinese/consent/background behavior. See DEVICE_QA_IOS.md for exact evidence and
  installation inventory caveat. Remaining13 baseline UI tests PASS (all16 UI).
  Visual review found/fixed faint white-on-bright-accent text with a shared native
  prominent style; all263 app +17 UI tests PASS on that candidate, all10 palette
  screenshots inspected. Removed misleading colon-currency fallback icon; latest
  candidate264 app +2 affected UI tests PASS, including actual ephemeral Secure
  Enclave generate/reopen/sign/verify (no Keychain or provider write). Ordinary
  Release and compiled catalog parity PASS; QA launched normally after tests.
  Full17 UI run is the preceding contrast candidate, not the later currency edit.
  These tests do not enable real providers/shared notes or lift TestFlight hold.
  Next: explicit retry bridge/UI and parent account/workspace routing; real sync
  needs the approved isolated service, provider config, enrolled-device auth,
  reviewed MLS/key distribution and concrete send/fetch/save-before-ACK UI.
  Android reports separate QA installation on Samsung with unchanged working APK;
  its own root contrast fix is in progress. Do not call either QA install sync.

- Original-invitation explicit retry now composes durable store and retained
  membership owner: read-only original hash matching, exact enrollment/current
  account/device, fresh registration, new durable generation before ONE acceptance
  status lookup, then either exact confirmation or NEW one-use consent. Explicit
  Join commits a new PENDING generation before one identical accept. Null/errors
  never erase metadata or automatically resend. Consent has five-minute wall/
  monotonic and current-access limits; server invitation eligibility is rechecked
  on accept. Five new store+nine owner cases; full **236/236 PASS**,16.539s:
  `/private/tmp/pinbook-ios-explicit-retry-full-core.log`. Actual privateTLS composed
  scenario verifies pending lookup→new consent→same original accept fields and
  durable marker counts. See TEAM_MEMBERSHIP_RETRY_IOS.md. Retry UI/bridge entry and
  parent workspace routing remain NEXT; existing membership screen is unchanged.
  Simulator build-for-testing PASS:
  `/private/tmp/pinbook-ios-explicit-retry-test-build.log`; unsigned iPhone Release
  PASS: `/private/tmp/pinbook-ios-explicit-retry-release.log`. No new runtime run.
  All final feature/physical/provider/activation gates and no-push/TestFlight hold
  remain. Keep tasks separate as owner requested. Phone is now available; owner
  approved separate QA installation as noted above. Never overwrite TestFlight.

- Fourteenth onboarding route `teams/acceptance` now has bounded, exact typed iOS
  lookup with original token/team/enrollment/role and current access-only ticket.
  Successful explicit null means eligible pending NOW only; all errors remain
  uncertainty. No PENDING deletion, raw-token persistence, polling or automatic
  accept. Six new intercepted cases+actual privateTLS four-scenario test pass;
  focused onboarding14/14, full **222/222 PASS**,18.796s:
  `/private/tmp/pinbook-ios-acceptance-route-core.log`. See
  TEAM_ONBOARDING_HTTP_IOS.md. Next: durable same-identity explicit retry and its
  owner/UI consent integration; this transport alone does not enable retries.
  Simulator build-for-testing and unsigned iPhone Release PASS:
  `/private/tmp/pinbook-ios-acceptance-route-test-build.log` and
  `/private/tmp/pinbook-ios-acceptance-route-release.log`. Compilation only;
  no new app-host/UI/device execution. Both connection tools still show phone offline.
  Membership screen at8abcc5d remains inactive; all final feature/activation gates
  and source-push/TestFlight hold remain unchanged. No cross-task messages.

- Localized native membership screen now uses a retained model→bridge→real owner,
  explicit read-only review, initially unchecked separate consent, single join and
  tokenless Check recovery. Existing durable records route to Check rather than a
  review loop. Close/background clears UI synchronously and rejects late results;
  parent cleanup waits for real pending work. Nine synthetic screen cases plus
  real bridge/owner/store composition; full **215/215 PASS**,14.981s:
  `/private/tmp/pinbook-ios-membership-screen-final-core.log`. All306 catalog keys
  in15 translations+English pass source and compiled Debug app/widget parity.
  Simulator build-for-testing PASS after correcting a new-view/asset file-ID
  collision: `/private/tmp/pinbook-ios-membership-screen-fixed-test-build.log`.
  Three new UI tests are compiled, NOT run. See TEAM_MEMBERSHIP_UI_IOS.md.
  Normal navigation remains unchanged; DEBUG host is double-gated to ephemeral
  synthetic fixtures. Invitation/account UI, workspace lifecycle, explicit pending
  acceptance retry, owner management and all final scope gates remain open.
  Unsigned iPhone Release PASS:
  `/private/tmp/pinbook-ios-membership-screen-release.log`.
  A non-secret GUI coordination request to WooOrders iOS was rejected by security
  review; the owner subsequently answered **No, keep the tasks separate**. Do NOT
  retry, message indirectly or request the same permission again. Keep this work
  Pinbook-local and do not use another task's status as permission for shared GUI
  control. No new app-host/UI run has started. Do not send Android updates while
  its prior outbound approval is unresolved; no cross-task status is necessary
  for this local checkpoint. Continue unaffected isolated implementation/checks.
  Owner now offers a connected physical iPhone. Read-only devicectl lookup reports
  the known iPhone16Pro **unavailable**; requested unlock/reconnect/Trust only.
  Do not overwrite its working TestFlight installation or financial records.
  A separate development identity/install and safe custody namespaces must be
  established before any physical test. No new signing/capability or install yet.

- Retained membership owner now binds ONE exact access-only account generation,
  current REGISTERED device and fresh server lookup, read-only preview, separate
  single-use five-minute consent, durable PENDING before one accept, and tokenless
  current-team recovery under a new durable generation. Account checks follow
  slow device/metadata reads; deadlines include owner-wide monotonic access
  lifetime anchored BEFORE the first slow account read. Close waits for real
  unresolved work. Fifteen new owner tests plus composed actual localhost TLS/
  storage-driver path; final full **205/205 PASS**,15.797s:
  `/private/tmp/pinbook-ios-membership-verified-core.log`. See
  TEAM_MEMBERSHIP_JOIN_IOS.md. Next: localized invitation/join screens and optional
  host lifecycle/account routing, then explicit pending-acceptance retry/owner
  management. Android's new source-only teams/acceptance contract inspected locally:
  null is eligible pending, NOT proof no queued accept can commit. iOS route/retry
  is still unimplemented; no automatic replay/clearing allowed. Outbound cross-task
  updates remain paused pending the earlier approval; no new duplicate question.
  Every final scope/activation/TestFlight hold below remains unchanged.
  Final Simulator build-for-testing PASS:
  `/private/tmp/pinbook-ios-membership-verified-test-build.log`; unsigned iPhone
  Release PASS: `/private/tmp/pinbook-ios-membership-verified-release.log`.
  No new app-host/UI runtime; the previous cross-task GUI coordination limitation
  remains separate from useful local implementation. Do not infer GUI ownership
  or release from task activity alone.

- Durable join recovery metadata now records scoped PENDING before accept, with
  no raw invitation or account credentials, exact generation/response binding,
  fresh recovery generations and read-only scoped listing. Dedicated passcode-only
  Keychain CAS index,8scopes/10teams each/80records/64KiB, reserves future metadata
  growth so admitted recovery can proceed at capacity. No automatic retry/deletion.
  Twelve synthetic storage/policy/fault/race tests pass. Two full regressions hit
  intermittent localhostTLS failures (cancellation and invitation preview); exact
  causes unproven. Added bounded DEBUG numeric transport/trust diagnostics without
  relaxing verification, deadlines or replay policy. Subsequent full189 PASS;
  final exact source **189/189 PASS**,16.171s:
  `/private/tmp/pinbook-ios-join-store-final-verified-core.log`.
  Final Simulator build-for-testing PASS:
  `/private/tmp/pinbook-ios-join-store-verified-test-build.log`; unsigned iPhone
  Release PASS: `/private/tmp/pinbook-ios-join-store-verified-release.log`.
  preserve both failures as open final-validation caveats. See VALIDATION.md and
  TEAM_JOIN_RECOVERY_IOS.md. Next: actual retained membership owner with current
  account/device, fresh lookup, separate single-use consent, one accept and
  read-only current-team reconciliation; then localized screens/host lifecycle.
  No normal navigation, real provider/hardware, shared resource, source push or
  TestFlight activation. Full final feature checklist remains open.

- Invitation account consent now has read-only preview, exact current-account
  display, opaque single-use five-minute wall/monotonic confirmation, bound native
  challenge/exchange, cancellation ownership and a memory-only join intent. The
  native owner returns only its exact committed generation, rejecting a competing
  replacement even with identical tokens. No implicit device registration or team
  accept. See TEAM_INVITATION_CONSENT_IOS.md. Full core **177/177 PASS**,16.755s:
  `/private/tmp/pinbook-ios-invitation-full-core.log`; Simulator build-for-testing
  PASS: `/private/tmp/pinbook-ios-invitation-test-build.log`. No new app-host/UI run.
  Unsigned iPhone Release PASS: `/private/tmp/pinbook-ios-invitation-release.log`.
  Next: bounded durable join intent, separate membership consent/current-team
  recovery, then localized screens/host lifecycle. Read Android's membership/join
  UI contracts locally; do not resume blocked outbound coordination without owner
  approval. Keep every remaining feature and external activation gate below.

- Coordination-only approval pending: sending the cee0f3c status to the separate
  Pinbook Android (studious-potato) task was rejected by security review. Read_thread
  verified it is Zaid's local Pinbook/studious-potato task, but a narrowed retry was
  also rejected for destination/disclosure authorization. Do NOT retry or route the
  message indirectly. An asynchronous owner question requests permission to share
  non-secret implementation/test updates there. Until an explicit answer/approved
  tool action, pause outbound cross-task status; local iOS implementation and local
  read-only contract inspection can continue. No credentials/financial data sent.

- Account-bound registration owner now composes current access-only session
  tickets, protected device custody and the SAME retained onboarding client.
  Fresh lookup even for REGISTERED, current-generation checks after slow device
  reads, wall/monotonic operation/proof limits and cancellation ownership; no
  automatic key rotation, sign-in, refresh or proof replay. See
  TEAM_DEVICE_REGISTRATION_IOS.md. Thirteen new core cases and actual localhostTLS
  captured-signature/repeat-lookup integration added. One older TLS sign-in case
  failed once in initial full regression; isolated and subsequent full runs pass,
  but root cause is unproven. Added bounded test diagnostics and three mandatory
  fresh TLS cases, not retry-on-failure. Preserve caveat for final validation.
  Subsequent invitation account consent/exact account handoff is recorded above;
  next is durable membership
  intent and separate join consent/current-membership recovery. Android invitation
  consent and join-recovery documents have been read; use persisted team/enrollment
  IDs for unknown accept, not re-preview of a consumed link. All release gates stay.
  Final core **163/163 PASS**,13.498s:
  `/private/tmp/pinbook-ios-registration-owner-final-core.log`; final Simulator
  build-for-testing PASS:
  `/private/tmp/pinbook-ios-registration-owner-final-test-build.log`. No new app-host
  runtime; Woo task snapshot was active but unchanged with no concrete GUI handle
  or explicit release. That is not a verified live wait; safe local work continues.
  Unsigned iPhone Release PASS:
  `/private/tmp/pinbook-ios-registration-owner-release.log`.

- Device custody now uses an inactive SecureEnclave-only provider and a separate
  bounded passcode-only Keychain index. RESERVED→READY→SUBMIT_PENDING (before signing)
  →REGISTERED; fresh RECOVERING generation and exact-key absence retain the SAME key.
  Fifteen synthetic fault/race/Keychain-policy tests plus composed actual localhost
  TLS signature verification added. Full core **149/149 PASS**; Simulator test build
  PASS. See TEAM_DEVICE_CUSTODY_IOS.md. No real Secure Enclave/Keychain runtime or
  physical acceptance is implied. The subsequent registration owner above now
  provides current-session and monotonic integration; consent/join UI remains open.
  The owning app must perform a fresh lookup even for local REGISTERED metadata;
  it is not lasting authority. Keep all final scope/activation/publication gates.
  Unsigned iPhone Release also PASS:
  `/private/tmp/pinbook-ios-device-custody-release.log`. Requested a fresh explicit
  app-host-only GUI release from WooOrders iOS after compilation; no live GUI
  operation is presumed from its task activity and no test was launched yet.

- Thirteen typed onboarding routes now share the retained auth HTTP client's
  unresolved slot; public/protected auth, exact scopes/roles/device keys, null vs
  uncertainty, 4 KiB/32 KiB limits and strict duplicate-safe JSON are enforced.
  Full core **133/133 PASS**, including two actual localhost TLS onboarding tests;
  Simulator build-for-testing PASS. See TEAM_ONBOARDING_HTTP_IOS.md and VALIDATION.md.
  Unsigned iPhone Release also PASS at
  `/private/tmp/pinbook-ios-onboarding-final-release.log`.
  No new app-host/UI run, private device-key custody or normal navigation activation.
  Next: dedicated bounded key custody/pending recovery, current-session generation
  plus monotonic registration owner, then invited sign-in/two-stage consent/join.
  Android b0e97af has corresponding inactive custody/registration source; its
  TEAM_ANDROID_DEVICE_CUSTODY.md and TEAM_ANDROID_DEVICE_REGISTRATION.md were read.
  That is contract guidance, not iOS Keychain or physical-provider evidence.
  No shared infrastructure mutation, source push or TestFlight upload.

- Google native adapter implemented using exact AppAuth3.0.0 for the system browser,
  fresh state/S256/raw nonce and app-owned bounded token HTTP. No GIDSignIn singleton,
  stored provider tokens, AppAuth shared URLSession override or Drive scope. Six
  intercepted token tests + four real SDK/silent-user-agent tests pass; full core
  **119/119 PASS**, final Simulator test compilation PASS. Five UIKit fake-driver
  tests are compiled, not yet executed. Existing Apple/device UIKit runtime tests
  also remain pending fresh Woo GUI clearance; no current GUI operation was assumed
  from task activity alone. Real clients/redirects/origin/claim acceptance and normal
  navigation remain absent. See TEAM_GOOGLE_IDENTITY_ADAPTER_IOS.md.
  Final unsigned Release also PASS: `/private/tmp/pinbook-ios-google-final-release.log`.
  No runtime UIKit pass is inferred from it. The subsequent onboarding transport
  checkpoint above supersedes this step; invitation account consent remains
  separate from explicit device registration/team join.
- Future local core runs should use `--scratch-path /private/tmp/pinbook-google-core.K7cTEo`
  with `-j 2` for now. The old repository `.build/build.db` failed with disk I/O errors
  and zero matching SDK tests; no success counted.91GiB disk free, no active build
  process at diagnostic check; underlying cache cause unproven. Old cache/logs retained.
- AppAuth ownership choice is now made; older undecided GIDSignIn/AppAuth notes
  below are historical. Pinned public source/configuration and inactive adapter
  do not establish Google-issued claims or account/provider setup. Do not repeat
  the provider-choice question or silently invent clients/redirect registration.

- Device enrollment canonical-byte/public-key interop implemented internally,
  without key custody, enrollment routes or navigation activation. Full core109/109
  passes after numeric/hex hostname parser hardening. Node-generated signature
  verifies in CryptoKit; CryptoKit-generated signature verifies using the actual
  backend serializer, with exact RFC7638/raw64 bytes and all field-tamper negatives.
  Two public-only fixtures and a read-only repeatable verification script are retained;
  private fixture keys discarded. See TEAM_DEVICE_ENROLLMENT_WIRE_IOS.md.
  Exact final unsigned iPhone Release and Simulator build-for-testing both pass;
  logs: `/private/tmp/pinbook-ios-device-wire-final-release.log` and
  `/private/tmp/pinbook-ios-device-wire-final-test-build.log`. Next runtime run must
  include both six-test Apple adapter and six-test wire suites; neither has new
  iPhone execution evidence yet. Await fresh Woo GUI release, then use the existing
  dedicated Pinbook Simulator and app-host-only test-without-building batch.
- Read Android0082c7cb invited-admission contract: claim/login is separate from
  key registration and explicit team join; first owner still needs controlled
  bootstrap. Admission persists independently of invite expiry/revoke. Native UI
  must distinguish those consents. Later TEAM_ONBOARDING_HTTP_V1.md assigns the
  literal public preview/claim routes, now implemented locally as noted above.
- Google10.0.0 isolation/dependency/cancellation findings are recorded in
  TEAM_GOOGLE_IDENTITY_ISOLATION_IOS.md. The later AppAuth decision above supersedes
  the original undecided dependency state; live configuration remains absent.

- Apple adapter now implemented; see TEAM_APPLE_IDENTITY_ADAPTER_IOS.md. Six
  fake-driver tests compile in the exact Debug test build; final unsigned iPhone
  Release passes. Runtime execution still awaits fresh shared-GUI clearance from
  WooOrders iOS; do not count these six tests as passed. No real Apple account UI,
  client/capability setup or navigation wiring exists yet. Prior app-host124+one
  skip remains checkpoint1ee16cf evidence. Google10.0.0 source review confirms
  fresh custom-nonce API but shared SDK Keychain state and no public flow-cancel
  method; resolve those integration boundaries before dependency adoption.

- Refresh integration checkpoint `ea03850` committed locally. New sign-in
  coordinator adds consented durable login reservations, native callback ownership,
  wall+monotonic deadlines around awaits/custody reads, single exchange and a
  generation-bound session commit. Existing sessions cannot be overwritten; stale
  callbacks cannot install after cancellation/new reservation. Public unbound
  initial-save removed (internal fixture seeding only). Concrete provider adapters
  and configuration/UI still pending; see TEAM_SIGN_IN_COORDINATOR_IOS.md.
- Latest validation: core103/103, iPhone app-host124 passes plus one hardware skip,
  unsigned Release/Simulator build pass. A macOS core rerun hung in test-fixture
  Process.waitUntilExit after its TLS child had already exited. Live stack sample
  located it in Fixture.deinit; that exact test helper was terminated, evidence kept.
  Bounded termination-handler synchronization replaces waitUntilExit. Full rerun
  then passed103/103. Not an app/network failure or a silently counted green run.
- Final review also replaced a two-read sign-out fallback with one union-record
  read plus exact-generation deletion, preventing false success during concurrent
  login commit. Final core103/103, app-host124+one hardware skip and unsignedRelease
  pass after that fix. Next concrete native step: retained Apple authorization
  controller/anchor adapter and cancellation quarantine (SDK confirms cancel() on
  iOS16+ reports through its delegate), plus Google identity/Drive isolation review.
  Android enrollment contract now available at its `a629647e` checkpoint in
  docs/TEAM_DEVICE_ENROLLMENT.md; exact P256/canonical-byte interoperability and
  dedicated key custody still need client review before adopting that flow.

- Session custody checkpoint `e0ff1c3` is committed locally. New follow-up actor
  connects custody to one-dispatch refresh: durable marker first, busy until actual
  transport settlement, cancellation/late-result rejection, generation-bound commit,
  explicit local sign-out and no auto-retry. HTTP completion now waits for the final
  URLSession invalidation callback. Six coordinator tests plus actual localhost TLS
  integration passed; full core95/95, app-host117 passes plus one hardware skip,
  and unsigned Release/Simulator compilation pass.
  Provider/challenge/exchange/controller ownership and configuration remain next;
  no normal-navigation activation. See TEAM_SESSION_CUSTODY_IOS.md and VALIDATION.md.
- Before selecting the Google iOS dependency, resolve SDK sharedInstance/saved-
  credential isolation from future personal Drive authorization. Tagged9.2.0 has
  raw nonce support but replaces SDK saved sign-in state. Maintained AppAuth system
  session with explicit selection and volatile provider results is an alternative
  under review. This is not permission to weaken OAuth/nonce checks, invent native
  client configuration or globally sign out a personal Drive connection.

- HTTP/TLS checkpoint is now committed locally at `c9b5912` (no push/upload).
  Subsequent session-only Keychain custody is implemented with passcode-required
  non-backup protection, explicit add-only consent, scope validation and generation
  CAS. Before refresh it persists a marker WITHOUT old tokens; only a successful
  marker write returns a volatile dispatch lease. A late callback cannot replace
  a newer login. Ambiguous replacement is pending OR a complete new pair, never a
  mixed pair or automatic old-token replay. Full core88/88 passes; app-host111
  passes plus one hardware skip, including actual isolated Simulator SecItem
  generation matching. Unsigned Release passes. See TEAM_SESSION_CUSTODY_IOS.md.
  Low-level custody alone is not a complete user-facing sign-in/session feature.

- New inactive native account transport implements all six agreed routes, bounded
  response validation, scoped authorization, default TLS trust and one-use POST
  streams. Both replacement-stream callbacks refuse replay. Actual private localhost
  TLS tests show one request/body for503 Retry-After:0,408 and lost-response cases;
  trust rejection, redirects, fixed/chunked overflow, cancellation/timeouts pass.
  Core81/81 plus unsigned iPhone Release and Simulator test compilation PASSED.
  See TEAM_AUTH_HTTP_IOS.md and VALIDATION.md for exact evidence and failed fixture
  diagnosis. Nothing is connected to a real origin/provider or normal navigation.
- Next is separate session custody and orchestration: durable marker before refresh,
  generation-bound atomic replacement, never replay after ambiguity. Use a new
  passcode-only/non-backup Keychain class for account sessions; do NOT migrate
  archive recovery keys to that class. Removing a passcode can invalidate sessions
  (sign-in again), but must not delete archives/recovery keys. Apple confirms
  WhenUnlockedThisDeviceOnly alone can restore to the same device; it is not a
  non-backup guarantee. Physical passcode/Keychain acceptance remains open.

- Current source checkpoint `3b02975` adds background invalidation and token-scoped
  cancellation for received-note recovery, plus explicit recovery-key setup/copy.
  New key custody requires consent, an exported file read-back, the last eight
  characters and separate-copy confirmation. Existing keys are never overwritten;
  unavailable custody is not treated as a missing key. This remains inactive in
  normal navigation; the DEBUG host uses an in-memory fake, not a real account.
- Recovery-only core suite: 62/62 passed. Two full Simulator attempts remain
  failed evidence: 100/1failed/1skip, then99/2failed/1skip. Nested-switch targeting
  alone did not fix the second run; recording showed a dimmed blocked screen after
  a prior native Files sheet was left open at host termination. Unchanged key
  setup passes1/1 in isolation after fresh boot, including background clearing.
  Native Files UI test now dismisses and verifies the sheet before termination.
  Final combined rerun PASSED:108 app/UI passes (95 app +13 UI), one hardware skip,
  zero failures. See VALIDATION.md for exact artifact paths and prior failures.
- New inactive native Apple/Google request binding and Apple request construction
  are implemented in TeamNativeSignIn.swift; seven synthetic tests bring core to
  69/69 passed. No Google SDK/controller, real provider/client ID, live HTTP route or
  session custody is enabled. Android session semantics require a durable refresh
  marker before dispatch and atomic replacement, with reauthentication on ambiguity.
  See TEAM_NATIVE_SIGN_IN_IOS.md and TEAM_AUTH_MLS_FEASIBILITY_20260904.md.
- Unsigned iPhone Release and compiled286-key app/widget catalog parity passed.
  This is a verified local checkpoint, not the final releasable feature set.
- Keychain protection remains non-synchronizing WhenUnlockedThisDeviceOnly.
  Passcode/secure-screen policy and physical acceptance remain open; changing to
  WhenPasscodeSetThisDeviceOnly would delete items when the passcode is removed.
  Native Files/cloud durability and imported-key retention are not established by
  local temporary-file read-back tests. Full sender/revision/media recovery is open.
- The personal import/widget checkpoint is committed locally at
  `f6e6e26c1e3280f1202b7d2b5b74ab9d4907bf7c`: 50 core passes, 85 app/UI passes
  plus one hardware skip, unsigned iPhone Release build passed; no upload/push.
- Subsequent inactive work adds strict agreed recovery-key text, single-use
  actor-backed restore confirmation, a scoped received-note Files recovery screen
  and all 16-language copy. Normal production navigation still does not instantiate
  it. DEBUG-only public fixture UI requires explicit ephemeral + preview flags.
  See TEAM_DELIVERY_IOS.md, TEAM_RECOVERY_KEY_TEXT_V1.md and VALIDATION.md for
  implementation, platform cancellation differences and final test state.
- This continuation is saved locally at `a5d1cb3`: final 55/55 core tests,
  92 app/UI passes (80 app + 12 UI), one hardware-protection skip and zero failures.
  Unsigned iPhone Release compile and exact compiled 272-key localization checks
  passed. Chinese preview screenshot was visually inspected. No source push/upload.
- Next safe implementation: bounded native auth transport and session custody,
  imported-key retention UX, secure-screen policy, authenticated
  Apple+Google integration against the Android-owned admission contract, and
  user-facing inbox/retry lifecycle. Finish automatic personal cloud concurrency/
  bounded I/O and live widget App Group/privacy integration. Do not silently drop
  sender/media/full recovery, staging or hardware acceptance from the final gate.
- Android has now supplied the six-route native account contract at `15751a7` in its
  `docs/TEAM_AUTH_HTTP_V1.md` (read-only checked SHA256
  `1f0791df923112808df25524a2106541008f26e273ac63690fb83ded64647235`;
  handler SHA256 `2f10b61feecc11962ecf0f1e3eea1c5c272fb5630d3fda607c70e4fe10818c48`).
  Exact next slice after this test checkpoint: bounded no-cookie/no-cache native
  HTTPS transport and strict response parsing, no redirects, followed by atomic
  device-only session custody with durable pre-dispatch refresh marker. No real
  base URL/provider IDs have been supplied; use synthetic tests, never invent or
  contact an endpoint. Re-read the peer contract/commit before implementation.
- Continuous implementation resumed at the owner's request. Current additional
  local slice: personal Files reads now use NSFileCoordinator off the main actor,
  balanced security-scoped access, regular-file-only descriptor reads, 64 KiB
  chunks and an actual-byte 128 MiB cap. JSON decoding/validation is off-main;
  SwiftData capture/merge/application remain main-actor operations. Cancellation
  stops pending coordination/reads and avoids presenting a stale cancelled import.
- This is a new operational personal-backup size limit, not a v8 schema change.
  Export rejects encoded backups over the same cap. Existing larger backups are
  rejected visibly without changing financial records; large legacy/cross-platform
  recovery acceptance remains open. This does not bound every decoded allocation
  or make whole-account export streaming. Team v1 limits/wire are unchanged.
- Both existing widgets now declare circular, rectangular and inline Lock Screen
  families, with family-specific layouts. Home Screen text uses semantic foreground
  when tinted or when its container background is removed. No financial values,
  App Group, entitlements, capability or live snapshot sharing was added.
- Backup status now says "Backup exported", not a blanket "Healthy local export"
  claim based on an old successful write. It does not verify continued destination
  availability, freshness or restoration. New size error has all 16 translations.
- Current-slice validation is tracked in VALIDATION.md. No additional TestFlight
  upload, source push, physical phone or shared Infrastructure change.

- Tested source saved locally as `fac1834f4f1bf07942f8d2759fb5b4ec445ea503`.
  No remote push or release; the previous published source remains unchanged.
- Added bounded regular-file archive ingestion, immutable authenticated candidates,
  redacted descriptions, snapshot restore preview and atomic current-state recheck.
  Source is in `TeamPortableArchive.swift` and `TeamInbox.swift`; v1 wire unchanged.
- Added bounded own-account/team inbox pagination with stable date/ID ordering,
  scope-bound cursors and no ACK/deletion side effects. No production entry point.
- Added device-only recovery-key custody through Security: account/purpose scope,
  non-synchronizing WhenUnlockedThisDeviceOnly items, no overwrite or automatic
  regeneration, strict stored-item validation and no key deletion API.
- Core regression: 50/50 passes. Final signed Simulator system-Keychain round trip
  passed, including refused overwrite and synthetic test-item cleanup. Exact
  result: 71 passes, one explicit hardware-protection skip, zero failures. Unsigned
  iPhone Release build passed. Paths and failed-attempt boundaries: `VALIDATION.md`.
- The first unsigned Keychain run failed with errSecMissingEntitlement (-34018),
  not a source-policy failure. Rerunning with local ad-hoc Simulator signing and
  the existing team/application identity passed. Do not skip the real Keychain
  test or use unsigned app-host tests for this slice. No Apple account settings,
  capability registration, provisioning download or project signing edits.
- Full audit research is at `OPENMLS_AUDIT_ADOPTION_20260904.md`: exact reviewed
  commit, excluded providers, public fix ancestry and unclosed storage-failure
  issue. No library/provider installed or crypto/session/team service activated.
- Android mirrored immutable candidate/preview semantics and reports 84/84 JVM
  tests at `ca68a77`. Read-only iOS review found no demonstrated semantic mismatch;
  Android tests were not independently rerun here. No raw URI/path behavior parity
  is claimed: Android owns InputStream closure; iOS owns its opened file descriptor.
- No source push, TestFlight upload, project signing/version change, physical-phone access
  or shared infrastructure action in this continuation. Apple+Google direction is
  accepted; actual provider configuration remains coordinated with Android.
- Next integration gates: configure and validate the accepted Apple+Google direction,
  approve a reviewed encryption library/provider and crash-safe storage design, freeze sender/
  revision/media archive coverage jointly, then implement authenticated team/Files
  UX and complete staging acceptance. Do not wire incomplete recovery into production.

## Current TestFlight build 3 publication — complete

- Owner explicitly approved the additional archive source export and continuing
  through TestFlight. Push of `ce246cf` and `0183278` succeeded; remote exact tip
  `01832788f50ccfee00cfb00d5a262fb0f40256b2` was independently verified.
- App Store Connect was refreshed: build `0.1.0 (2)` is now **Testing**, with both
  existing internal and external Zaid testing groups assigned. This closes the
  prior locked-screen status gap, not proof of tester installation.
- Build 3 increments app and widget together, keeping version `0.1.0`, identifiers
  and signing team unchanged. Signed archive and full Simulator tests passed.
  No app/widget entry point invokes team inbox or encrypted archive code; team
  sharing and recovery UI remain disabled until the documented activation gates.
- Publication target is TestFlight and the existing groups only, not public
  App Store release, new testers, public invitation links or Infrastructure.
- Final source `444b18d595133a6f7b291bfd45ab807fa7af3aa2` passed the full Simulator
  suite: 56 app tests plus 10 UI tests, one explicitly skipped hardware check.
  Signed Release archive and signature verification passed. Evidence is in
  `docs/VALIDATION.md`. Local IPA export succeeded, 5,505,946 bytes:
  `build/releases/0.1.0-3/export/Pinbook.ipa`, SHA-256
  `05c593e58cdd7a60a817c01dba7852fa141ece4bcf9ae87d8dc1cbb2dd122edb`.
  ZIP integrity passed; distribution summary confirms arm64, app/widget build 3,
  Cloud Managed Apple Distribution signing and get-task-allow=false.
- Local IPA is a separate export from the same archive, not a byte-equality claim
  about Apple's upload package. Upload succeeded on 2026-09-04 at 15:47:36
  Asia/Shanghai (`EXPORT SUCCEEDED`); Apple processing completed successfully.
  Do not duplicate the upload.
  Log: `/private/tmp/pinbook-testflight-3-upload.log`. Beta review notes were saved
  and explicitly disclose that team features are inactive. Existing contact and
  no-sign-in configuration were preserved.
- Apple build ID: `c43396a3-4fbd-4475-bbf9-6fcc819ee3c2`, app `6807481054`.
  Both existing Zaid testing groups are attached: internal
  `6178030b-38c6-4016-868a-5ee48376d920` and external
  `efe63df8-e238-4717-9921-a37d9a715993`, each with three testers.
  Saved build-specific What to Test, submitted external review with automatic
  tester notification enabled, then independently opened each group's Builds tab:
  **0.1.0 (3) is Testing in both internal and external groups**.
- No public App Store release, new testers, public-link creation/change, phone
  connection, personal-data reset or team activation. The external group already
  had a public invitation link; it was not created, changed or redistributed here.
  No installation of Apple's processed build 3 is claimed. Owner may open
  TestFlight and update Pinbook; no account action is required for publication.

## Current isolated team-delivery workstream

- Portable received-text archive/restore is now implemented locally. Read
  `docs/TEAM_ARCHIVE_V1.md` for the frozen cross-platform profile and
  `docs/TEAM_DELIVERY_IOS.md` for native implementation boundaries. Final core
  tests passed 36/36; final Simulator app tests passed 56 executed with one
  hardware-only protection check skipped (57 discovered). Unsigned iPhone Release
  build passed. No current-slice UI regression or physical-device result is claimed.
- Node, iOS SQLite-export and Android Room/JCA-returned PUBLIC fixtures pass
  CryptoKit conformance and native SQLite restore/re-export checks. Android reports
  77/77 tests at `69822e1`, including Room/JCA consumption of the exact iOS fixture.
  Restore is atomic and archive-only: no ACKs, enrollment or remote access restored.
  Ten-member pilot policy now permits nine peer recipients, excluding the sender.
- This remains inactive source-only work: no recovery-key custody/Files UI, outbound
  drafts/revisions/media recovery, group encryption, authenticated transport or
  real-user activation. Hardware protection and complete cross-platform recovery
  remain gates. Archive code/tests/docs are committed locally at `ce246cf`.
  The normal push was rejected by auto-review because the prior source-export
  approval was judged limited to the earlier payload, not this new archive slice.
  No retry or workaround was attempted. Remote remains the previously verified
  `829938c`; direct owner approval is required to export this additional source to
  `zaidsafa/verbose-winner`, branch `codex/team-delivery-foundation`. No merge/release.
- Owner requested native local foundation coordinated with Android. Worktree:
  `/Users/zaidsmac/Documents/ChatGPT/TC Projects/pinbook-ios-team-delivery`, branch
  `codex/team-delivery-foundation`, based on `4c8087b`. The original iOS worktree
  and its uncommitted signing/project edits remain untouched.
- Read `docs/TEAM_DELIVERY_IOS.md` for scope, implementation, evidence limits and
  activation gates. `docs/TEAM_DELIVERY_V1.md` snapshots the Android-owned draft2
  contract. Shared fixture SHA-256:
  `af994f328144079960f0bcaa5f78ed6db91a8c02a3387b21c0251797583cf033`.
- Local text envelope, frozen account/device/enrollment policy, exact 30-day
  retention reference, sender exclusion, explicit cancellation, immutable archive
  plus receipt transaction, bounded outbox and enrollment-scoped receipt retirement
  are implemented. Media is rejected. No network or app/team UI entry point exists.
- Personal records, backup-v8 serializers, version/build and signing settings are
  unchanged. No phone, shared Infrastructure, App Store Connect or release action
  was performed for this workstream. Code commit: `5a99217379dcb35e475261e65ce45ba60fdf8b0e`.
- GitHub export was initially rejected by auto-review. The owner then directly
  approved the exact pending source/ancestor export in this task on 2026-09-04.
  The same normal push succeeded to `https://github.com/zaidsafa/verbose-winner.git`,
  branch `codex/team-delivery-foundation`. Code commit `5a99217` plus evidence docs
  are published as source only; no PR merge or release occurred. The branch includes
  four existing local localization/TestFlight baseline ancestors. The team-only
  comparison starts at `4c8087b`, not the older remote foundation branch.
- Local Swift tests: 24/24 passed (9 existing, 15 new). Simulator: 44 app tests
  passed, one hardware-only protection check explicitly skipped; 10/10 existing
  UI tests passed. Hardware protection is not claimed. See `docs/VALIDATION.md`
  for exact final-source versus Simulator evidence boundaries.
- Both final-source unsigned builds passed: generic iPhone Release and generic
  Simulator Debug. Compiled binaries include the final rollback-failure guard.
- Android froze the portable archive schema and public fixture; the native local
  implementation above supersedes the earlier feasibility-only hold. Do not invent
  group crypto or treat received-text recovery as complete pilot recovery.
- Infrastructure and Android were notified directly. Admission remains NEEDS_INFO.
  Auth/crypto/enrollment/recovery, portable encrypted Android/iOS archive transfer,
  complete durable media handling and deployment admission remain prerequisites.
  No E2EE, public activation, physical deletion, or worldwide compliance claim.

## Prior TestFlight build 2 publication

- Owner authorized publishing build 2 to all existing internal and external test groups.
- `Pinbook: Expense Ledger`, app ID `6807481054`, version `0.1.0 (2)` uploaded
  successfully to App Store Connect on 2026-09-04 at 11:59 Asia/Shanghai.
  Apple build ID: `f620a966-03b9-45ba-a056-ba850878c97c`.
- Processing completed. Build details confirmed both existing `Zaid testing`
  groups assigned: internal `6178030b-38c6-4016-868a-5ee48376d920` and external
  `efe63df8-e238-4717-9921-a37d9a715993`, each with three testers.
- Clicked Submit for Review for external testing with Automatically notify testers
  checked. The dialog closed and Groups (2) appeared. A final refresh of the
  external review status and internal availability was blocked because the Mac
  locked. Do not resubmit or claim Apple approval/tester installation without checking.
- Beta description, review notes, feedback email, and review contact information
  were saved. Contact values came directly from the owner and remain in App Store
  Connect, not in this repository. No sign-in is required. Cloud sync remains absent.
- Signed Release archive: `/private/tmp/Pinbook-0.1.0-2.xcarchive`.
  Upload log: `/private/tmp/pinbook-testflight-2-upload.log` (`EXPORT SUCCEEDED`).
- Preserved archive: `build/releases/0.1.0-2/Pinbook.xcarchive`.
  Local IPA: `build/releases/0.1.0-2/export/Pinbook.ipa` (5,404,007 bytes).
  SHA-256: `dbcdf50deacfdd8fd85c84968df61bcde21c04f7e07b0b06a34766b98ce5e881`.
  ZIP integrity and app/widget identifiers/version/build were verified. This is a
  separate export from the same archive, not proof of byte equality with Apple's
  uploaded package. No manual re-upload is needed. Release artifacts are Git-ignored.
- All 39 signed Debug tests passed on the physical iPhone 16 Pro, iOS 26.6.1.
  Result: `/private/tmp/Pinbook-TestFlight-2-Physical-Retry.xcresult`.
  This does not claim acceptance of Apple's processed Release binary. The owner
  subsequently disconnected the phone; any further automated UI checks should
  use the dedicated Pinbook simulator, not ask for the phone again unnecessarily.
- No public App Store submission, new testers, public invitation link, or GitHub
  push was authorized by this TestFlight publication request or performed.

## Ownership and source

- iOS repository: `zaidsafa/verbose-winner`
- Android read-only product reference: `zaidsafa/studious-potato`
- Initial Android compatibility baseline: Pinbook 0.4.2, `versionCode 8`, source `442ae6a5bd2dc8ee26d6a1006dd9dda9fe4c0985`
- Android workstream update superseding the rejected candidate: 0.5.0 is reported published from behavior source `9ad28646f3ddb5ebfa874421b44e40b4cfda8a74`. Its contract is system-default language, first-run and Options language controls, 16 languages including distinct Chinese scripts and Brazilian Portuguese, and Arabic/Urdu RTL. Generated initial drafts were explicitly authorized with feedback-driven corrections; native review is no longer a publication prerequisite, and the drafts must not be described as native-reviewed or professionally translated.
- Initial iOS `main` bootstrap: `7b7fb061e22539632a13b9b5aa5c378235c83684`
- Active feature branch: `codex/pinbook-ios-foundation`

## Implemented scope

- Localization now includes 256 source keys with complete values for all 15 non-English locales (16 languages including English). The owner requested direct assistant translation, so the 13 new catalogs were authored without a translation service. First-run/Options controls persist choices and update view/service localization and Arabic/Urdu direction. Build 2 passed signed Debug iPhone tests and was uploaded to TestFlight; installation of Apple's processed Release build remains unverified. This is not a public App Store release.

- Swift package foundation with Android backup-v8-compatible records.
- ISO currency-aware minor-unit money parsing and formatting.
- Deterministic newest-record merge with local-wins-ties behavior.
- Explicit service boundaries for Drive backup, receipts, statements, reminders, and later OCR.
- Native iOS 26.1 SwiftUI application and unit-test targets.
- SwiftData persistence for books, expenses, settlements, templates, receipt metadata, appearance, favorite currencies, reminders, and cross-platform timestamps.
- Working expense entry, partial payments and remaining balance, reversible noted flow, currency-separated summary, five visual skins, and grouped Options.
- Versioned four-page first-run introduction is brief, skippable, and replayable from Options. Production creates no fixture financial records, and the milestone performs no destructive reset or migration of returning-user data.
- All five skins now resolve backdrop, surface, and accent colors for both light and dark appearance. The picker adds distinct SF Symbols, compact palette previews, descriptions, animated selection, and semantic text; Reduce Motion disables ornamental transitions.
- All 16 languages cover current app, onboarding, accessibility, and widget strings. Arabic/Urdu use RTL, Chinese scripts are distinct, and user-authored content is not translated. Seven Simplified Chinese archive-related strings were corrected to distinguish archiving from full payment.
- Native Liquid Glass tab bar, minimizing behavior, bottom accessory, toolbar/buttons, sheet presentation, and grouped custom glass actions; information cards stay on stable themed surfaces.
- Arabic shell localization, RTL-safe semantic layout, and bidirectional isolation for financial values.
- Debug-only deterministic launch fixtures use an ephemeral SwiftData store to exercise populated expenses, a partial payment, three currencies, Summary, Noted, and grouped Options without contaminating production bootstrap.
- Accessibility-size layouts stack card metadata/actions, switch Expenses to an inline title, and remove the optional Quick Add accessory while retaining the toolbar Add action.
- Book management supports create, rename, active-book selection, recoverable archive, and restore. The active book cannot be archived, and production bootstrap repairs an invalid active-book reference.
- Expenses, Summary, and Noted are isolated to the active book; settlements and currency totals cannot leak across that boundary.
- Favorite currencies remain empty in production until the user explicitly enables them. A permanently searchable selector lists all 159 Foundation common ISO currency codes with a symbol tile, ISO code, localized name, and independent switch; ambiguous or unavailable distinct symbols fall back to a neutral currency glyph while the code stays visible.
- The embedded `PinbookWidgets` extension supplies two privacy-safe Home Screen widgets. Quick Expense opens a clean expense form and Balance Overview opens Summary. Neither widget displays amounts or reads shared financial data, and no App Group/iCloud capability was added.
- TestFlight groundwork uses app bundle `com.zaidsafa.pinbook.ios`, widget bundle `com.zaidsafa.pinbook.ios.widgets`, version `0.1.0`, build `1`, and automatic signing pinned to Apple team `F98S3VN5NL` for both distributable targets. No signing or account-side mutation was performed during this milestone.
- The app now has a full-bleed 1024×1024 opaque App Store icon, an embedded `PrivacyInfo.xcprivacy` declaring no tracking/collection and app-only UserDefaults reason `CA92.1`, plus `ITSAppUsesNonExemptEncryption = NO` for the current no-custom-encryption build.
- `docs/TESTFLIGHT_SUBMISSION.md` provides copy-ready app-record fields, TestFlight review copy, App Store listing copy, privacy/compliance answers, and the upload sequence. `docs/PRIVACY_POLICY.md` is a publish-ready policy draft with a support-email placeholder.
- Users can create, edit, and soft-delete active-book templates. Expenses can be starred or unstarred as Favorites directly from their cards.
- Quick Add presents active-book Favorites and templates in a native half-height sheet and copies the selected source into a fresh, open, unstarred expense with a new identity and current date.
- SwiftData tombstones use `isTombstoned` internally to avoid the framework's `isDeleted` lifecycle collision; cross-platform backup records retain the Android-compatible `isDeleted` field.
- Expense cards open a private receipt sheet. Apple PhotosPicker grants only the selected image, which is copied to app-private Application Support storage under a UUID filename with protected file attributes; no broad photo-library permission is requested.
- Receipt import and removal coordinate file bytes with SwiftData metadata, compensate failed metadata saves, reject traversal filenames, and retain a confirmation step before UI deletion.
- Statements generate on-device PDF and CSV for exactly one active-book person and one currency. CSV retains exact minor-unit integers; both formats exclude private notes and never apply an implicit exchange rate.
- Statement files are temporary and backup-excluded, and become externally visible only if the user activates the native ShareLink workflow.
- PDF rendering is appearance-independent for printing: every page is explicitly white with black/dark-gray ink. CSV protects spreadsheet consumers by neutralizing formula-leading user fields, and both formats surface arithmetic overflow instead of clamping.
- Receipt removal persists its tombstone before deleting private bytes. If persistence fails, rollback keeps both live metadata and the file; a later byte-removal failure can leave an orphan but cannot leave live metadata pointing to a missing file.
- Books and Statements reserve shared bottom scroll clearance, and UI automation proves their final identified content can be moved fully above the floating Liquid Glass tab bar.
- Local reminders request notification authorization only during an explicit reminder-bearing save. Scheduled notification copy is generic, and pending requests are cancelled when a reminder is cancelled or its expense is marked noted.
- Local Backup & Recovery exports the complete Android-compatible version-8 envelope through native Files, validates imported content and references before mutation, previews add/update/unchanged/conflict counts by entity, keeps local records on equal-timestamp conflicts, and never converts or combines currencies.
- A confirmed restore saves an exact pre-restore snapshot before transactional apply. Recovery replaces the financial domain with that snapshot; receipt bytes are staged before SwiftData changes, and activity history stores only privacy-safe metadata and opaque failure codes.

## Validation

- Completed draft milestone (2026-09-04): 256 keys × 15 translated locales plus English passed the offline check; compiled Debug/Release app and widget strings exactly match source. All 16 language choices are present. The final full Simulator scheme passed 39/39 (29 app tests, 10 UI tests), and Swift package tests passed 9/9. Unsigned generic iPhone Release build passed. Final result: `/private/tmp/Pinbook-Translations-Final.xcresult`; logs: `/private/tmp/pinbook-translations-final.log` and `/private/tmp/pinbook-translations-release-final.log`. New tests cover Traditional Chinese → Urdu → System Default, preserved onboarding position, mirrored Urdu controls, compiled catalog counts and supported-secondary-language direction. Final screenshots `docs/evidence/pinbook-language-zh-hant.png` and `docs/evidence/pinbook-language-ur.png` were visually inspected. No exact-build physical acceptance or publication occurred.

- Language-control milestone (2026-09-04): 9/9 Swift package tests and 37/37 complete-scheme simulator tests passed (28 app tests, 9 XCUITests) on the dedicated iPhone 17 Pro. The final result bundle is `/private/tmp/Pinbook-Language-Final.xcresult`. An unsigned generic iPhone Release build passed. Existing English/Arabic/Simplified Chinese coverage is 256 keys, with no missing values or format-token mismatches. New tests verify live English → Arabic → Simplified Chinese introduction changes, mirrored Arabic controls, saved choice across relaunch, System Default reset, independently localized service messages, and exact Arabic/Urdu/Hindi decimal-digit parsing. Visual evidence: `docs/evidence/pinbook-language-switch-ar.png`. This does not validate the pending 13 catalogs, Urdu UI, widget override sharing, TestFlight delivery, or exact-build physical acceptance.

- `swift test --disable-sandbox --scratch-path /private/tmp/pinbook-ios-swift-build` passed all 5 tests on Xcode 26.6 / Swift 6.3.3.
- The alternate scratch path was required because the managed environment denied SwiftPM's user cache and nested sandbox; this is an environment boundary, not a source failure.
- Unsigned generic iOS Simulator build passed against SDK 26.5 with deployment target 26.1.
- The iOS test bundle compiled, and all 3 in-memory SwiftData tests passed on a dedicated iPhone 17 Pro simulator: clean production bootstrap, persisted partial payment, and currency-separated summary totals.
- The clean-launch Expenses screen was visually inspected in English and Arabic RTL on that simulator; screenshots: `docs/evidence/pinbook-empty-expenses.png` and `docs/evidence/pinbook-empty-expenses-ar.png`.
- The final simulator suite passes 5/5 tests after adding deterministic fixture/configuration coverage; Swift package tests remain 5/5.
- Unsigned Debug and Release generic iOS Simulator builds pass. Release compilation excludes all fixture population code.
- Populated visual evidence now covers Paper Glass Expenses, Soft Pastel Summary, Night Ink Noted, grouped Options, Arabic RTL, accessibility extra-extra-large text, Increase Contrast, and Reduce Transparency. See `docs/VALIDATION.md` for the evidence map.
- Clean Ledger and Editorial now have accepted light/dark populated evidence. All skin backdrops adapt to color scheme; the initial Clean Ledger dark contrast defect was fixed before acceptance.
- The book milestone passes 7/7 simulator tests. Interactive acceptance created/selected a second book, proved its Expenses view was empty, switched back to prove the original records remained, then exercised rename, archive, and restore. Evidence: `docs/evidence/pinbook-books-management.png`.
- The Templates/Favorites/Quick Add milestone passes 9/9 simulator tests with unique ephemeral stores for parallel isolation. Interactive acceptance verified accessible star controls, both Quick Add source groups, and a fresh expense created from the fixture template. Evidence: `docs/evidence/pinbook-quick-add.png`.
- The receipt milestone passes 11/11 simulator tests. Interactive PhotosPicker acceptance imported a deterministic image, displayed its attachment metadata, and verified the copied 2,853,668-byte UUID-named PNG inside Pinbook's private Simulator container. Evidence: `docs/evidence/pinbook-private-receipt.png`.
- The statement/reminder milestone passes 14/14 simulator tests. Interactive acceptance generated a 178-byte exact-value CSV and a 28,996-byte one-page PDF for one person/currency scope without opening the share sheet. The reminder overview showed generic privacy guidance and a future fixture date. Evidence: `docs/evidence/pinbook-statements.png` and `docs/evidence/pinbook-reminders.png`.
- The follow-up complete scheme passes 20/20 on the dedicated iPhone 17 Pro simulator (19/19 isolated tests plus 1/1 XCUITest). It covers dark-mode print-safe PDF pixels, CSV formula neutralization, explicit statement-overflow failures, receipt tombstone-save failure ordering, and final-row/help reachability above the tab bar. Evidence: `docs/evidence/pinbook-statements-dark-reachability.png` and `docs/evidence/pinbook-dark-generated-statement-pdf.png`.
- The local backup milestone passes 7/7 Swift package tests and 26/26 complete-scheme tests on the dedicated iPhone 17 Pro simulator (22/22 isolated tests plus 4/4 XCUITests). It covers full version-8 export/round trip with receipt bytes, deterministic preview/local-wins ties, currency separation, corrupt/unsupported no-financial-mutation, pre-restore snapshot creation, exact recovery rollback, English dark plus Arabic RTL reachability, and native Files export/import sheet presentation without saving or selecting a document. Unsigned Debug and Release builds pass. Evidence: `docs/evidence/pinbook-backup-recovery-dark.png`, `docs/evidence/pinbook-backup-recovery-ar.png`, and `docs/evidence/pinbook-files-import-picker-physical.png`.
- The signed Debug build also installed on a wired iPhone 16 Pro running iOS 26.6, where the complete scheme passed 26/26. Physical English dark and Arabic RTL screenshots replaced the earlier Simulator captures for the two backup-screen evidence files. The native export and import sheets both opened on that phone; automation terminated Pinbook without pressing Save or selecting a file. Tests used isolated fixtures/temporary storage and did not touch production financial data.
- The Simulator accessibility tree exposes card labels, labeled remaining values, and Payment/Mark noted actions in logical order. Spoken VoiceOver, rotor, and physical-device focus behavior remain outside this evidence boundary.
- The UX/localization/currency/widget milestone's final Simulator result bundle covers 33 tests: 26 isolated app tests plus 7 XCUITests. It includes new-vs-returning onboarding behavior, both widget routes, all 159 Foundation common ISO currencies, 10 skin/appearance contrast combinations, Simplified Chinese onboarding traversal, Night Ink/Light readability, searchable symbol/name/code currency selection, and the existing Files/backup regressions. Swift package compatibility remains 7/7, and unsigned Debug/Release app builds embed the two-widget extension.
- Retained evidence for this milestone: `docs/evidence/pinbook-onboarding-zh-hans.png`, `docs/evidence/pinbook-night-ink-light-picker.png`, and `docs/evidence/pinbook-world-currency-picker.png`.
- TestFlight preparation passed a clean unsigned Release build for generic iOS and a clean unsigned archive at `/private/tmp/Pinbook-0.1.0-1.xcarchive`. Inspection confirmed arm64 app/widget binaries, both bundle identifiers, `0.1.0 (1)`, embedded privacy manifest, encryption declaration, widget extension, and generated iPhone/iPad icons.
- Post-preparation regression passed 7/7 Swift package tests and 33/33 complete-scheme Simulator tests (26 app tests plus 7 XCUITests). The result bundle was `/private/tmp/Pinbook-TestFlight-2.xcresult`; this temporary local evidence is not committed.

## Limitations

- Drive/OAuth, iCloud transport, and OCR remain unimplemented. Backup & Recovery is currently manual and local through Files.
- iCloud/CloudKit is not implemented. The planned provider design treats it as an optional alternative to Google Drive, not a simultaneous second sync authority.
- Statements are generated locally, but successful transfer through a chosen share extension was not exercised. Reminder request construction is implemented, but authorization and real notification delivery were deliberately not triggered during simulator acceptance.
- All 16 catalogs are complete, but draft coverage does not establish native fluency or exhaustive layout acceptance. User-authored content is not translated. Widgets follow system language, not the in-app override, because no App Group is used; already scheduled notifications are not rewritten when the language changes.
- Android's reported target locale set is English, Arabic, Turkish, Simplified Chinese, Traditional Chinese, Spanish, French, German, Brazilian Portuguese, Hindi, Indonesian, Japanese, Korean, Russian, Italian, and Urdu, with Arabic/Urdu RTL behavior. iOS must not advertise incomplete locale catalogs. Generated drafts are allowed with a feedback correction loop, but must not be represented as human-authored, professional, or native-reviewed translation.
- Widgets currently provide privacy-safe navigation only. Live counts or balances require an explicitly approved App Group entitlement, a versioned shared-snapshot format, signing/profile changes, and new privacy/physical-device acceptance; none is enabled here.
- The universal target declares all four standard interface orientations, but the complete iPhone/iPad rotation and multitasking layout matrix has not yet received visual acceptance.
- The current build passed 39 signed Debug physical-device tests. These do not prove widget gallery installation, installation of Apple's TestFlight Release binary, a completed external Files-provider transfer, real notification delivery, or App Store acceptance. The UI tests opened both system document pickers but did not save or select a file. Further automated checks should use the simulator while the owner's iPhone is disconnected.
- Existing Apple signing with automatic provisioning was used for device tests, archive, export, and upload. TestFlight metadata, group assignment, and external review submission were changed under owner authorization. No OAuth credentials or public App Store submission were created.
- The initial TestFlight audit reported no valid code-signing identities, so its archive was deliberately unsigned. The owner later supplied evidence of a processed build (below). This does not prove current signing availability or physical acceptance; localization resumption uses unsigned builds and does not mutate signing or upload a replacement.
- The owner subsequently supplied an App Store Connect screenshot showing `Pinbook: Expense Ledger`, processed TestFlight build `0.1.0 (1)`, the colorful icon, and `Ready to Submit`. This is screenshot evidence, not a live account audit or proof of tester installation/review approval. No App Store Connect mutation was performed during localization resumption. Before external testing, confirm final contact/privacy-policy details. The current **No Data Collected** answer applies only while records, receipts, and manual backups stay local; future cloud integration requires a fresh privacy audit.

## Exact next actions

1. When browser access resumes, read the external review status and internal availability for build `0.1.0 (2)`. Both groups are already assigned and Submit for Review was clicked; do not duplicate submission. Contact and feedback details are saved in App Store Connect. Apple approval is not yet verified.
2. Before a future public App Store submission, confirm the final public policy/support URLs and publish `docs/PRIVACY_POLICY.md` at the chosen HTTPS privacy-policy URL. Do not invent URLs or copy contact placeholders into Apple.
3. Use the simulator for further work while the iPhone is disconnected. When the owner chooses to resume physical acceptance, install the exact processed TestFlight build and run disposable-data checks: onboarding/locales, five-theme contrast, two widgets, receipt selection, local notification delivery, statement sharing, and a completed Files backup/export/import/recovery round trip.
4. Complete the remaining physical-iPhone accessibility pass for spoken VoiceOver, rotor behavior, focus order, Reduce Transparency, and Increase Contrast before App Store release.
5. Implement Google Drive `drive.appdata` only after explicit OAuth/provider approval, routing remote bytes through the existing validation, preview, snapshot, history, and deterministic conflict-recovery boundary. Re-audit App Privacy and update the privacy policy before shipping it.
6. Collect locale-specific wording/layout feedback from the exact candidate on iPhone. All catalogs are now directly assistant-authored drafts; no Google approval or external translation request is needed. The offline checker validates all 256 keys and placeholders and can compare compiled app/widget catalogs to source. Native review is not a blocker under the owner's authorization, but do not claim professional or native-reviewed quality.
7. Source commits remain local-only; the binary was uploaded to TestFlight. The earlier 2026-09-04 push was blocked by auto-review pending explicit owner approval to export commits to `https://github.com/zaidsafa/verbose-winner.git`, branch `codex/pinbook-ios-foundation`. No push was retried. Do not retry through another route without that authorization. Project changes committed for these milestones are the 13 added `knownRegions` lines and four build-number increments; the owner's pre-existing project/signing edits remain uncommitted and preserved.
