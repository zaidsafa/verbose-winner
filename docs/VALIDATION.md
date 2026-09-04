# Validation plan

## 2026-09-04 concrete Apple identity adapter — runtime check pending

- AuthenticationServices controller/delegate/scene-anchor adapter implemented,
  with callback ownership, cancellation quarantine, expiry/clock rollback checks
  and bounded, unverified Apple identity-token handling. No navigation activation.
- Six fake-driver app-host tests compile, including synchronous and stale callbacks,
  wrong state/provider/token, unavailable presentation, expiry and cancellation.
  They do not contact Apple or present an Apple account sheet.
- Exact Debug build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-apple-adapter-final-test-build.log`.
- Exact unsigned iPhone Release **PASS**, including DEBUG-only test injection
  exclusion and the final callback-time rollback check:
  `/private/tmp/pinbook-ios-apple-adapter-final-release.log`.
- Runtime test launch is pending fresh shared-GUI clearance from WooOrders iOS.
  No new app-host or UI pass is claimed. Prior124 passes/one hardware skip belong
  to checkpoint1ee16cf, not this adapter. Android's resource-batch hold was cleared;
  that does not independently clear the shared GUI slot.
- No client IDs, entitlement, signing, provider account, financial data, TestFlight
  build, source push or shared Infrastructure configuration changed.

## 2026-09-04 durable native sign-in coordinator (inactive)

- Seven new sign-in/reservation tests **PASS7/7** in0.029s:
  `/private/tmp/pinbook-ios-signin-coordinator-tests.log`. Consent and pre-cancelled
  callers do not contact the provider; existing sessions are not replaced; late
  callbacks/abandoned reservations cannot commit; wall/monotonic/state/provider
  failures never exchange; ambiguous storage never triggers a second exchange.
- Real localhost TLS challenge→synthetic provider callback→exchange→protected
  reservation commit test passed with exact route/field assertions. Initial full
  core103/103 passed at `/private/tmp/pinbook-ios-signin-coordinator-full-core.log`.
- After tighter per-challenge monotonic checks, a rerun stalled in test cleanup:
  `/private/tmp/pinbook-ios-signin-coordinator-final-core.log` is NOT passing evidence.
  Live sample `/private/tmp/pinbook-signin-core-stall.sample.txt` showed the test
  helper in Fixture.deinit→NSConcreteTask.waitUntilExit, although the Python child
  had exited. Sampled the still-live helper before explicitly terminating PID75035;
  parent exited1. Replaced all fixture waitUntilExit calls with a preinstalled
  termination handler and bounded semaphore wait, retaining failed cleanup evidence.
- Final full core **103/103 PASS** in12.764s:
  `/private/tmp/pinbook-ios-signin-coordinator-verified-core.log`.
- Review then fixed a two-read local-sign-out race between a login reservation
  and a concurrently committed session. `removeCurrent` reads the union once and
  deletes that exact generation; a concurrent replacement fails stale rather than
  returning false success. Full core rerun **103/103 PASS** in12.279s:
  `/private/tmp/pinbook-ios-signin-owner-final-core.log`; final unsigned Release
  **PASS**: `/private/tmp/pinbook-ios-signin-owner-final-release.log`.
- Exact final Simulator rebuild **PASS**:
  `/private/tmp/pinbook-ios-signin-owner-final-test-build.log`; app-host rerun
  **124 passes, one hardware skip, zero failures**:
  `/private/tmp/Pinbook-SignIn-Owner-Final-App.xcresult`, finish Unix1788523839.278;
  `/private/tmp/pinbook-ios-signin-owner-final-app.log`.
- Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-signin-coordinator-release.log`; Simulator test build
  **PASS**: `/private/tmp/pinbook-ios-signin-coordinator-test-build.log`.
- iPhone app-host **124 passed, one hardware file-protection skip, zero failures**:
  `/private/tmp/Pinbook-SignIn-Coordinator-App.xcresult`, finish Unix1788523458.477;
  `/private/tmp/pinbook-ios-signin-coordinator-app.log`. Actual isolated Keychain
  test includes login reservation commit/read/stale cancellation and rotation.
  macOS-only TLS fixture cleanup change is not part of the iPhone target.
- No UI source changed; UI13/13 remains prior-checkpoint evidence, not newly rerun.
  No real provider/credential/URL/navigation activation, source push or upload.
  `TEAM_SIGN_IN_COORDINATOR_IOS.md` distinguishes native orchestration from the
  still-required concrete Apple/Google controller/SDK adapters and live acceptance.

## 2026-09-04 one-owner rotating-refresh integration (inactive)

- Six coordinator tests pass for durable marker before dispatch, busy serialization,
  cancellation-ignoring transport, late response/new-login preservation, failed marker
  writes, lost response, ambiguous replacement, clock rollback/expiry and pre-cancelled
  callers. `/private/tmp/pinbook-ios-refresh-manager-tests.log`:6/6 in0.016s.
- Real localhost TLS integration now connects manager→HTTP→custody. Success saves
  the entire new pair;503/drop leave the pending barrier; a newly constructed owner
  cannot replay the old token. Each case has exactly one recorded request/body.
- HTTP completion waits for the final native session invalidation callback after
  cancellation, not just the request to cancel. All prior actual TLS cancellation,
  timeout, redirect, bounds and no-repeat cases remain green.
- Full core **95/95 passed** in12.963s:
  `/private/tmp/pinbook-ios-refresh-manager-full-core.log`. Unsigned iPhone Release
  **PASSED**: `/private/tmp/pinbook-ios-refresh-manager-release.log`. Simulator
  build-for-testing **PASSED**: `/private/tmp/pinbook-ios-refresh-manager-test-build.log`.
- iPhone app-host **117 passed, one hardware file-protection skip, zero failures**:
  `/private/tmp/Pinbook-Refresh-Manager-App.xcresult`, finish Unix1788522599.562;
  `/private/tmp/pinbook-ios-refresh-manager-app.log`. All six new coordinator
  tests and the prior actual isolated Keychain tests pass in the app host.
- No UI changes or provider/service activation. Physical-only acceptance remains
  open. No source push, signing/capability mutation, infrastructure change or upload.

## 2026-09-04 separate account-session Keychain custody (inactive)

- Seven new synthetic custody tests pass. Full core **88/88 passed** in12.243s:
  `/private/tmp/pinbook-ios-session-custody-full-core.log`. Focused7/7 result:
  `/private/tmp/pinbook-ios-session-store-tests2.log`. Initial test source needed
  explicit `try` inside Swift Testing's throwing `#require` expression; corrected
  before execution. No failed compilation is counted as a test pass.
- Tests cover passcode-only/non-sync attributes, explicit consent/add-only behavior,
  marker persistence with no old tokens, simulated reopen, before/after-commit
  failure ambiguity, eight competing refresh starts with one winner, newer login
  preservation against late callbacks, scope/corruption/unavailable reads, lifetime/
  clock/token checks and pre-cancelled writes. New and old storage remain separate.
- Unsigned generic iPhone Release **PASSED**:
  `/private/tmp/pinbook-ios-session-custody-release.log`. Simulator test compile
  **PASSED**: `/private/tmp/pinbook-ios-session-custody-test-build.log`.
- A new app-host test uses actual SecItem calls in an isolated random test service,
  with DEBUG-only WhenUnlockedThisDeviceOnly protection. This checks generation
  query/update behavior, NOT physical passcode-only/non-backup acceptance. Public
  session construction always uses WhenPasscodeSetThisDeviceOnly; existing archive
  recovery-key protection is unchanged. See `TEAM_SESSION_CUSTODY_IOS.md`.
- Full iPhone app-host **111 passed, one explicit hardware skip, zero failures**:
  `/private/tmp/Pinbook-Session-Custody-App.xcresult`, finish Unix1788522079.999;
  `/private/tmp/pinbook-ios-session-custody-app.log`. Actual Keychain generation
  test passed in0.006s and removed its isolated test item. UI suite not rerun;
  no UI source changed. The hardware skip concerns file-protection attributes.
- No provider/refresh coordinator or normal navigation activation; no source push,
  capability/signing change, production service or TestFlight upload.

## 2026-09-04 inactive native account HTTP and one-use request body

- Six-route scoped adapter, bounded strict response codec, default platform TLS,
  no cookies/cache/ambient credentials/redirects, sanitized errors and one-use
  request streams implemented. Both replacement stream callbacks return nil.
  Refresh rejects account/family/absolute-expiry changes and reuse of either old
  token in either returned field. No production origin or entry point is enabled.
- Initial HTTP slice core77/77 passed at
  `/private/tmp/pinbook-ios-auth-http-tests.log`. iPhone app-host **103 passes,
  one explicit hardware skip, zero failures** at
  `/private/tmp/Pinbook-Auth-HTTP-App.xcresult`, finish Unix1788520381.284;
  `/private/tmp/pinbook-ios-auth-http-app.log`. This preceded the stream change.
- Four additional real localhost TLS tests passed on macOS Foundation/CFNetwork:
  default untrusted certificate rejected before HTTP; exact public refresh body;
  one request/body on503 Retry-After:0,408 and lost response; redirects not followed;
  fixed/chunked overflow rejected; cancellation and10s stalled-body timeout.
  `/private/tmp/pinbook-ios-auth-tls-verified.log`:4/4 in11.990s.
  Initial TLS fixture failures in `pinbook-ios-auth-tls-tests.log` were diagnosed
  as missing serverAuth EKU in the generated test certificate. Fixed that fixture;
  no relaxed trust evaluation or system trust-store installation. Certificate/key
  exist only in per-test private temporary directories and are removed afterward.
- Final full core **81/81 passed** in12.165s:
  `/private/tmp/pinbook-ios-auth-tls-full-core.log`. A separate scratch cache was
  used after `.build/build.db` reported a disk I/O error in a diagnostic run;
  the failed diagnostic is not counted as acceptance.
- Unsigned generic iPhone Release **PASSED**:
  `/private/tmp/pinbook-ios-auth-tls-release.log`. Simulator build-for-testing
  **PASSED**: `/private/tmp/pinbook-ios-auth-tls-test-build.log`.
- Post-stream iPhone app-host rerun **103 passes, one hardware skip, zero failures**:
  `/private/tmp/Pinbook-Auth-TLS-App.xcresult`, finish Unix1788521450.064;
  `/private/tmp/pinbook-ios-auth-tls-app.log`. Compiled Release app/widget catalogs
  match286 keys in all15 translated locales (30 catalogs); English source fallback
  is distinct from its35 explicitly compiled overrides, not a missing translation.
- No UI changed in this slice. Prior complete UI13/13 evidence remains at the
  native/recovery checkpoint below; not newly rerun by the HTTP-only app-host run.
- These local tests do not prove universal exactly-once delivery, physical-device
  TLS/protected custody or live provider/service acceptance. Durable pre-dispatch
  marker, atomic session replacement, native provider flow and staging remain gates.
  See `TEAM_AUTH_HTTP_IOS.md`. No source push or TestFlight upload.

## 2026-09-04 recovery lifecycle and explicit key setup (inactive)

- Final tested source saved locally at `3b02975`. Combined app/UI regression
  **PASSED108 tests (95 app +13 UI), one explicit hardware-protection skip,
  zero failures**: `/private/tmp/Pinbook-Native-Recovery-Final.xcresult`, log
  `/private/tmp/pinbook-ios-native-recovery-final.log`, finish Unix1788519214.739.
  Both native Files dismissal and the later key-setup/background test pass together.
  Earlier failures below are preserved, not silently substituted or counted as passes.
- New actor setup tests cover consent/export/confirmation, no premature custody,
  wrong content with matching suffix, no replacement, token-scoped cancellation,
  read failure, ambiguous own-add reconciliation and losing a race to another key.
  Presentation tests reject late background work and retain uncertain restore
  state until an authoritative preview. Core: **62/62 passed** at
  `/private/tmp/pinbook-ios-key-setup-final-core.log`.
- Initial full Simulator run: **100 passed, 1 failed, 1 hardware skip**.
  `/private/tmp/Pinbook-Key-Setup-Full.xcresult`, log
  `/private/tmp/pinbook-ios-key-setup-full.log`, finish Unix1788517423.598.
  The key-setup UI test tapped SwiftUI's labeled Switch container; hierarchy showed
  value0 and disabled Create. Changing to the nested native switch did not alone
  resolve the full-run failure. Both failed runs are retained; do not attribute
  the cause solely to that selector or call either suite fully passed.
- Second full run: **99 passed, 2 failed, 1 hardware skip** at
  `/private/tmp/Pinbook-Key-Setup-Verified.xcresult` (the historical filename does
  NOT mean it passed), finish Unix1788518491.324, log
  `/private/tmp/pinbook-ios-key-setup-verified.log`. Failures: native Files picker
  relaunch navigation and subsequent key-setup interaction. Extracted recording
  frames show the latter screen dimmed/blocked, not merely a disabled Create.
- After a fresh dedicated Simulator boot, unchanged key-setup source and the
  nested-control test **passed1/1**, including consent, disabled Finish before
  export, Home/background clearing and foreground reset:
  `/private/tmp/Pinbook-Key-Setup-Focused.xcresult`, log
  `/private/tmp/pinbook-ios-key-setup-focused.log`. Its screenshot was inspected:
  readable warnings/actions, masked confirmation field, no key shown. The prior
  Files test terminated its host with a native provider sheet still open. It now
  pulls the sheet down and verifies the underlying action is hittable BEFORE
  termination. The successful combined rerun above follows this change; no
  production switch workaround was introduced.
- Unsigned generic iPhone Release build PASSED:
  `/private/tmp/pinbook-ios-key-setup-release.log`. Static and compiled app/widget
  localization parity PASSED: **286 keys ×15 translated locales +English source**.
- Key setup UI is DEBUG-fixture-only until integrated; in-memory fake custody
  avoids real credentials. Native unit coverage reads an actual temporary64-byte
  key file through the coordinated reader before retention. This is not live
  Files-provider durability, separate physical storage or successful native export.
- Scene/background teardown clears pasted text, document/preview references and
  cancels scoped tasks. Late operation completions cannot repopulate active UI or
  clear a newer operation. Swift/String/FileDocument copies are not guaranteed
  physically erased. Exported user files are not deleted on cancellation.
- No Keychain accessibility change: WhenUnlockedThisDeviceOnly remains in use.
  [Apple's passcode-only class](https://developer.apple.com/documentation/security/ksecattraccessiblewhenpasscodesetthisdeviceonly)
  deletes its items when the passcode is removed; adopting it requires an explicit
  migration/recovery policy, not a silent strengthening that risks lost keys.
  No physical screen/passcode/access-control acceptance is claimed.
- No source push, signing/capability mutation, shared infrastructure write or
  TestFlight upload. Build3 remains the published baseline.

## 2026-09-04 native sign-in binding (inactive)

- Added one-use native attempt/callback binding and actual Apple request
  construction, exact raw nonce plus independent local state, bounded unverified
  token submission, stale cancellation protection, clock/expiry validation and
  redacted descriptions/reflection. No live controller/provider/HTTP/session flow.
- Seven new synthetic tests; full core **69/69 passed**:
  `/private/tmp/pinbook-ios-native-signin-final-core.log`.
- Unsigned iPhone Release **PASSED**:
  `/private/tmp/pinbook-ios-native-signin-release.log`. Compiled Release app/widget
  catalogs exactly match all286 keys ×15 translations +English source.
- iOS app-host tests and complete UI rerun PASSED in the combined108-pass result
  above, including all seven native sign-in tests. See `TEAM_NATIVE_SIGN_IN_IOS.md`
  for implemented API and outstanding provider/controller/transport integration.

## 2026-09-04 continuous final-update work: personal import and widget families

- Tested source checkpoint: `f6e6e26c1e3280f1202b7d2b5b74ab9d4907bf7c` (local commit).
- Current uncommitted slice implements cancellable, coordinated, bounded personal
  file reads, off-main decoding/validation and 128 MiB import/export admission.
  New tests cover exact cap, short reads, extra bytes after cap, read failures,
  symlink/directory/FIFO/missing/non-file rejection, coordinated local reading,
  cancellation and no preview/snapshot/financial mutation after cancellation.
- First sandboxed Simulator run could not access CoreSimulator (exit 70). Retried
  with approved local Simulator access, without changing devices or signing config.
- First native test run found only the stale 256-key localization-count assertion:
  all 15 translated catalogs now have 257 keys. New functionality tests passed;
  this run as a whole FAILED and is not counted as a pass. Evidence:
  `/private/tmp/Pinbook-Personal-Read-Verified-2.xcresult` and
  `/private/tmp/pinbook-ios-personal-read-simulator-2.log`.
- Source and compiled app/widget catalog check PASS: 257 keys in each of 15
  translated languages, plus English source; placeholder tokens match. Command:
  `python3 scripts/localization_drafts.py --check-built-app /private/tmp/pinbook-ios-recovery-key-signed-derived/Build/Products/Debug-iphonesimulator/Pinbook.app`.
- Core rerun PASS 50/50: `/private/tmp/pinbook-ios-core-continuation.log`.
- Full signed Simulator app/UI regression PASSED against the updated source:
  `/private/tmp/Pinbook-Personal-Widgets-Full.xcresult` and
  `/private/tmp/pinbook-ios-personal-widgets-full.log`. Verified xcresult summary:
  85 passes (75 app + 10 UI), one hardware-protection skip, zero failures;
  finished Unix time 1788513987.968. Dedicated Simulator remains
  `4A87A62E-C254-4FBE-8673-7D089E4165C1`; no other project device is touched.
- Widget family layouts compile in that build, but no widget-gallery, Always On,
  locked-device or live balance data acceptance is claimed.
- Unsigned generic iPhone Release build PASSED:
  `/private/tmp/pinbook-ios-personal-widgets-release.log`. No archive was created.
- No TestFlight upload, source push, version/signing/capability change, iPhone
  connection or shared Infrastructure mutation. Existing build 3 remains unchanged.

## 2026-09-04 received-text recovery UI and key text (inactive continuation)

- Local tested source commit: `a5d1cb3` (no source push or upload).
- Shared key-text parser and public fixture passed core 52/52:
  `/private/tmp/pinbook-ios-key-text-core.log`. Session orchestration passed 54/54:
  `/private/tmp/pinbook-ios-recovery-session-core.log`. A temporary unused-result
  warning in best-effort key-text scratch clearing was corrected afterward.
- Initial native app run passed (80 discovered, one hardware-only skip):
  `/private/tmp/pinbook-ios-recovery-flow-app.log` and
  `/private/tmp/Pinbook-Recovery-Flow-App.xcresult`. This preceded final screen
  cancellation cleanup, new translations and DEBUG-only UI fixture additions.
- New recovery strings are assistant-authored across 15 translations plus English.
  Static catalog check: 272 keys, all placeholder tokens valid. This is not a
  native-speaker review claim. Final compiled catalog check remains pending.
- First full screen run FAILED one UI test (two assertions): iOS supplied the
  dialog Cancel action without the assigned SwiftUI identifier. Hierarchy showed
  a single labelled Cancel and duplicate bridged Apply representations. Corrected
  the English-only test to use the observed Cancel label and first matching Apply.
  App tests and the Chinese screen test passed in this failed overall run:
  `/private/tmp/Pinbook-Recovery-UI-Full.xcresult` and
  `/private/tmp/pinbook-ios-recovery-ui-full.log`.
- Exported and visually inspected the Chinese preview screenshot: dark appearance,
  readable counts, wrapped scope explanation and visible apply action without
  clipping. Public fixture's 1970 export timestamp is intentional synthetic data.
  Evidence: `/private/tmp/pinbook-recovery-ui-evidence/C03A95AB-6399-4B60-85CA-C3D15F2692C7.png`.
- Final core 55/55 PASS at `/private/tmp/pinbook-ios-recovery-session-final-core.log`,
  including wrong-ID preservation and cancellation consuming a matched preview.
- Unsigned iPhone Release build PASS at `/private/tmp/pinbook-ios-recovery-ui-release.log`;
  DEBUG-only preview host excluded. No distribution archive or upload.
- All 272 keys in compiled app/widget match 15 translated source catalogs plus
  English source; exact placeholder check PASS.
- Corrected full app/UI rerun PASSED: `/private/tmp/Pinbook-Recovery-UI-Verified.xcresult`
  and `/private/tmp/pinbook-ios-recovery-ui-verified.log`. Verified xcresult summary:
  92 passes (80 app + 12 UI), one hardware-only protection skip, zero failures;
  finished Unix time 1788515575.215. Explicit cancel-then-confirm and Chinese
  preview tests both passed. Real provider selection/import, new-key
  consent/export, locked hardware and full team recovery remain unverified.

## 2026-09-04 post-release local recovery and inbox work

- Exact tested source commit: `fac1834f4f1bf07942f8d2759fb5b4ec445ea503` (local only).
- No TestFlight upload, app/widget version increment, project signing changes,
  personal data reset, physical phone or shared Infrastructure action. Build 3
  remains the published baseline. No app entry point invokes these new APIs.
- Bounded regular-file ingestion/authenticated candidates, read-only restore
  counts, atomic conflict recheck, inbox keyset pagination and device-only
  recovery-key storage are implemented. Portable archive v1/schema unchanged.
- Core **50/50 passed**, log `/private/tmp/pinbook-ios-recovery-key-core.log`.
  Command: `swift test --disable-sandbox --scratch-path
  /private/tmp/pinbook-ios-team-foundation-swift`. Keychain policy tests use a fake
  backend; no real macOS/user Keychain items are accessed by this suite.
- Signed iOS Simulator **71 passed, one hardware-only protection check skipped,
  zero failures**. Result `/private/tmp/Pinbook-Recovery-Key-Signed-Simulator.xcresult`,
  log `/private/tmp/pinbook-ios-recovery-key-signed-simulator.log`. The actual
  Security round trip uses known PUBLIC test bytes in a unique test-only service;
  it verifies load/reopen, account isolation and duplicate-save refusal.
- Final rerun with an explicit test-item cleanup assertion **TEST SUCCEEDED**:
  `/private/tmp/Pinbook-Recovery-Key-Verified.xcresult`, log
  `/private/tmp/pinbook-ios-recovery-key-verified-simulator.log`; **71 passed,
  one hardware check skipped, zero failures**. This is the final test-source result.
- Simulator command uses explicit `-sdk iphonesimulator`, dedicated device
  `4A87A62E-C254-4FBE-8673-7D089E4165C1`, Debug, jobs 2, parallel testing NO,
  only-testing PinbookTests, `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`.
  Derived data: `/private/tmp/pinbook-ios-recovery-key-signed-derived`.
  No new capabilities, certificates or provisioning were registered/downloaded.
- The unsigned app-host attempt correctly failed actual Keychain access with
  -34018 (missing entitlement); it is not a pass or a reason to skip the test.
  Earlier command without explicit Simulator SDK also failed test-host discovery.
  Both failed attempts are retained in `/private/tmp/pinbook-ios-recovery-key-simulator.log`
  and `/private/tmp/pinbook-ios-import-preview-simulator.log` respectively.
- Final application source unsigned generic iPhone Release **BUILD SUCCEEDED**,
  `/private/tmp/pinbook-ios-recovery-key-release.log`. This was build only, not
  an archive, signed distribution artifact or upload.
- Coverage adds malformed/oversized files, short reads/growth/partial error,
  file replacement after preview, cross-connection conflict rollback, own-account
  scope, empty/idempotent restore, savedAt preservation, bounded stable pages and
  scope-bound cursors, redacted candidate descriptions, no-overwrite Keychain
  policy, wrong key/protection/scope and locked/error versus missing behavior.
- Historical import-only checkpoint: 43 core/63 Simulator passes +1 skip and
  Release passed. Paging checkpoint: 46 core/66 Simulator passes +1 skip and
  Release passed. Do not substitute those for the later Keychain-source results.
- XCUITests were not rerun for these inactive APIs; the published build's 10/10
  UI suite is historical evidence. Device lock/backup migration, Files provider
  coordination/cancellation, consent/key export/rotation, full sender/revision/media
  recovery, real group encryption/auth and staging remain unverified gates.

## 2026-09-04 TestFlight build 3 release candidate

- Candidate source: `444b18d595133a6f7b291bfd45ab807fa7af3aa2`, version `0.1.0`,
  app and widget build `3`. No signing, identifier, personal-data or runtime team
  activation changes. The original worktree's signing edits remain untouched.
- Final full dedicated Simulator run **TEST SUCCEEDED**: 56 app tests passed,
  one hardware-only protection test explicitly skipped, and **10/10 XCUITests
  passed**, zero failures. Result: `/private/tmp/Pinbook-TestFlight-3-Simulator.xcresult`;
  log: `/private/tmp/pinbook-testflight-3-simulator.log`. This closes the earlier
  current-source UI regression gap. No physical-device result is claimed.
- Signed generic iPhone Release **ARCHIVE SUCCEEDED**:
  `/private/tmp/Pinbook-0.1.0-3.xcarchive`; log:
  `/private/tmp/pinbook-testflight-3-archive.log`. System-trust `codesign --verify
  --deep --strict` passed. App/widget identifiers and build 3 verified. No public
  test vectors or test bundles are embedded in the app archive.
- Preserved archive: `build/releases/0.1.0-3/Pinbook.xcarchive` (Git-ignored).
  Local IPA export and TestFlight upload succeeded; exact hash and paths are in
  `CODEX_HANDOFF.md`. App Store Connect processing completed. Build details showed
  both existing groups; each group's Builds tab independently showed build 3 as
  **Testing** after external submission with automatic notification enabled.
  This proves TestFlight availability, not physical installation of processed build 3.

## 2026-09-04 inactive portable encrypted archive/restore

- Frozen profile: `docs/TEAM_ARCHIVE_V1.md`. Native CryptoKit JWE Compact `dir` /
  `A256GCM`; strict header/base64url/tuple JSON, 16 MiB plaintext and ciphertext,
  22,370,000-byte compact limit, 10,000 records. Production generates fresh nonces.
- Final core tests: **36/36 passed**. Log:
  `/private/tmp/pinbook-ios-team-archive-roundtrip-core.log`; command:
  `swift test --disable-sandbox --scratch-path /private/tmp/pinbook-ios-team-foundation-swift`.
- Final Simulator app tests: **56 executed/passed**, **one explicitly skipped**
  hardware protection test (57 discovered), **TEST SUCCEEDED**. Result:
  `/private/tmp/Pinbook-Team-Archive-Roundtrip.xcresult`; log:
  `/private/tmp/pinbook-ios-team-archive-roundtrip-simulator.log`.
  Dedicated iPhone 17 Pro `4A87A62E-C254-4FBE-8673-7D089E4165C1`, iOS 26.5,
  Debug, `-only-testing:PinbookTests`, `CODE_SIGNING_ALLOWED=NO`.
  This includes the prior rollback-close guard. XCUITests were not rerun for this
  inactive slice; their earlier 10/10 result remains historical foundation evidence.
- Final generic iPhone unsigned Release **BUILD SUCCEEDED**. Log:
  `/private/tmp/pinbook-ios-team-archive-final-release.log`.
- All three PUBLIC fixtures decrypt and reproduce byte-for-byte in CryptoKit tests:
  Node fixture `team-archive-v1-vector.json`, SHA-256
  `4a92f6b9f1f940daf73f8ed3774354ed3ef883ab0c397319da03f15da397d504`;
  iOS store-export fixture `team-archive-v1-ios-vector.json`, SHA-256
  `a08c173173a3d73243444db5862b46fd25187b00c43fdfd8528388578ad73a3a`;
  Android Room/JCA return fixture `team-archive-v1-android-vector.json`, SHA-256
  `c653fd21479780674344bf009f569de59279b0566d862b7fb7f9af516cb543a0`.
  All live under `Tests/PinbookCoreTests/Fixtures`; keys/nonces are public test
  material, never production key custody. Android reports 77/77 tests at `69822e1`
  including exact iOS fixture restore/re-export through Room and JCA. The returned
  fixture decrypts, restores and reopens through native iOS SQLite with unchanged
  archive content and no ACKs; it re-exports successfully. This proves the local
  received-text fixture round trip, not full real-user recovery. Test resources only.
- Twelve new archive tests cover authenticated tampering/wrong keys, alternate
  headers/noncanonical encoding, malformed JSON/Unicode/types/timestamps, exact
  10,000-record acceptance, independent size bounds, historical enrollment,
  account scoping, immutable conflict rollback, close/reopen, idempotence,
  preserved local savedAt and unaffected live receipt/personal fixture state.
- Foundation JSONDecoder accepted a trailing array comma during negative testing.
  A bounded fixed-shape syntax preflight now rejects that extension, comments and
  trailing input before JSONDecoder; all final tests include this correction.
- Account-wide SQLite export streams one SELECT snapshot into a bounded encoder;
  restore authenticates/validates everything before one archive-only transaction.
  No receipt outbox or enrollment changes. Nine peer targets pass; ten reject.
- No personal backup-v8 changes, migrations, signing/version change, phone, live
  team UI, network service, shared Infrastructure, release or App Store action.
  No key custody/recovery UI, group-crypto audit, outbound/revision/media recovery,
  physical lock/backup extraction or complete pilot recovery is claimed.

## 2026-09-04 inactive team-delivery foundation

- Isolated branch `codex/team-delivery-foundation` based on `4c8087b`; no release,
  signing/version changes, network/team UI, personal-data migration or live service.
  The original iOS worktree's user-owned signing/project edits were preserved.
- Shared Android draft2 fixture is byte-identical, SHA-256
  `af994f328144079960f0bcaa5f78ed6db91a8c02a3387b21c0251797583cf033`.
  Fixtures are test resources, not included in the production app.
- Final Swift package tests: **24/24 passed** (9 prior, 15 team). Command:
  `swift test --disable-sandbox --scratch-path /private/tmp/pinbook-ios-team-foundation-swift`.
  Log: `/private/tmp/pinbook-ios-team-foundation-swift-final.log`.
- Simulator app tests: **44 executed/passed**, with **one explicitly skipped**
  hardware-only Data Protection test (45 discovered). Result:
  `/private/tmp/Pinbook-Team-Foundation-Verified.xcresult`; log:
  `/private/tmp/pinbook-ios-team-foundation-simulator-verified.log`.
  Destination: iPhone 17 Pro `4A87A62E-C254-4FBE-8673-7D089E4165C1`, iOS 26.5,
  Debug, `-only-testing:PinbookTests`, `CODE_SIGNING_ALLOWED=NO`.
- Existing XCUITest regression: **10/10 passed**, including onboarding languages,
  RTL, theme/currency selection and native Files presentation. Initial result:
  `/private/tmp/Pinbook-Team-Foundation.xcresult`; log:
  `/private/tmp/pinbook-ios-team-foundation-simulator.log`.
  That initial combined run failed only its new protection-attribute assertion;
  its overall result must not be described as passed.
- The initial assertion incorrectly cast Apple's NSString protection value;
  correcting the cast revealed that this Simulator returns no protection attribute.
  The test was split: backup exclusion and 0700/0600 permissions still execute;
  the hardware protection test is explicitly disabled on Simulator and enabled on
  a physical iPhone. Hardware initialization verifies Complete protection before
  content writes. No phone reconnection or hardware acceptance is claimed.
- Coverage includes exact deadline/overflow, frozen sender-excluding targets,
  foreign device/enrollment/team rejection, contradictory cancellation/ACK sets,
  UTF-8 bounds and unpaired surrogate rejection, immutable redelivery, atomic
  receipt-insert failure rollback, all-connection close/reopen, concurrent duplicate
  receipt idempotency, enrollment-bound retirement, full bounded queues, independent
  account limits, unknown-schema refusal and preservation of personal fixture bytes.
- After the Simulator run, final review added fail-closed connection invalidation
  if ROLLBACK itself fails. The final **24/24** package run includes this change.
  Simulator execution above predates that final safeguard; no result is relabeled
  as exact-final iOS execution. Further device launches were held for another
  project's exclusive Simulator credential-entry window.
- Generic iPhone unsigned Release and generic Simulator Debug final-source builds
  both passed; logs are `/private/tmp/pinbook-ios-team-foundation-release-final.log` and
  `/private/tmp/pinbook-ios-team-foundation-debug-final.log`.
  Both binaries reference `sqlite3_close_v2`, confirming the final invalidation
  safeguard was compiled. This does not substitute for its iOS runtime fault test.
- Code commit `5a99217` was pushed on `codex/team-delivery-foundation` after the
  owner directly approved the precise source/ancestor export. An earlier auto-review
  rejection was respected; the same normal push succeeded only after that approval.
  This is source publication only, with no merge, runtime activation or release.
- Transaction-trigger failure/reopen tests are not sudden power loss, actual disk
  exhaustion or cryptographic durability proof. Hardware protection/lock behavior,
  actual OS backup extraction, portable encrypted Android/iOS archive transfer,
  authentication/enrollment/crypto, durable attachment verification, server ACKs,
  provider deletion and restore remain gates. Infrastructure is NEEDS_INFO.

## 2026-09-04 TestFlight build 2 physical validation

- App Store Connect upload succeeded and processing completed for `0.1.0 (2)`.
  Both existing internal/external groups were confirmed on the build. External
  Submit for Review was clicked with automatic notification checked; the final
  status refresh was blocked by the locked Mac, so approval is not claimed.
- Preserved archive: `build/releases/0.1.0-2/Pinbook.xcarchive`.
  Separately exported IPA: `build/releases/0.1.0-2/export/Pinbook.ipa`, 5,404,007 bytes.
  ZIP integrity and both embedded bundle versions/identifiers passed verification.
  SHA-256: `dbcdf50deacfdd8fd85c84968df61bcde21c04f7e07b0b06a34766b98ce5e881`.
- Set both app and widget to version `0.1.0`, build `2`; kept existing signing settings.
- Signed Release archive succeeded at `/private/tmp/Pinbook-0.1.0-2.xcarchive`.
  Verified the app bundle ID, team, arm64 architecture, build number, embedded
  widget, signature (using the system trust store), and all compiled language values.
- Connected iPhone 16 Pro: iOS 26.6.1. Developer services became available after
  unlock; no security setting was disabled. Initial test-runner signing failed
  because test targets had no team; supplying the existing team as a command-line
  setting resolved it without changing project signing configuration.
- Passed 39/39 signed Debug physical tests (29 app, 10 UI), including all existing
  backup/Files presentation tests and live Chinese/Arabic/Urdu language behavior.
  Result: `/private/tmp/Pinbook-TestFlight-2-Physical-Retry.xcresult`.
  Log: `/private/tmp/pinbook-testflight-2-device-retry.log`.
- Visually inspected `docs/evidence/pinbook-language-ur-physical-build2.png` for
  readable text, mirrored controls, and no clipping on the final introduction page.
- Physical tests use isolated fixtures and do not reset production financial data.
  This is a signed Debug test build, not proof of installation of Apple's processed
  Release binary. TestFlight installation, external provider transfers, notification
  delivery, widget-gallery installation, and spoken VoiceOver remain separate checks.

## 2026-09-04 complete translation draft milestone

- Directly authored the 13 remaining locales without Google or another translation service.
- Passed 9/9 Swift package tests and the final 39/39 complete Simulator tests
  (29 app tests, 10 XCUITests) on the dedicated iPhone 17 Pro, iOS 26.5.
- Final result: `/private/tmp/Pinbook-Translations-Final.xcresult`;
  log: `/private/tmp/pinbook-translations-final.log`.
- Passed unsigned generic iPhone Release build, log:
  `/private/tmp/pinbook-translations-release-final.log`.
- Offline check passed all 256 keys × 15 translated locales, plus English source.
  Both Debug Simulator and Release iPhone app/widget bundles exactly match the
  translation catalog. English source strings may be omitted by Xcode and fall
  back to their keys; all non-English bundles contain all 256 translated values.
- Verified all 16 language choices are compiled, distinct Chinese script bundles,
  localized service errors, and RTL when a supported secondary phone language is
  Arabic/Urdu. The existing persistence and System Default tests passed again.
- New UI coverage switches Traditional Chinese → Urdu → System Default while
  retaining the current onboarding page; checks Urdu navigation text and mirrored
  controls, advances to the final page, and returns to English without relaunching.
- Visually inspected final screenshots with readable, unclipped text:
  `docs/evidence/pinbook-language-zh-hant.png` and
  `docs/evidence/pinbook-language-ur.png`.
- Seven Simplified Chinese archive-related strings now distinguish archiving
  from full payment. Existing English and Arabic values remain unchanged.
- No financial-data reset, schema migration, signing change, physical install,
  GitHub push, TestFlight upload, or account mutation. Exhaustive layouts, native
  wording review, real device/widget installation, and external transfers are
  outside this validation. Translations remain assistant-authored drafts.

## 2026-09-04 language-control milestone

- Passed 9/9 Swift package tests and 37/37 full simulator tests (28 app, 9 UI).
- Passed unsigned generic iPhone Release build; no archive/upload/publication.
- Verified 256 English-source keys and complete Arabic/Simplified Chinese values
  with intact format tokens. The other 13 target catalogs remain pending.
- Verified live language changes on onboarding, Arabic RTL, persistence, System
  Default reset, localized service errors, and Unicode decimal-digit parsing.
- Result bundle: `/private/tmp/Pinbook-Language-Final.xcresult`.
- Visually checked `docs/evidence/pinbook-language-switch-ar.png`.
- No new physical-device or TestFlight acceptance; no claim of complete 16-language parity.

## Automated on every coherent milestone

- Run `swift test` for backup compatibility, merge behavior, and currency-safe money.
- Build the iOS app unsigned against the iOS simulator SDK.
- Compile and run the in-memory SwiftData tests for clean bootstrap, persistence, settlements, and currency-separated totals.
- Run `git diff --check` and confirm the working tree contains no generated build output or credentials.

## Visual and accessibility acceptance

- Inspect Expenses, Summary, Noted, grouped Options, add-expense, and partial-payment flows on an iPhone simulator.
- Check Paper glass, Clean ledger, Soft pastel, Editorial, and Night ink in light/dark appearances.
- Check native Liquid Glass controls while scrolling and during sheet presentation; information cards must remain stable and legible.
- Check Reduce Transparency and Increase Contrast, and verify that no state depends only on color.
- Exercise Dynamic Type through the accessibility sizes without clipped amount or action rows.
- Review VoiceOver labels/order and minimum control hit areas.
- Run in Arabic to verify right-to-left order, leading/trailing alignment, and mirrored navigation.
- Test empty, long-text, large-value, zero-decimal, two-decimal, and three-decimal currency states.

## Completed simulator matrix — 2026-09-01

The matrix uses `-PinbookFixture populated`, an in-memory SwiftData store available only in Debug builds. Production bootstrap remains empty apart from its default book and appearance settings. Deterministic launch arguments also select the initial tab, skin, and theme without writing sample records to the persistent store.

| Evidence | Scenario | Result |
| --- | --- | --- |
| `docs/evidence/pinbook-populated-paper.png` | Paper Glass, light, open expenses | Partial payment and remaining CNY balance visible; USD and three-decimal KWD cards remain separate. |
| `docs/evidence/pinbook-summary-soft-pastel.png` | Soft Pastel, light, Summary | Open/noted counts and CNY, KWD, USD totals are legible without a rectangular page backing. |
| `docs/evidence/pinbook-noted-night-ink.png` | Night Ink, dark, Noted | Populated recoverable item is legible on the stable dark surface. |
| `docs/evidence/pinbook-options-grouped.png` | Paper Glass, grouped Options | Personalize, Data, and Device groups are readable and unfinished capabilities remain explicit. |
| `docs/evidence/pinbook-populated-ar.png` | Arabic RTL, Paper Glass | Navigation, actions, and shell copy are Arabic and mirrored; financial values use bidirectional isolation. Fixture record content intentionally remains test-authored English. |
| `docs/evidence/pinbook-dynamic-type-axxxl.png` | Accessibility extra-extra-large | The title becomes inline, metadata and actions stack vertically, Quick Add yields to the toolbar Add action, and the first card has no clipped balance or action. |
| `docs/evidence/pinbook-increased-contrast-reduced-transparency.png` | Increase Contrast plus Reduce Transparency | Stable cards gain a stronger outline and native glass controls use an opaque, legible fallback. |
| `docs/evidence/pinbook-clean-ledger-light.png` | Clean Ledger, light, Expenses | Populated cards and native glass controls remain compact and legible. |
| `docs/evidence/pinbook-clean-ledger-dark.png` | Clean Ledger, dark, Summary | Adaptive navy backdrop restores clear title, footnote, card, and tab-bar contrast. |
| `docs/evidence/pinbook-editorial-light.png` | Editorial, light, Expenses | Warm editorial palette preserves card separation without a page-sized slab. |
| `docs/evidence/pinbook-editorial-dark.png` | Editorial, dark, Options | Adaptive brown backdrop and grouped dark surfaces remain readable throughout the Options hierarchy. |
| `docs/evidence/pinbook-books-management.png` | Books & currencies, Paper Glass, light | Two editable books are visible, the active book has a non-color-only checkmark, and favorite currencies remain individually controlled. |
| `docs/evidence/pinbook-quick-add.png` | Quick Add, Paper Glass, light | A native half-height Liquid Glass sheet separates starred expenses from named templates and retains a clear full-form action. |
| `docs/evidence/pinbook-private-receipt.png` | Receipt sheet after PhotosPicker import | The selected deterministic image appears as one attachment, and the sheet explains the selected-photo-only and app-private-storage boundary. |
| `docs/evidence/pinbook-statements.png` | One-person, one-currency statement workflow | Local PDF and exact-value CSV were prepared for Al Noor Trading/KWD; only explicit ShareLink actions expose the temporary files. |
| `docs/evidence/pinbook-reminders.png` | Local reminder overview | One future fixture reminder is readable and the screen states that Lock Screen notification copy intentionally omits financial details. |
| `docs/evidence/pinbook-statements-dark-reachability.png` | Dark-mode Statements UI automation | The generated PDF ShareLink and final help card are visible, and the help card clears the floating Liquid Glass tab bar. |
| `docs/evidence/pinbook-dark-generated-statement-pdf.png` | Actual PDF generated from the dark-mode UI test | The one-page statement paints a white page and uses black/dark-gray print-safe text despite dark app appearance. |
| `docs/evidence/pinbook-backup-recovery-dark.png` | Physical iPhone 16 Pro, Backup & Recovery, Paper Glass, dark | Format/count health, native Files actions, provider boundary, empty activity state, and privacy footer remain readable above the floating tab bar. |
| `docs/evidence/pinbook-backup-recovery-ar.png` | Physical iPhone 16 Pro, Backup & Recovery, Arabic RTL | The complete local backup screen is localized and mirrored, with the full inline title and privacy footer visible above the tab bar. |
| `docs/evidence/pinbook-files-import-picker-physical.png` | Physical iPhone 16 Pro, native Files import picker | Pinbook opened Apple's document picker to Recents. The test terminated the app without selecting a document or changing an external Files location. |
| `docs/evidence/pinbook-onboarding-zh-hans.png` | Simplified Chinese first-run introduction | New-user copy, page progress, Skip, and the primary Liquid Glass action render in Simplified Chinese; automation completes all four pages. |
| `docs/evidence/pinbook-night-ink-light-picker.png` | Night Ink selected with Light appearance | The former dark-on-dark combination now resolves to a bright adaptive surface with readable semantic text, distinct symbols, descriptions, previews, and a non-color-only checkmark. |
| `docs/evidence/pinbook-world-currency-picker.png` | Searchable world-currency selector | The always-visible search field, symbol tile, ISO code, localized name, and independent toggle produce a clean selector across Foundation's 159 common ISO codes. |

The Simulator accessibility tree exposed the open-expense elements in logical order: Add, heading, purpose, counterparty, labeled remaining balance/value, date, category, Payment, and Mark noted. Card actions have a minimum 44-point height; navigation uses the native tab bar. This verifies labels and structural order, not spoken VoiceOver output, rotor behavior, or physical-device focus behavior.

### Automated evidence

- Swift package: 5/5 tests passed.
- iOS simulator suite: 5/5 tests passed, including clean production bootstrap, persistence/partial payment, currency-separated totals, launch-argument parsing, and deterministic fixture contents.
- Unsigned Debug and Release generic iOS Simulator builds passed against SDK 26.5 with deployment target 26.1. The universal target declares all four standard interface orientations; the full rotation/layout matrix remains a separate visual-acceptance boundary.
- The Debug fixture is excluded from Release compilation by `#if DEBUG`; the Release build passed after this boundary was added.
- All five skins now have simulator evidence, and the two non-default remaining skins were checked in both light and dark. The first Clean Ledger dark capture exposed a light-only backdrop contrast failure; adaptive color-scheme backdrops fixed it before the accepted evidence was recorded.
- Book management and active-book isolation: 7/7 iOS simulator tests passed. The UI pass created and automatically selected a second book, verified its Expenses screen was empty while the original fixture book retained all three open expenses, renamed it, archived it, and restored it. Production bootstrap still asserts zero favorite currencies and no preferred currency.
- Templates, Favorites, and Quick Add: 9/9 isolated iOS simulator tests passed. The UI pass exposed the star control with accessible add/remove labels, showed one favorite and one template in Quick Add, created a fresh CNY 1,680 expense from the template without changing the source, and verified that Add different expense opens the full editor above the Quick Add sheet. A test failure revealed the SwiftData `isDeleted` lifecycle-name collision; app persistence now uses `isTombstoned`, and the soft-delete filter is covered by the passing suite.
- Private receipts: 11/11 isolated iOS simulator tests passed. Lifecycle coverage verifies generated sanitized filenames, exact byte reload, traversal rejection, physical file removal, and persisted metadata tombstoning. The interactive pass selected a deterministic image through Apple PhotosPicker; Pinbook displayed one attachment and a read-only container check found a 2,853,668-byte UUID-named PNG only under the app's private `Library/Application Support/Receipts` directory. The UI deletion confirmation was not activated; deletion behavior is covered by the lifecycle test.
- Statements and reminders: 14/14 isolated iOS simulator tests passed. Coverage verifies active-book/person/currency statement isolation, CSV quoting and UTF-8 BOM bytes, exact minor-unit original/paid/remaining values, deleted-settlement exclusion, valid PDF output, deterministic notification identifiers/date components, and generic notification copy without fixture purpose, currency, or amount. The interactive pass generated a 178-byte BOM/CRLF CSV and a 28,996-byte one-page PDF in Pinbook's temporary container, then showed both ShareLink actions without opening the share sheet. The reminder overview displayed a deterministic future fixture date. Notification authorization and actual delivery were not triggered.
- Hardening regression: the complete scheme passes 20/20 on the dedicated iPhone 17 Pro simulator (19/19 isolated tests plus 1/1 UI test). New coverage rasterizes a PDF generated under a dark trait and asserts a white corner plus dark ink, verifies all four spreadsheet-formula prefixes are neutralized, verifies CSV settlement overflow and PDF total overflow fail with `StatementGenerationError.arithmeticOverflow`, preserves the private receipt file when tombstone persistence fails, and locks the tab-bar clearance invariant. The UI target scrolls the final Books row and Statements help card until each is hittable and entirely above the native tab bar, prepares a PDF in dark mode, and retains screenshot evidence. The actual 26,050-byte dark-mode-generated PDF was rendered to PNG for visual inspection.
- Local Backup & Recovery: Swift package compatibility/merge coverage passes 7/7. The complete iOS scheme passes 26/26 on the dedicated iPhone 17 Pro simulator (22/22 isolated tests plus 4/4 UI tests). New coverage verifies a full Android-compatible version-8 round trip, receipt bytes and every entity type, deterministic preview counts, local-wins ties, separated USD/EUR records, corrupt and unsupported inputs with no financial mutation, pre-restore snapshot creation, and exact recovery rollback. English dark and Arabic RTL UI tests verify both Files actions and move the privacy footer fully above the Liquid Glass tab bar. A fourth UI test opens both native Files sheets and terminates the app without saving or selecting a document. Unsigned Debug and Release generic Simulator builds pass.
- Physical-device acceptance: the same complete 26/26 scheme passes on a wired iPhone 16 Pro running iOS 26.6 using the existing development team/profile. The signed Debug build installed without replacing a prior Pinbook installation, and the retained English dark, Arabic RTL, and native import-picker screenshots were visually inspected. The native export and import sheets both opened; automation terminated Pinbook without pressing Save or selecting a file. Test services used isolated in-memory stores and temporary receipt directories and did not use production financial data. A completed user-driven Files export/import round trip remains separate because no external provider location was mutated.
- UX, localization, currency, and widgets milestone: the final complete Simulator scheme covers clean-versus-returning onboarding policy, full English/Arabic/Simplified Chinese catalog presence, a four-page Chinese onboarding traversal, all five skins in both appearances with programmatic contrast assertions, the corrected Night Ink/Light picker, all 159 `Locale.commonISOCurrencyCodes` with nonempty deterministic symbols/names, searchable currency UI, and both privacy-safe widget deep-link routes. The app scheme builds and embeds the two-widget extension unsigned without an App Group or cloud capability.

## Release boundary

Simulator builds and static inspection alone do not prove physical-device behavior, Apple signing, Home Screen widget installation, Google OAuth, Drive transfer, iCloud, successful Files-provider transfer, real notification delivery, successful transfer through a share extension, or App Store review readiness. Earlier signed development acceptance remains valid only for its exact prior build. The new onboarding/currency/theme/widget milestone is Simulator-validated and makes no new physical-device claim. Each implemented integration needs its own end-to-end acceptance before any release claim.
