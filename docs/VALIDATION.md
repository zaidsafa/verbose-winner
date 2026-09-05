# Validation plan

## 2026-09-05 active personal Google Drive sync release candidate

- Added the production runtime from explicit AppAuth consent through protected
  refresh-token custody, memory-only access refresh, strict Drive `appDataFolder`
  transport, bounded verified backup-v8 inventory/download, deterministic merge,
  pre-apply recovery snapshot and immutable idempotent append. A single 401 clears
  the memory token and retries through the protected refresh owner; all other
  failures stop without deleting remote snapshots.
- Added user-facing Backup & Recovery states for Connect, Sync now, optional sync
  when Pinbook opens, Disconnect and fenced cleanup. The confirmation explicitly
  says Pinbook cannot read other Drive files. All 29 provider strings contain the
  15 supported non-English localizations. Manual Files copy no longer falsely says
  that no cloud provider can be connected.
- Focused Swift access+merge suites: **5/5 PASS**. The complete SwiftPM runner
  compiled but later produced no progress and was interrupted; it is not counted
  as acceptance evidence.
- Signed iOS 26.5 Simulator personal-Drive acceptance: **47/47 PASS**, zero
  failures/skips:
  `/private/tmp/Pinbook-Personal-Drive-Sync-Auto-Sim-20260905.xcresult`.
- Separate signed QA app on physical **iPhone 16 Pro, iOS 26.6.1** ran the same
  complete set: **47/47 PASS**, zero failures/skips, including real device-only
  Keychain coverage:
  `/private/tmp/Pinbook-QA-Physical-Personal-Drive-Sync-Auto-20260905.xcresult`.
  The normal QA app was relaunched afterward.
- Scope-confirmation XCUITest: **1/1 PASS** on Simulator, exact evidence:
  `/private/tmp/Pinbook-Drive-Sync-UI-Sim-Retry-20260905.xcresult`. The initial
  attempt asserted the wrong shorter status label and is not acceptance evidence.
- Complete Simulator UI regression: **30/30 PASS**, zero failures/skips, covering
  onboarding, localization/RTL, themes, currencies, widgets, native Files and the
  new Drive scope flow:
  `/private/tmp/Pinbook-Full-UI-Sync-20260905.xcresult`.
- Separate Simplified Chinese Drive scope UI: **1/1 PASS**, including localized
  navigation, disconnected state, Connect action and private-folder explanation:
  `/private/tmp/Pinbook-Drive-Sync-Chinese-UI-Sim-20260905.xcresult`.
- A four-case affected physical UI attempt compiled and signed but ran **0 tests**
  because Apple timed out while enabling device automation mode. It is a runner
  failure, not product evidence, and must not be counted:
  `/private/tmp/Pinbook-QA-Physical-Drive-UI-20260905.xcresult`.
- Complete signed Simulator app-host regression: **404 PASS + 4 expected
  physical-only SKIPS**, 408 total, zero failures:
  `/private/tmp/Pinbook-Full-AppHost-Sync-20260905.xcresult`.
- Exact unsigned production Release **BUILD SUCCEEDED** at
  `/private/tmp/pinbook-personal-drive-active-release-derived`; bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`, production OAuth client,
  and the updated privacy manifest all compile into the app.
- Live QA browser handoff: **1/1 PASS**. The isolated Simulator QA client opened
  Google's loaded `accounts.google.com` sign-in page with the exact wording
  **Sign in with Google** and **to continue to Pinbook**:
  `/private/tmp/Pinbook-Live-Drive-Loaded-Inspect-Retry-20260905.xcresult`.
  This proves the configured QA OAuth client reaches Google's real authorization
  UI and presents the expected app identity. The temporary network inspection
  test was removed afterward. No email, password, token or Drive object was used.
- The owner then completed Google sign-in and reported **backed up to Google
  Drive** from the separate physical `Pinbook QA` app. This is owner-observed live
  consent/token/upload evidence against the QA client, not an independently read
  Drive object or exact-byte download/revocation result. The working TestFlight app
  and its records were not used.
- A separate Pinbook support/privacy site is complete as a validated static export.
  It contains an app home page, privacy policy and support page, reuses the exact
  current app icon, has responsive light/dark presentation, and passes lint and
  production build. No public URL exists yet: the normal Sites connector is
  returning a transport failure, and no fallback GitHub Pages publication has
  been authorized. This is prepared local publication evidence only, not the
  owned HTTPS release gate.
- Live App Store Connect read-only audit at **2026-09-05 10:09 CST** confirmed
  build `0.1.0 (3)` remains **Testing** in both existing `Zaid testing` groups.
  The page showed three installs, one seven-day session and no reported crashes
  or feedback for build 3. The owner's authorized feedback email, review phone
  and review email were then saved and verified after reload. Build 3's accurate
  no-Drive description/review notes were deliberately left unchanged.
- The same audit confirmed App Privacy is still at **Get Started** with no privacy
  policy URL. The App Store 1.0 page still has no uploaded screenshots,
  description, keywords, support URL, build or copyright, and its separate App
  Review form has Sign-In required selected. These remain observed open gates.
  The factual subtitle **Private expense notebook** plus primary **Finance** and
  secondary **Productivity** categories were saved and verified after reload;
  no privacy answer, build assignment or review submission was changed.
- Prepared six visually inspected English App Store screenshots from exact app and
  installed-widget evidence. Every PNG is **1242 x 2688**, with SHA-256 recorded
  beside the assets under `release/app-store/screenshots`. The set covers expenses,
  summary, world currencies, the current Drive scope disclosure, reminders and both
  widgets. The stale pre-Drive backup screen was excluded. Nothing was uploaded.
- Apple App Privacy guidance was re-audited for ongoing off-device sync. The
  manifest and submission guide now disclose Other Financial Info, Other User
  Content and Photos or Videos for App Functionality, linked to the user's Drive
  account, with no tracking. The policy describes private-folder scope, Keychain,
  automatic sync and disconnect retention.
- Independent remote-object download/revocation acceptance and the
  Android-to-iOS-to-Android synthetic-data round trip are still open gates. The
  connected Samsung is reserved for that later compatible-build run and was not
  used. No source push, archive, TestFlight upload or App Store Connect mutation
  occurred.

## 2026-09-05 personal Drive OAuth client allocation and installed configuration

- Created separate Google iOS OAuth clients in the dedicated `pinbook-507110`
  project for production `com.zaidsafa.pinbook.ios` and QA
  `com.zaidsafa.pinbook.ios.qa`, both bound to Apple team `F98S3VN5NL`. The Drive
  API is enabled. These native clients contain no client secret.
- Added build-setting-bound client IDs and reversed-client callback schemes to the
  installed app configuration. Production and QA compile to their own exact client
  and callback; `PersonalGoogleDriveConfiguration.installed()` rejects missing or
  mismatched installed values.
- Signed production Simulator complete personal-Drive suites **27/27 PASS**, zero
  failures/skips: `/private/tmp/Pinbook-Personal-Drive-Config-Sim-20260905.xcresult`.
- Separate signed QA app on physical **iPhone 16 Pro, iOS 26.6.1** complete
  personal-Drive suites **27/27 PASS**, zero failures/skips, including real
  Data Protection Keychain coverage:
  `/private/tmp/Pinbook-QA-Physical-Personal-Drive-Config-20260905.xcresult`.
- Google Auth Platform is external/testing and explicitly includes
  `zaid.safa@gmail.com` as its one test user. The console still reports incomplete
  branding, so live consent is not accepted evidence yet. No browser authorization,
  token, Drive object, Android mutation, source push, archive or TestFlight action
  occurred.

## 2026-09-05 inactive personal Drive connection custody coordinator

- Added the authorization-to-Keychain coordinator. Before reporting success, a
  newly issued refresh token is atomically added as `revocationPending`, then the
  exact generation is promoted to `active`. Existing active or fenced records
  stop before provider contact, and a second in-process connection fails busy.
- Cancellation after provider issuance performs revocation outside the cancelled
  caller task and deletes only the exact fenced generation. Activation failure
  follows the same cleanup path. If revocation or deletion is not authoritative,
  the fenced credential remains unusable and the result is `cleanupRequired`;
  success is never reported from ambiguous custody.
- Focused Swift connection+custody **7/7 PASS** using isolated scratch path
  `/private/tmp/pinbook-spm-connection-20260905-a`. Two earlier runs executed the
  tests but returned nonzero after the workspace `.build/build.db` reported disk
  I/O errors; they are not acceptance evidence.
- Complete Swift core **366/366 PASS**, 35 suites, 14.749s, using that same
  isolated scratch path.
- Signed iOS 26.5 Simulator complete personal-Drive suites **26/26 PASS**, zero
  failures/skips, including real Keychain staged activation/reopen/delete:
  `/private/tmp/Pinbook-Personal-Drive-Connection-Sim-20260905.xcresult`.
- Separate signed QA app on physical **iPhone 16 Pro, iOS 26.6.1** complete
  personal-Drive suites **26/26 PASS**, zero failures/skips, including the real
  Data Protection Keychain:
  `/private/tmp/Pinbook-QA-Physical-Personal-Drive-Connection-20260905.xcresult`.
  QA returned to a successful normal launch afterward.
- Exact-current ordinary unsigned production Release **BUILD SUCCEEDED** at
  `/private/tmp/pinbook-personal-drive-connection-release-derived`, with unchanged
  bundle `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.
- No allocated Google client, production callback route, Google account/request,
  Android app operation, source push, archive or TestFlight action occurred.

## 2026-09-05 inactive personal Drive browser and callback owner

- Added a one-flight AppAuth browser/callback owner for explicit personal Drive
  consent. Live construction requires the allocated reversed-client URL scheme
  to be registered and a usable foreground presenter before any browser starts.
  AppAuth supplies a fresh request, state and S256 verifier; only the exact
  bounded callback is routed to that pending flow and consumed once.
- The system driver uses an ephemeral browser session, exchanges only the code
  bound to the original request/verifier, cancels on background or caller
  cancellation, and attempts remote revocation if cancellation arrives after a
  refresh token was issued. A monotonic ten-minute task bounds browser ownership;
  wall-clock rollback cannot extend it. Durable credential save and rollback are
  intentionally left to the next connection coordinator.
- Clean complete Swift core **362/362 PASS**, 34 suites, 16.209s. The UIKit-only
  authorizer suite is excluded by SwiftPM, while the actual AppAuth callback test
  is included. An initial sandbox attempt failed before compilation because the
  compiler module cache was inaccessible and is not acceptance evidence.
- Exact-current signed iOS 26.5 Simulator OAuth+authorizer suites **11/11 PASS**,
  zero failures/skips:
  `/private/tmp/Pinbook-Personal-Drive-Authorizer-Sim5-20260905.xcresult`.
  A preceding sandboxed attempt could not access CoreSimulator or GitHub and is
  not acceptance evidence.
- Separate signed QA app on physical **iPhone 16 Pro, iOS 26.6.1** ran OAuth,
  authorizer, real Keychain custody and synthetic revocation suites: **21/21
  PASS**, zero failures/skips:
  `/private/tmp/Pinbook-QA-Physical-Personal-Drive-Authorizer-Final-20260905.xcresult`.
  QA returned to a successful normal launch afterward.
- Exact-current ordinary unsigned production Release **BUILD SUCCEEDED** at
  `/private/tmp/pinbook-personal-drive-authorizer-release-derived`, with unchanged
  bundle `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.
- Both physical devices were detected: iPhone 16 Pro and Samsung SM-S9180. The
  Android app was not opened or changed because no allocated Google client,
  connection coordinator, production callback wiring, live remote bytes or sync
  UI exists yet. Synthetic tests opened no real browser and contacted no Google
  service. No source push, archive or TestFlight action occurred.

## 2026-09-05 inactive personal Drive credential custody and revocation

- Added device-only Data Protection Keychain custody for the personal Drive
  refresh token. Access tokens remain memory-only. Stored records contain a
  hashed client binding, generation, connection time, optional bounded refresh
  expiry and phase; diagnostics and reflection redact credentials.
- Initial save requires consent. Refresh replacement and deletion use exact
  Keychain generations. Disconnect persists a `revocationPending` fence before
  network work, preventing refresh from rotating credentials during revocation.
  Failure/cancellation keeps the fenced token for an explicit retry; only an
  authoritative empty 200 or exact `invalid_token` result permits local deletion.
- The revocation request is one-use, form-encoded, bounded, single-flight and sent
  only to `https://oauth2.googleapis.com/revoke`. No client secret, cookie,
  redirect, automatic retry or credential diagnostic is permitted.
- Focused Swift personal-Drive boundary **15/15 PASS**. Clean complete Swift core
  **361/361 PASS**, 34 suites, 16.400s. Two preceding complete runs executed all
  361 tests successfully but returned nonzero because the generated SwiftPM build
  database reported disk I/O errors; `swift package clean` removed only generated
  artifacts, and the clean rebuild above is the acceptance result.
- Signed iOS 26.5 Simulator focused **16/16 PASS**, including a real Keychain
  reopen/delete cycle:
  `/private/tmp/Pinbook-Personal-Drive-Revoke-Sim-20260905.xcresult`.
- Separate signed QA app on physical **iPhone 16 Pro, iOS 26.6.1** focused
  **16/16 PASS**, zero failures/skips, including real Keychain custody:
  `/private/tmp/Pinbook-QA-Physical-Personal-Drive-Revoke-20260905.xcresult`.
  The QA app returned to a successful normal launch afterward.
- Exact-current ordinary unsigned production Release **BUILD SUCCEEDED**, bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.
- No allocated Google client/project, browser/callback controller, real token,
  provider account, Drive request, production UI, Android-device operation,
  source push or TestFlight action occurred.

## 2026-09-05 inactive personal Google Drive OAuth/token boundary

- Added a separate personal-Drive OAuth configuration and AppAuth request. It
  requires an allocated iOS client ID plus its registered reversed-client callback,
  uses fresh AppAuth state/nonce/S256 PKCE, requests only `drive.appdata`, and asks
  for explicit offline consent. It is isolated from team Google sign-in.
- Added a bounded single-flight Google token client for authorization-code exchange
  and refresh. Native clients send no client secret; form bodies use one-use streams.
  Concurrent dispatches fail busy. Strict responses require the exact Drive scope,
  Bearer type and bounded access/optional refresh expiry. Access/refresh/grant
  diagnostics are redacted. This layer does not persist tokens.
- Focused Swift **6/6 PASS**. Complete Swift core **352/352 PASS**, 32 suites.
  No request reached Google.
- Signed iOS 26.5 Simulator app-host focused **6/6 PASS**, 1 suite, 0 failures:
  `/private/tmp/Pinbook-Personal-Drive-OAuth-Hardening-Sim2-20260905.xcresult`.
  The first attempt omitted the explicit iPhone Simulator SDK and selected a
  macOS-style test host; it failed before build/test and is not acceptance evidence.
- A later parallel hardening run returned before its result bundle finalized; its
  incomplete bundle is also not acceptance evidence. The independent Sim2 rerun
  above is the exact-current result.
- Separate signed QA app on physical **iPhone 16 Pro, iOS 26.6.1** focused
  **6/6 PASS**, 1 suite, 0 failures:
  `/private/tmp/Pinbook-QA-Physical-Personal-Drive-OAuth-Hardening-20260905.xcresult`.
  The QA app returned to a successful normal launch afterward.
- Exact-current ordinary unsigned production Release **BUILD SUCCEEDED**, unchanged bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.
- No allocated Google client ID was invented, no URL scheme/production UI/token
  custody/revocation/scheduler/real Drive call was enabled, and no Android-device,
  archive, source push or TestFlight action occurred.

## 2026-09-05 inactive Google Drive v3 backup transport

- Corrected the upload reservation boundary so `BackupTransport` supplies the
  idempotent operation identity. Google Drive therefore pre-generates an
  `appDataFolder` file ID before the protected owner persists it; a local UUID can
  no longer silently stand in for a provider-reserved create identity.
- Added a disconnected `GoogleDriveBackupTransport` using only the documented
  `drive.appdata` scope. It strictly constructs `generateIds`, page-token list,
  bounded `alt=media` download and multipart create requests. Private
  `appProperties` bind schema, ID, creation time, bytes and SHA-256. A retrying
  create's 409 is successful only after exact metadata and downloaded bytes both
  verify. Bearer diagnostics are redacted and the bounded ephemeral HTTP exchange
  refuses redirects, cookies and compressed responses.
- Focused synthetic Drive wire suite **5/5 PASS**. Clean complete Swift core
  **346/346 PASS**, 31 suites, 14.212s. No request reached Google.
- Signed iOS 26.5 Simulator app-host **372 PASS + 4 expected physical-only
  SKIPS**, 376 total, 0 failures:
  `/private/tmp/Pinbook-Drive-Adapter-Exact-AppHost-20260905.xcresult`.
- Separate signed QA app on physical **iPhone 16 Pro, iOS 26.6.1** ran the owner,
  transport and Drive synthetic suites: **15/15 PASS**, 2 suites, 0 skips or
  failures, including real Keychain reopen/clear:
  `/private/tmp/Pinbook-QA-Physical-Drive-Adapter-Exact-20260905.xcresult`. QA returned
  to normal launch afterward; Android was not touched.
- Ordinary unsigned production Release **BUILD SUCCEEDED**, bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.
- No personal OAuth/token custody, provider account, live Drive bytes, iCloud,
  scheduler, automatic merge, production UI, archive/upload, source push or
  TestFlight action occurred. The existing published build remains unchanged.

## 2026-09-05 durable personal-cloud upload ownership (inactive)

- Added `PersonalCloudUploadOwner` above the immutable transport guard. It
  persists operation identity, creation time, exact byte count and SHA-256 before
  awaiting a provider, then clears only after an exact verified receipt. A retry
  after an ambiguous failure or process reopen must use the same identity and
  exact content authority; changed content, concurrent dispatch and corrupted
  stored authority fail closed.
- The production store uses the Data Protection Keychain with
  `AfterFirstUnlockThisDeviceOnly`, no synchronization and content-hash CAS. It
  stores no backup bytes, account, filename or credential.
- Focused Swift package **9/9 PASS**. Complete Swift core **341/341 PASS**, 30
  suites, 17.428s. The initial sandbox attempt was blocked before compilation by
  module-cache permissions and was not counted.
- Signed iOS 26.5 Simulator focused **10/10 PASS**, including actual Keychain
  reopen/clear. The preceding unsigned-host run failed only that real-Keychain
  case with `-34018` because disabling signing removes the entitlement; it was not
  counted as product evidence.
- Signed iOS 26.5 Simulator app-host **367 PASS + 4 expected physical-only
  SKIPS**, 371 total, 0 failures:
  `/private/tmp/Pinbook-Cloud-Upload-AppHost-20260905.xcresult`.
- Separate signed QA app on physical **iPhone 16 Pro, iOS 26.6.1** focused
  **10/10 PASS**, 0 skips or failures, including real Keychain reopen/clear:
  `/private/tmp/Pinbook-QA-Physical-Cloud-Upload-20260905.xcresult`. The QA app
  was returned to normal launch afterward.
- Ordinary unsigned production Release **BUILD SUCCEEDED**, bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.
- No Android-device operation, Drive/iCloud adapter, OAuth token, remote file,
  scheduler, automatic merge, production UI, archive/upload, source push or
  TestFlight action occurred. See `PERSONAL_CLOUD_SYNC_V1.md`.

## 2026-09-05 immutable personal-cloud transport guard (inactive)

- Replaced the unused blind `download/upload` port with a provider-neutral
  immutable contract: paginated inventory, exact bounded download and append-only
  upload. No update/delete method exists. Metadata is opaque and diagnostic output
  is redacted.
- The guard follows all cursors, rejects cursor loops, duplicate object/operation
  IDs and inventory overflow, requests no more than the advertised exact byte
  count, verifies SHA-256, and requires the append receipt to match the persisted
  operation ID/time/bytes/digest.
- Focused **5/5 PASS**, 1 suite, 0.001s:
  `/private/tmp/pinbook-cloud-transport-focused-20260905.log`. The first focused
  command was blocked before compilation by sandbox denial of Swift's module cache;
  its misleading piped shell exit was not counted.
- Complete Swift core **337/337 PASS**, 30 suites, 15.207s:
  `/private/tmp/pinbook-cloud-transport-full-core-20260905.log`.
- Signed iOS 26.5 Simulator app-host **362 PASS + 4 expected physical-only
  SKIPS**, 366 total, 0 failures, 31 suites, 8.071s:
  `/private/tmp/Pinbook-Cloud-Transport-AppHost-20260905.xcresult` and
  `/private/tmp/pinbook-cloud-transport-apphost-20260905.log`.
- Ordinary unsigned production Release **BUILD SUCCEEDED**, bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`:
  `/private/tmp/pinbook-cloud-transport-release-20260905.log`.
- No Drive/iCloud adapter, OAuth client/token, entitlement, schedule, remote file,
  automatic merge, production UI, archive/upload or TestFlight action occurred.
  See `PERSONAL_CLOUD_SYNC_V1.md`.

## 2026-09-05 canonical ACCEPT/ACK/CANCEL journal event parity (inactive)

- Mirrored the exact accepted-delivery journal metadata frozen in committed
  Android/server checkpoint `2725a49`: deterministic ACCEPT event/object IDs,
  delivery/team/sender authority, revision, audience/intent/JWE hashes and size,
  ordered frozen targets, all lifecycle timestamps and fixed 30-day expiry.
  ACK/CANCEL now freeze target user/device/enrollment/agreement-key thumbprint;
  CANCEL remains distinct and limited to `MEMBERSHIP_REMOVED`.
- The accepted constructor requires exact canonical submit-intent bytes and derives
  their SHA-256. Independent Node canonicalization and Swift serialization match:
  1,079 bytes, SHA-256
  `253037999a2c6122c96de38e1123f7b3923202670e98c418575d34f9f23a4a7f`;
  embedded intent SHA-256
  `b39a539699af95520162e09fe08ee4044e66bf80de3968ee24f356e043561ddf`.
- Focused Swift journal-event **4/4 PASS**. Complete Swift core **332/332 PASS**,
  29 suites, 19.487s:
  `/private/tmp/pinbook-journal-event-full-core-20260905.log`.
- Correct signed iOS 26.5 Simulator app-host run **357 PASS + 4 expected physical-
  only SKIPS**, 361 total, 0 failures, 30 suites, 10.736s:
  `/private/tmp/Pinbook-Journal-Event-AppHost-3-20260905.xcresult` and
  `/private/tmp/pinbook-journal-event-apphost-3-20260905.log`. The first app-host
  attempt omitted `-sdk iphonesimulator`, failed before tests by selecting a macOS
  host path, and is not counted.
- The same exact source then passed the separate physical **iPhone 16 Pro,
  iOS 26.6.1** QA app-host: **361/361 PASS**, 30 suites, 9.106s, zero skips or
  failures. This closes the four Simulator hardware skips for this source:
  `/private/tmp/Pinbook-QA-Physical-Journal-Event-20260905.xcresult` and
  `/private/tmp/pinbook-qa-physical-journal-event-20260905.log`. The isolated QA
  app returned to a successful normal launch recorded at
  `/private/tmp/pinbook-qa-journal-event-normal-launch-20260905.json`.
- Ordinary unsigned production Release **BUILD SUCCEEDED**, bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`:
  `/private/tmp/pinbook-journal-event-release-20260905.log`.
- Later server checkpoint `12137d2` retains this event contract and adds inactive
  lease/recovery fencing. The connected Samsung was detected but deliberately
  untouched because no authenticated sync route exists. No iOS provider write,
  journal, network route, Android sync, archive-before-ACK, staging, archive/upload
  or TestFlight action occurred.
  See `TEAM_DELIVERY_JOURNAL_EVENT_IOS.md`.

## 2026-09-05 installed widgets and authoritative cross-route presentation

- The actual Pinbook entry in the iOS 26.5 Simulator widget gallery exposes four
  Home Screen choices: Quick Expense small/medium and Balance Overview small/
  medium. Both widget kinds were installed together. The bright multicolor glass
  pinwheel icon appears in the gallery.
- Installed Balance Overview opened Summary and installed Quick Expense opened
  New Expense. Testing the widgets in sequence found a real state bug: after New
  Expense was presented, a later Summary route changed the selected tab but left
  the expense sheet covering it. `PinbookDeepLinkPresentation` now makes every
  accepted deep link set tab, expense-editor and Quick Add state authoritatively.
- Complete signed Simulator app-host rerun on the corrected source: **353 passes,
  4 expected physical-only skips, 0 failures**, 357 total. The named
  `widgetDeepLinksRouteWithoutExposingFinancialData()` test passed. Result:
  `/private/tmp/Pinbook-Widget-Route-Full-AppHost-20260905.xcresult`.
- Manual cross-route retest opened `pinbook://expense/new`, then
  `pinbook://summary`; Summary was visible with no stale sheet. Evidence:
  `docs/evidence/pinbook-final-widgets-installed.png` SHA-256
  `a2596b515f7f6dba2b9281cfd310348d9dba891414dc4477bc29cfe15971d48c`,
  `docs/evidence/pinbook-final-widget-quick-expense-deeplink.png` SHA-256
  `3cee6f443f16ebcca1993c6e6439cb1962c6e497c5ebb23497142de3abb460eb`,
  and `docs/evidence/pinbook-final-widget-cross-route-summary.png` SHA-256
  `924ddb07ef25a83c6ab79af8b7fe717eb2fe93100d949ac1e7e5c773778c1cc7`.
- Ordinary unsigned generic-iPhone Release **BUILD SUCCEEDED** with production
  bundle `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`:
  `/private/tmp/pinbook-widget-route-release-20260905.log`.
  This does not claim physical Lock Screen/Always On behavior, live App Group
  balances, a new archive/upload, or App Store Connect acceptance.

## 2026-09-05 exact-current UI, localization and backend-profile regression

- Exact iOS source at local commit `910f3dc` passed the complete signed native UI
  suite on the dedicated iPhone 17 Pro, iOS 26.5 Simulator: **29/29 PASS**,
  **0 failures/skips**, 440.864s. The run covers introduction/language switching,
  Simplified and Traditional Chinese, Arabic/Urdu RTL, theme readability, the
  searchable currency catalog, local Files recovery, final-content/tab-bar
  clearance and the inactive invitation/device/membership consent workflows.
  Result: `/private/tmp/Pinbook-Final-UI-20260905.xcresult`.
- The exact compiled Debug app from that run passed localization verification:
  **336 keys x 15 translated locales plus English**, format tokens intact, and
  app/widget compiled strings exactly matching source. This is automated catalog
  and structural accessibility/UI evidence; it does not claim spoken VoiceOver,
  rotor, locked-device widgets or physical focus behavior.
- The exact-current signed Simulator app-host result contains **353 passes,
  4 expected physical-only skips, 0 failures** (357 total). The skips are the
  three real Secure Enclave cases and the physical file-protection case; the
  separate physical-iPhone result contains **357/357 passes, 0 skips/failures**.
- Committed backend checkpoint `926d2ae` added strict canonical General JWE
  validation without enabling delivery submit. The iOS JWE, payload and
  submit-intent fixtures remain byte-identical to the shared vectors (`cmp=0`),
  with SHA-256 `95d83009ccc53f6573edde6269d66ff6184fe3dbf518954edbcbcb0d5dc9e8a9`,
  `6b77c4c44048741fd4fd82ef0c8a244a6b949c3c00a82555c5f760d22bc353c7`
  and `02c4cdcbcea9e50e0e9066c5618245f321e6ec06a8854129858c44459a136b17`.
  A fresh temporary Swift build ran the exact JWE/payload/intent selection:
  **10/10 PASS**, 3 suites, 0.010s. The first two Swift invocations are not
  counted: one was sandbox-blocked at the module cache; the next hit the stale
  workspace `.build` database and selected zero tests. No source, app data,
  physical device, network route, TestFlight build or App Store state changed.

## 2026-09-05 canonical delivery submit intent parity (inactive)

- Implemented exact iOS parity with frozen Android/server checkpoint
  `a158bf8f1c83bb2813009d835d0b079999d25187`. The compact printable-ASCII intent
  binds canonical JWE byte length/SHA-256, stable delivery ID, complete-audience
  digest and membership revision. Decode compares independent expected authority
  fields and exact re-encoding. It is metadata only; no transport is activated.
- The shared fixture is byte-identical, SHA-256
  `02c4cdcbcea9e50e0e9066c5618245f321e6ec06a8854129858c44459a136b17`.
  Focused submit-intent **3/3 PASS**,1 suite,0.004s:
  `/private/tmp/pinbook-ios-submit-intent-focused-first-20260905.log`.
- Complete Swift core **328/328 PASS**,28 suites,15.268s:
  `/private/tmp/pinbook-ios-submit-intent-full-core-20260905.log`. Signed Simulator
  app-host **353 PASS + 4 expected physical-only SKIPS**,357 total,29 suites,
  8.208s,0 failures:
  `/private/tmp/Pinbook-Submit-Intent-Signed.xcresult` and
  `/private/tmp/pinbook-ios-submit-intent-signed-app-host-20260905.log`.
- Separate physical-iPhone QA build-for-testing **SUCCEEDED** and app-host
  **357/357 PASS**,29 suites,3.949s:
  `/private/tmp/pinbook-ios-device-qa-submit-build-20260905.log`,
  `/private/tmp/Pinbook-QA-Physical-Submit-Intent-20260905.xcresult` and
  `/private/tmp/pinbook-qa-physical-submit-intent-20260905.log`. QA returned to a
  successful normal launch:
  `/private/tmp/pinbook-qa-submit-intent-normal-launch-20260905.json`.
- Ordinary unsigned Release **BUILD SUCCEEDED** with production bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`:
  `/private/tmp/pinbook-ios-submit-intent-release-20260905.log`. The test fixture
  filename/vector digest is absent from the Release app. No live endpoint,
  Android device, upload, server acceptance, database write, ACK, release archive,
  TestFlight upload or real sync was used.

## 2026-09-05 canonical team payload and multi-recipient JWE parity (inactive)

- Implemented exact independent iOS parity with frozen Android/server checkpoint
  `b2a33120a1b96c117ebb6cac12a45e72db88c56f`: compact canonical note payload,
  expected team/delivery/authenticated-author binding, fixed zero attachments,
  A256GCM General JWE, per-recipient P-256 ECDH-ES+A256KW, complete-audience
  digest, canonical parsing and input snapshot/failure cleanup. JWE validity is
  explicitly not treated as sender authentication. No runtime route was activated.
- Payload and JWE fixtures are byte-identical to the shared checkpoint, SHA-256
  `6b77c4c44048741fd4fd82ef0c8a244a6b949c3c00a82555c5f760d22bc353c7`
  and `95d83009ccc53f6573edde6269d66ff6184fe3dbf518954edbcbcb0d5dc9e8a9`.
  Both recipients independently decrypt and decode the exact payload. Focused
  composed delivery **26/26 PASS**,3 suites,1.750s:
  `/private/tmp/pinbook-ios-delivery-composed-focused-final-20260905.log`.
- Complete Swift core **325/325 PASS**,27 suites,16.951s:
  `/private/tmp/pinbook-ios-jwe-payload-full-core-20260905.log`. Signed Simulator
  app-host **350 PASS + 4 expected physical-only SKIPS**,354 total,28 suites,
  9.327s,0 failures:
  `/private/tmp/Pinbook-JWE-Payload-Signed-Final.xcresult` and
  `/private/tmp/pinbook-ios-jwe-payload-signed-app-host-final-20260905.log`.
- Separate physical-iPhone QA build-for-testing **SUCCEEDED** and complete app-host
  **354/354 PASS**,28 suites,3.970s. The named physical test encrypts the canonical
  payload for two recipients and decrypts/decodes through the retained Secure
  Enclave agreement key:
  `/private/tmp/pinbook-ios-device-qa-jwe-build-20260905.log`,
  `/private/tmp/Pinbook-QA-Physical-JWE-Payload-20260905.xcresult` and
  `/private/tmp/pinbook-qa-physical-jwe-payload-20260905.log`. QA returned to a
  successful normal launch:
  `/private/tmp/pinbook-qa-jwe-payload-normal-launch-20260905.json`.
- Ordinary unsigned Release **BUILD SUCCEEDED** with production bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`:
  `/private/tmp/pinbook-ios-jwe-payload-release-20260905.log`. Shared test fixture
  filenames/private scalars are absent from the Release app artifact. No Android
  device, live endpoint, upload/fetch/ACK, archive-before-ACK, release archive,
  TestFlight upload or real cross-device sync was used.

## 2026-09-05 finalized-draft identity safeguard (inactive)

- A finalized draft ID can no longer be recreated while its immutable pending
  event remains. This prevents a later draft from aliasing the idempotent retry
  identity of already-finalized work. Outgoing public values also expose an empty
  reflection mirror so payload text is not surfaced by generic diagnostics.
- Focused outgoing-store **9/9 PASS**:
  `/private/tmp/pinbook-ios-outgoing-commit-focused-20260905.log`. Complete core
  **318/318 PASS**,25 suites,15.321s:
  `/private/tmp/pinbook-ios-outgoing-commit-full-core-20260905.log`.
- Signed Simulator app-host **343 PASS + 3 expected physical-only SKIPS**,346
  total,26 suites,8.981s,0 failures:
  `/private/tmp/Pinbook-Outbox-Commit-Signed.xcresult` and
  `/private/tmp/pinbook-ios-outbox-commit-signed-app-host-20260905.log`.
- Separate signed physical-iPhone QA **BUILD SUCCEEDED** and complete app-host
  **346/346 PASS**,26 suites,3.924s:
  `/private/tmp/pinbook-ios-device-qa-outbox-commit-build-20260905.log`,
  `/private/tmp/Pinbook-QA-Physical-Outbox-Commit-20260905.xcresult` and
  `/private/tmp/pinbook-qa-physical-outbox-commit-20260905.log`. QA then returned
  to a successful normal launch:
  `/private/tmp/pinbook-qa-outbox-commit-normal-launch-20260905.json`.
- Ordinary unsigned Release **BUILD SUCCEEDED** with bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`:
  `/private/tmp/pinbook-ios-outbox-release-final-20260905.log`. No live endpoint,
  Android test, sync, archive or TestFlight upload was performed.

## 2026-09-05 agreement private-key possession parity (inactive)

- Implemented exact iOS parity with the frozen Android/server checkpoint
  `fdfa0a883af409d0fd02a47aaeeaed15b66e1400`. The challenge sends the proposed
  public agreement JWK, strictly parses the one-use server P-256 JWK/thumbprint,
  derives ECDH plus `pinbook-agreement-confirm-v1` Concat KDF, and executes with
  the exact `pinbook-agreement-possession-v1` HMAC while retaining the separate
  registered-device signature. Missing/malformed/private/reflected server keys
  and wrong confirmation sizes fail closed. No runtime route was activated.
- The copied public fixture is byte-identical to Android/server, SHA-256
  `946a6bfda62b193c23a38a53e6a3f4293fdc725545e3deefd99c567c63c763c2`.
  Independent CryptoKit rebuild reproduces the public JWK thumbprints, ECDH
  secret, request bytes, KDF output, possession message and HMAC, and rejects a
  changed thumbprint. Focused agreement/custody/enrollment **13/13 PASS** plus
  focused HTTP route **1/1 PASS**:
  `/private/tmp/pinbook-ios-agreement-possession-focused-final-20260905.log` and
  `/private/tmp/pinbook-ios-agreement-possession-http-focused-final-20260905.log`.
- Clean complete Swift core **318/318 PASS**,25 suites,15.838s:
  `/private/tmp/pinbook-ios-agreement-possession-full-core-20260905.log`.
  Signed dedicated-Simulator app-host **343 PASS + 3 expected physical-only
  SKIPS**,346 total,26 suites,9.848s,0 failures:
  `/private/tmp/Pinbook-Agreement-Possession-Signed.xcresult` and
  `/private/tmp/pinbook-ios-agreement-possession-app-host-20260905.log`.
- The initial unsigned Simulator app-host run compiled and executed but failed
  exactly three real-Keychain checks because an unsigned test host has no
  Keychain entitlement. It is not counted as a pass:
  `/private/tmp/Pinbook-Outgoing-Local.xcresult` and
  `/private/tmp/pinbook-ios-outgoing-app-host-20260905.log`.
- Signed separate QA build-for-testing **SUCCEEDED**:
  `/private/tmp/pinbook-ios-device-qa-possession-build-20260905.log`. The first
  individual physical selector matched zero Swift Testing cases and is not
  counted: `/private/tmp/Pinbook-QA-Physical-Agreement-Possession-20260905.xcresult`.
  The corrected complete physical iPhone run explicitly passed the named Secure
  Enclave agreement/reopen/software-peer possession test, the shared vector, and
  all app-host tests: **346/346 PASS**,26 suites,3.962s, zero failures/skips:
  `/private/tmp/Pinbook-QA-Physical-Agreement-Possession-Full-20260905.xcresult`
  and `/private/tmp/pinbook-qa-physical-agreement-possession-full-20260905.log`.
  QA returned to a normal launch:
  `/private/tmp/pinbook-qa-post-possession-normal-launch-20260905.json`.
- Ordinary unsigned Release **BUILD SUCCEEDED** with production bundle defaults:
  `/private/tmp/pinbook-ios-agreement-possession-release-20260905.log`.
  No live server, Android device, real account, encrypted delivery, submit/fetch/
  ACK, TestFlight upload, release archive or production activation was used.

## 2026-09-05 durable outgoing drafts and distinct events (inactive)

- Added a dedicated, backup-excluded/protected local SQLite outbox with editable
  draft compare-and-swap and atomic explicit finalization into immutable note,
  correction, approval or changes-requested events. Exact embedded-NUL UTF-8 is
  preserved. Reading/saving never approves; stale edits/finalization cannot
  overwrite current work; event retry is exact-ID idempotent; replacement
  enrollments cannot adopt old queues. No event retirement exists without a
  future authenticated response. See `TEAM_OUTGOING_IOS.md`.
- Focused **9/9 PASS**:
  `/private/tmp/pinbook-ios-outgoing-focused-20260905.log`. An initial sandboxed
  run failed existing and new backup-exclusion metadata checks with SQLite code3;
  the same focused tests passed outside that file sandbox. This was an execution
  permission issue, not an app-code correction.
- This slice is included in the clean **318/318** core, signed Simulator
  **346/346**, physical QA **346/346**, and ordinary unsigned Release results in
  the newest safeguard section above. No normal UI, encrypted wire event, server
  revision, transmission, remote retry/reconciliation, Android transfer or live
  sync exists.

## 2026-09-05 signed agreement-key enrollment and strict audience (inactive)

Historical checkpoint; the possession gap described here is closed by the newer
inactive parity/evidence section above.

- Updated to corrected Android/server contract
  `0011c1d4f9719ab0137632ecd3485676c6a54cad`. Added the literal
  `device-agreements/challenge` and `/execute` routes, exact canonical agreement
  body, locally verified registered-device signature, exact response rebinding,
  one-flight current account/device/membership/agreement owner, and mandatory
  signing+agreement recipient credentials. Missing agreement credentials reject
  the entire audience and signing/agreement reuse rejects. No normal route,
  listener, deployment or delivery. See `TEAM_AGREEMENT_ENROLLMENT_IOS.md`.
- First focused HTTP run passed **41/42**; its only issue was the test attempting
  to decode the larger public agreement body with the deliberately 32-byte-only
  coordinate decoder. The test now performs canonical general base64url decoding;
  production behavior was unchanged:
  `/private/tmp/pinbook-ios-agreement-enrollment-http-focused-20260905.log`.
- The first owner compile exposed only Swift overload ambiguity between async and
  synchronous checkpoint helpers plus explicit closure-capture requirements.
  Renamed the synchronous helper and captured the sendable identity explicitly.
  The next run passed **43/43** but SwiftPM printed a local build-database I/O
  warning while reusing valid artifacts:
  `/private/tmp/pinbook-ios-agreement-enrollment-focused-20260905.log` and
  `/private/tmp/pinbook-ios-agreement-enrollment-focused-fixed-20260905.log`.
- A separate clean scratch build under `/private/tmp` freshly compiled and passed
  focused **43/43**,0.095s:
  `/private/tmp/pinbook-ios-agreement-enrollment-focused-clean-20260905.log`.
  Complete clean core **307/307 PASS**,14.782s:
  `/private/tmp/pinbook-ios-agreement-enrollment-full-core-20260905.log`.
- Unsigned generic-iOS app plus test targets **TEST BUILD SUCCEEDED**:
  `/private/tmp/pinbook-ios-agreement-enrollment-test-build-20260905.log`.
  Ordinary unsigned Release **BUILD SUCCEEDED**:
  `/private/tmp/pinbook-ios-agreement-enrollment-release-20260905.log`.
- This checkpoint is intentionally source-only and was not installed or run on
  either connected phone. The prior physical **330/330** applies to the preceding
  crypto/custody commit, not this newer source. Prior UI **29/29** remains source-
  applicable because UI did not change, but is not a run of this exact checkpoint.
- At this historical checkpoint signing authorization alone was not proof of
  agreement-private-key possession; the newer frozen ECDH confirmation now closes
  that source/vector/physical-iPhone gap. No live
  provider/TLS, encryption envelope, submit/fetch/ACK, two-device note sync,
  release archive, production activation or TestFlight readiness was established.

## 2026-09-05 standard delivery crypto and separate agreement custody (inactive)

- Added bounded RFC 7518 Concat KDF/SHA-256 and RFC 3394 A256 Key Wrap using
  CryptoKit, plus a separate Secure Enclave P-256 agreement identity scoped to the
  exact canonical origin/account/authority epoch/enrollment. The agreement key
  cannot sign and the signing key cannot enter this API. Keychain custody has
  no update/delete/replace/sync/fallback. See `TEAM_DELIVERY_CRYPTO_IOS.md` and
  `TEAM_AGREEMENT_KEY_CUSTODY_IOS.md`.
- The first test command was blocked before compile by sandbox denial of Swift
  compiler caches: `/private/tmp/pinbook-ios-delivery-crypto-focused-20260905.log`.
  With cache access, compile identified two missing `try` markers in the new
  independent-agreement test only; corrected without changing app behavior:
  `/private/tmp/pinbook-ios-delivery-crypto-focused-fixed-20260905.log`.
- Final standard vectors **4/4 PASS**,0.001s:
  `/private/tmp/pinbook-ios-delivery-crypto-focused-final-20260905.log`.
  Combined crypto/custody **9/9 PASS**,0.007s:
  `/private/tmp/pinbook-ios-agreement-focused-20260905.log`. Complete core
  **302/302 PASS**,20.014s:
  `/private/tmp/pinbook-ios-agreement-full-core-20260905.log`.
- Signed isolated QA build-for-testing PASS:
  `/private/tmp/pinbook-qa-agreement-build-20260905.log`. A first focused physical
  selector matched zero Swift Testing cases and is not counted:
  `/private/tmp/Pinbook-QA-Physical-Agreement-Key-20260905.xcresult`. The complete
  physical app-host run explicitly executed and passed the named Secure Enclave
  agreement/Keychain reopen/software-peer/A256 round trip and finished **330/330
  PASS**,3.842s, zero failures/skips:
  `/private/tmp/Pinbook-QA-Physical-Agreement-Full-20260905.xcresult` and
  `/private/tmp/pinbook-qa-physical-agreement-full-20260905.log`.
- A fresh ordinary Release compile exceeded the bounded tool window after source
  compilation began; a warm-cache rerun passed, and the final durable ordinary
  unsigned Release log reports **BUILD SUCCEEDED**:
  `/private/tmp/pinbook-ios-agreement-release-success-20260905.log`. QA returned
  to a normal launch:
  `/private/tmp/pinbook-qa-post-agreement-normal-launch-20260905.json`.
- Prior complete UI **29/29 PASS** remains applicable because there is no UI or
  runtime route. This does not validate an agreement-enrollment server route,
  envelope, note encryption, submit/fetch/ACK, Android/iPhone sync, release archive,
  production activation or TestFlight readiness.

## 2026-09-05 one-flight current team audience lookup (inactive)

- Added one explicit foreground owner for the exact reviewed account, registered
  device/enrollment and fresh current-team revision. It performs one typed
  challenge/sign/execute sequence; rechecks account, device, wall/monotonic and
  proof authority around every boundary; validates the bounded returned audience;
  and has no retry, cache, timer, poll, background work or runtime route. Device
  signing is a read-only exact-generation custody operation with the account check
  inside the transaction. See `TEAM_AUDIENCE_LOOKUP_IOS.md`.
- The first focused lookup run compiled and passed **4/5**; one expired-access test
  had constructed a ticket already expired at fixture creation. The fixture now
  creates a valid ticket and places the lookup exactly at expiry. A subsequent
  compile rejected a mutable captured test counter under strict concurrency; it
  was replaced by a lock-protected helper without changing app code. Final focused
  lookup plus custody **6/6 PASS**,0.027s:
  `/private/tmp/pinbook-ios-audience-lookup-focused-final-fixed-20260905.log`.
- Complete core **293/293 PASS**,17.324s:
  `/private/tmp/pinbook-ios-audience-lookup-full-core-20260905.log`.
  Signed isolated QA build-for-testing PASS:
  `/private/tmp/pinbook-qa-audience-lookup-build-20260905.log`.
- Physical iPhone audience **5/5 PASS**,0.017s; complete custody **16/16 PASS**,
  0.064s; complete app-host **320/320 PASS**,3.798s, zero failures/skips:
  `/private/tmp/Pinbook-QA-Physical-Audience-Lookup-20260905.xcresult`,
  `/private/tmp/Pinbook-QA-Physical-Audience-Custody-20260905.xcresult`, and
  `/private/tmp/Pinbook-QA-Physical-Audience-Lookup-Full-20260905.xcresult`.
- The first fresh-derived Release attempt could not resolve AppAuth because the
  sandbox had no network; the local-cache retry was initially denied compiler
  cache access. The same source then passed ordinary unsigned Release using the
  already-resolved package/cache. Logs:
  `/private/tmp/pinbook-ios-audience-lookup-release-20260905.log`,
  `/private/tmp/pinbook-ios-audience-lookup-release-fixed-20260905.log`, and
  `/private/tmp/pinbook-ios-audience-lookup-release-final-20260905.log` (interrupted
  warm-cache compile). Final ordinary unsigned Release **BUILD SUCCEEDED**:
  `/private/tmp/pinbook-ios-audience-lookup-release-success-20260905.log`. QA
  launched normally afterward:
  `/private/tmp/pinbook-qa-post-audience-lookup-normal-launch-20260905.json`.
- Prior complete UI **29/29 PASS** remains applicable because this checkpoint adds
  no UI/runtime path. All transports and identities are synthetic/intercepted.
  This is not live TLS/provider validation, encryption, submit/fetch/ACK, two-device
  note sync, release archive, production activation or TestFlight readiness.

## 2026-09-05 typed device-request challenge/execute transport (inactive)

- Added two literal authenticated routes to the existing bounded client. Challenge
  accepts only the exact nested `team-audience` binding; execute accepts only the
  prepared challenge, a locally verified raw64 signature, and canonical encoded
  membership-revision body. Response parsing binds team/revision, caps targets at
  nine, excludes the caller, requires unique account/device/enrollment IDs, and
  validates exact P-256 JWK plus matching RFC7638 thumbprint. No generic callback,
  live listener, signer/custody owner, delivery handler, provider, or activation.
- Initial focused **17/17 PASS**,0.072s. Self-review then required local signature
  verification before execute and added a wrong-raw64/no-dispatch case. Final
  focused **17/17 PASS**:
  `/private/tmp/pinbook-ios-device-request-http-focused-final-20260905.log`.
  Complete core **287/287 PASS**,14.639s:
  `/private/tmp/pinbook-ios-device-request-http-full-core-20260905.log`.
- Signed isolated QA build-for-testing and ordinary unsigned Release PASS:
  `/private/tmp/pinbook-qa-device-request-http-build-20260905.log` and
  `/private/tmp/pinbook-ios-device-request-http-release-20260905.log`.
- Physical iPhone intercepted-transport **17/17 PASS**,0.061s; complete app-host
  **314/314 PASS**,8.680s, zero failures/skips:
  `/private/tmp/Pinbook-QA-Physical-Device-Request-HTTP-20260905.xcresult`,
  `/private/tmp/Pinbook-QA-Physical-Device-Request-HTTP-Full-20260905.xcresult`, and
  `/private/tmp/pinbook-qa-physical-device-request-http-full-20260905.log`.
  QA launched normally afterward. Prior complete UI **29/29** remains applicable
  because this adds no UI/runtime route.
- Evidence is strict local/stubbed/on-device transport behavior, not deployed TLS,
  Secure Enclave request signing, current-session orchestration, recipient trust,
  Android/iPhone note sync, release archive, or TestFlight readiness.

## 2026-09-05 device-authorized request public wire (inactive)

- Added `TeamDeviceRequestWire`: strict local challenge/binding validation,
  1...65,536-byte body hash, one-minute/access deadline, and exact canonical
  `pinbook-device-request-v1` bytes. It contains no signer, custody mutation,
  transport, generic callback, provider, persistence, or runtime activation. See
  TEAM_DEVICE_REQUEST_IOS.md and corrected shared checkpoint
  `dbeba7df0d64a637ea89fa2614cbe0b4fbeae97b`.
- Local fixture is byte-for-byte identical to the shared public fixture. First
  compile failed only because three nested Swift Testing `#require` macros are not
  supported; split them. The next run exposed a noncanonical synthetic base64url
  replacement in one test; replaced it with the fixture's other canonical public
  credential. No production rule was relaxed. Logs:
  `/private/tmp/pinbook-ios-device-request-wire-focused-20260905.log` and
  `/private/tmp/pinbook-ios-device-request-wire-focused-fixed-20260905.log`.
- Final focused public-vector/bounds **3/3 PASS**,0.009s:
  `/private/tmp/pinbook-ios-device-request-wire-focused-final-20260905.log`.
  Complete core **284/284 PASS**,15.106s:
  `/private/tmp/pinbook-ios-device-request-wire-full-core-20260905.log`.
- Signed isolated QA build-for-testing PASS and ordinary unsigned Release PASS:
  `/private/tmp/pinbook-qa-device-request-wire-build-20260905.log` and
  `/private/tmp/pinbook-ios-device-request-wire-release-20260905.log`.
- Physical iPhone focused CryptoKit vector **3/3 PASS**,0.005s; complete app-host
  **311/311 PASS**,8.677s, zero failures/skips:
  `/private/tmp/Pinbook-QA-Physical-Device-Request-Wire-20260905.xcresult`,
  `/private/tmp/Pinbook-QA-Physical-Device-Request-Wire-Full-20260905.xcresult`, and
  `/private/tmp/pinbook-qa-physical-device-request-wire-full-20260905.log`.
  Normal QA launch succeeded afterward. The preceding complete UI **29/29 PASS**
  remains applicable because this checkpoint adds no UI/runtime path.
- This verifies public bytes and signature interoperability, not live Android/iOS
  sync, server deployment, device request signing, authenticated HTTP, delivery,
  production state, archive, or TestFlight readiness.

## 2026-09-05 retained invitation workflow and device-consent UI

- Added a native device-registration model/view and retained account → device →
  membership parent. No I/O starts on presentation. The three decisions remain
  separate; wait/retry-ready/uncertain registration cannot advance or replay, and
  every explicit attempt starts with unchecked consent. Close/background drains
  transitions and children; mismatched, late and cleanup-uncertain products fail
  closed. The real composition factory uses the exact retained connector, while
  the DEBUG presentation is public synthetic UI with no provider, Keychain,
  network, stored-record, or live-note access. See TEAM_INVITATION_WORKFLOW_IOS.md.
- First QA build correctly failed before testing because the initial new test-file
  project object identifier duplicated an existing Xcode object. Replaced it with
  a unique identifier, audited all 24-character object definitions for duplicates,
  then `xcodebuild -list` and `plutil -lint` passed. Failed/corrected logs:
  `/private/tmp/pinbook-qa-workflow-screen-build-20260905.log` and
  `/private/tmp/pinbook-ios-workflow-project-list-fixed-20260905.log`.
- Focused workflow model **9/9 PASS**:
  `/private/tmp/pinbook-ios-workflow-screen-focused-20260905.log`.
  Complete core **281/281 PASS**,14.735s:
  `/private/tmp/pinbook-ios-workflow-screen-full-core-20260905.log`.
- Thirteen new source messages across all15 translated locales plus English;
  localization validation **336 keys PASS**, with exact compiled app/widget parity.
- Corrected signed QA build-for-testing and ordinary unsigned Release both PASS:
  `/private/tmp/pinbook-qa-workflow-screen-fixed-build-20260905.log` and
  `/private/tmp/pinbook-ios-workflow-screen-release-20260905.log`.
- Physical iPhone app-host **308/308 PASS**,8.672s, plus the five new UI journeys
  **5/5 PASS**,106.359s, zero failures/skips:
  `/private/tmp/Pinbook-QA-Physical-Workflow-Screen-20260905.xcresult` and
  `/private/tmp/pinbook-qa-physical-workflow-screen-20260905.log`.
  Tests cover Chinese three-consent completion, Arabic existing account with
  separate device/membership consent, fresh consent after both wait and retry-ready,
  uncertain no-replay/no-advance, and whole-workflow background closure.
- Chinese dark-mode and Arabic RTL screenshots were exported and visually checked:
  semantic foregrounds are readable, RTL alignment is correct, machine identifiers
  remain LTR, and the action remains reachable by scroll. Files are under
  `/private/tmp/pinbook-workflow-attachments-20260905-2/`.
- Complete existing+new physical UI regression **29/29 PASS**,422.507s, zero
  failures/skips. It includes all theme contrast, introduction/language, currency,
  backup/recovery, invitation, membership, retry, and new workflow journeys:
  `/private/tmp/Pinbook-QA-Physical-Workflow-Screen-Full-20260905.xcresult` and
  `/private/tmp/pinbook-qa-physical-workflow-screen-full-20260905.log`.
  Normal QA launch without fixture arguments succeeded afterward:
  `/private/tmp/pinbook-qa-post-workflow-screen-normal-launch-20260905.json`.
  No production identifier, capability, version, archive, provider, shared service,
  normal route, app records, or TestFlight build changed.

## 2026-09-05 exact-account device registration and invitation connector

- Regression before fix **FAILED six assertions across two account replacements**:
  old retained owner incorrectly returned success, created/signed a key and sent
  requests after same-ID re-login or a different-account switch.
  `/private/tmp/pinbook-ios-registration-account-pin-before-20260905.log`.
- Registration initializer now requires the exact reviewed access ticket. Removed
  its scope-only entry and dispatch-time account substitution; current-generation
  checks run before the first custody prepare and continue around subsequent work.
  Initial focused17 run caught an invalid test refresh fixture (reused credentials)
  and correctly rejected it. Corrected fixture rotates tokens as required; no
  production refresh rule was relaxed.
  `/private/tmp/pinbook-ios-registration-account-pin-focused-20260905.log`.
  Subsequent focused registration/TLS **18/18 PASS**,0.387s:
  `/private/tmp/pinbook-ios-registration-account-pin-composition-20260905.log`.
- Added TeamInvitationDeviceFlow: exact one-use account receipt → private device
  step → explicit consent → confirmed registration → one-use membership bridge.
  Actual TLS composition now traverses these retained owners/bridges and preserves
  separate membership consent, uncertain acceptance and recovery/retry boundaries.
  Seven flow cases plus four registration cases cover stale accounts, fresh consent,
  mid-prepare old-scope preservation, wait/recovered-null, closure/caller cancellation,
  changed-account transfer and invitation expiry after durable device commit.
- Focused **24/24 PASS**,0.486s before the final post-commit expiry case:
  `/private/tmp/pinbook-ios-invitation-device-flow-focused-20260905.log`.
  Complete final **272/272 core PASS**,14.851s:
  `/private/tmp/pinbook-ios-invitation-device-flow-full-core-20260905.log`.
- Signed QA build-for-testing PASS:
  `/private/tmp/pinbook-qa-invitation-device-flow-build-20260905.log`.
  Unchanged323-key catalogs exactly match compiled QA app/widget resources.
  No new native device-registration screen or normal-navigation activation here;
  native host UI remains next. See TEAM_INVITATION_DEVICE_FLOW_IOS.md.
- Physical iPhone QA app-host **299/299 PASS**,8.459s, zero failures/skips:
  `/private/tmp/Pinbook-QA-Physical-Invitation-Device-Flow-20260905.xcresult`;
  `/private/tmp/pinbook-qa-physical-invitation-device-flow-20260905.log`.
  Includes the exact-account/connector cases with synthetic account/key/transport
  adapters on-device. This is not live registration or shared-note delivery.
  No UI tests rerun for this core-only change; prior full24 UI and rebuilt affected4
  are recorded in the account-screen checkpoint below.
- Ordinary unsigned Release PASS:
  `/private/tmp/pinbook-ios-invitation-device-flow-release-20260905.log`.
  Final QA/Release app/widget compiled catalogs match all323 source entries.
  Normal QA launch succeeded afterward:
  `/private/tmp/pinbook-qa-post-invitation-device-flow-normal-launch-20260905.json`.
  No source push, distribution archive, TestFlight upload, production identity/
  version/capability, real provider or shared Infrastructure activation.

## 2026-09-05 invitation account screen and one-use handoff

- New native preflight, observable model and real invitation-owner bridge. No
  normal-navigation activation, live provider/service, device enrollment or join.
  See TEAM_INVITATION_CONSENT_IOS.md for lifecycle/receipt boundaries.
- Initial focused compilation caught async assertions combined inside synchronous
  boolean autoclosures; split those test assertions without changing app behavior.
  Corrected focused **25/25 PASS**,0.015s:
  `/private/tmp/pinbook-ios-invitation-account-screen-focused-fixed-20260905.log`.
- Initial full core **260/260 PASS**,26.089s:
  `/private/tmp/pinbook-ios-invitation-account-screen-full-20260905.log`.
- Self-review found that the new delayed receipt handoff sampled expiry before a
  potentially slow protected-account read but not after it. Added one regression
  with access expiry, invitation expiry and clock rollback occurring between those
  checks. It correctly **FAILED all three cases before the fix**, not dismissed:
  `/private/tmp/pinbook-ios-invitation-handoff-time-regression-before-20260905.log`.
  Handoff now rechecks wall/monotonic time, invitation/access expiry and cancellation
  after that read. It still consumes the receipt on failure and preserves custody.
  Final full core **261/261 PASS**,22.442s:
  `/private/tmp/pinbook-ios-invitation-account-screen-final-core-20260905.log`.
  Final self-review also kept the bridge busy through each public operation's
  state commit, with another closed/cancelled check after the nested async return.
  Complete core **261/261 PASS**,28.078s on that source:
  `/private/tmp/pinbook-ios-invitation-account-screen-ownership-final-core-20260905.log`.
- Eleven new assistant-authored messages in all15 translated locales+English:
  **323 catalog entries**. Source validation and exact compiled QA/Release app
  and widget parity PASS; this is not human linguistic review.
- Initial signed QA build-for-testing and ordinary unsigned Release both PASS:
  `/private/tmp/pinbook-qa-invitation-account-screen-build-20260905.log`,
  `/private/tmp/pinbook-ios-invitation-account-screen-release-20260905.log`.
  Physical initial candidate **287 app +24 UI PASS**,311 total, no failures/skips.
  App8.536s, UI313.554s. Result:
  `/private/tmp/Pinbook-QA-Physical-Invitation-Account-20260905.xcresult`;
  log `/private/tmp/pinbook-qa-physical-invitation-account-20260905.log`.
  All four new invitation cases passed: Chinese unchecked consent, explicit shown
  account in Arabic, uncertainty without replay and background clearing.
- Actual Chinese and Arabic screenshots exported and visually inspected: readable
  identity/role cards, wrapping, Arabic RTL with LTR machine IDs, unchecked consent
  and neutral disabled label; enabled Arabic action has readable dark-on-mint text.
  `/private/tmp/pinbook-qa-invitation-account-chinese-20260905/F66F3649-EC32-4B86-B85B-6BE4291977F6.png`;
  `/private/tmp/pinbook-qa-invitation-account-arabic-20260905/2B016EF2-49D1-44F6-8609-C1FA0C59A06C.png`.
  Full24 UI preceded the post-Keychain/bridge-ownership core fix. No UI code or
  translation changed after that full run; final rebuilt affected tests follow.
- Final signed QA build PASS:
  `/private/tmp/pinbook-qa-invitation-account-screen-final-build-20260905.log`.
  Physical **288 app +4 affected UI PASS**,292 total, zero failures/skips. App
  8.623s/UI39.033s; post-protected-read expiry regression PASS on iPhone0.003s.
  `/private/tmp/Pinbook-QA-Physical-Invitation-Account-Final-20260905.xcresult`;
  `/private/tmp/pinbook-qa-physical-invitation-account-final-20260905.log`.
  Final unsigned ordinary Release PASS:
  `/private/tmp/pinbook-ios-invitation-account-screen-ownership-final-release-20260905.log`.
  Final compiled QA/Release app/widget catalogs exactly match323 source entries.
  QA launched normally afterward, without fixture arguments:
  `/private/tmp/pinbook-qa-post-invitation-account-normal-launch-20260905.json`.
  Launch receipt is not additional end-to-end UX acceptance. No source push,
  TestFlight upload, production identity/version change, live provider/enrollment
  or notes delivery. The next current-account/device-parent integration remains open.

## 2026-09-05 explicit retry screen and TLS-fixture readiness correction

- Five new screen cases and three real bridge/owner/store compositions; focused
  **42/42 PASS**,0.073s:
  `/private/tmp/pinbook-ios-retry-screen-focused-20260905.log`.
- First full run **FAILED**,244 tests/three issues:
  `/private/tmp/pinbook-ios-retry-screen-full-core-20260905.log`.
  Existing tlsTrustAndActualPostBody and503 one-transmission assertions failed;
  private diagnostics recorded URL error-1004 (cannot connect). New retry cases
  and composed membershipTLS cases passed. This was not dismissed as a green run.
- Found a concrete fixture startup race: Python write_text creates the `port` file
  before filling it, while Swift treated existence as readiness. Empty text forms
  `https://localhost:` with no port in Foundation, silently targeting the default
  HTTPS port. Fixture now writes `port.pending` then atomically renames it; Swift
  independently requires a canonical1...65535 port and verifies URL.port. New
  regression rejects empty/whitespace/overflow/noncanonical values. Production
  transport, trust policies, deadlines and one-transmission rules are unchanged.
- Complete **245/245 PASS** on three bounded runs:20.221s,17.294s,19.769s:
  `/private/tmp/pinbook-ios-retry-screen-atomic-port-core-20260905.log`,
  `/private/tmp/pinbook-ios-retry-screen-atomic-port-core-20260905-2.log`,
  `/private/tmp/pinbook-ios-retry-screen-atomic-port-core-20260905-3.log`.
  The race is eliminated by construction and is consistent with these connection
  failures. Historical failed runs did not record the parsed port, so this does
  not prove the cause of every older TLS failure. Retain that evidence and watch
  for recurrence in final validation; never relax trust/timeouts to force passes.
- QA signed build PASS. Initial physical run had **six membership UI PASS**, but
  one app catalog test failed its stale306 count in15 locales (actual312). Fixed
  exact count and added assertions for all six new retry translations.
  Initial result: `/private/tmp/Pinbook-QA-Physical-Retry-Screen-20260905.xcresult`;
  log: `/private/tmp/pinbook-qa-physical-retry-screen-20260905.log`.
  Source/compiled QA app/widget parity PASS312 keys×15 translations+English.
- Chinese retry screenshot inspected: warning and unchecked consent wrap cleanly;
  disabled prominent text was too dark on its neutral surface. Use semantic text
  for disabled native buttons, retaining contrasting accent labels when enabled.
  Final rebuilt physical **272 app +20 UI PASS**,292 total with zero failures/
  skips; UI273.596s. Exact result:
  `/private/tmp/Pinbook-QA-Physical-Retry-Final-20260905.xcresult`;
  log: `/private/tmp/pinbook-qa-physical-retry-final-20260905.log`.
  Corrected Chinese pending-consent screenshot inspected: warning/role/account
  and unchecked switch readable; disabled label now legible on its neutral surface.
  Ordinary unsigned Release PASS:
  `/private/tmp/pinbook-ios-retry-screen-release-20260905.log`.
  Source and compiled QA/Release app/widget catalogs exactly match312 entries.
- Android supplied a new public physical-Keystore fixture; copied bytes match
  SHA256 bebd7e86c612c42edf117a5076e27773e61b7806b69f94cffdfa4fd25b6cf603.
  Swift focused7/7 PASS; subsequent complete core **246/246 PASS**,18.268s:
  `/private/tmp/pinbook-ios-retry-android-vector-full-core-20260905.log`.
  No new runtime code change; a test-only rebuild adds native fixture verification.
  Physical iPhone Android-vector test now PASS0.001s; all273 app tests PASS8.533s,
  zero skips/failures. Result:
  `/private/tmp/Pinbook-QA-Physical-Android-Vector-20260905.xcresult`;
  log: `/private/tmp/pinbook-qa-physical-android-vector-20260905.log`.
  Full20 UI preceded that test-only rebuild. See TEAM_DEVICE_ENROLLMENT_WIRE_IOS.md
  for scope; no live enrollment/notes or attestation is inferred. QA launched
  normally afterward; receipt `/private/tmp/pinbook-qa-post-retry-normal-launch-20260905.json`.
- No normal team activation, real provider/shared service, production data/identity,
  source push or TestFlight update. See TEAM_MEMBERSHIP_RETRY_IOS.md.

## 2026-09-05 isolated physical iPhone QA

Separate development QA build, signature verification and installation PASS.
App-host **263/263 PASS**,0 skips/failures; membership UI **3/3 PASS**,33.103s.
Exact logs/results, identity isolation, ordinary Release verification and important
limitations are in DEVICE_QA_IOS.md. This supersedes historical compiled-only and
phone-offline statements below. Chinese screenshot inspection found faint
white-on-jade action text despite passing behavior tests; corrected via shared
native prominent styling. Remaining baseline UI **13/13 PASS**,182.692s.
Contrast candidate **263 app +17 UI PASS** (280 total, zero failures/skips), with
all10 palette screenshots inspected. Later currency-label and temporary hardware
test candidate **264 app +2 affected UI PASS** (266 total, zero failures/skips).
Actual Secure Enclave generate/reopen/sign/verify PASS; no private-material export,
Keychain/file/provider write, or lock/passcode/recovery acceptance inferred.
Latest currency/Chinese screenshots inspected; ordinary Release/signature/catalog
checks PASS. Full17 UI was the immediately preceding contrast candidate, not the
later currency-only UI change. Detailed exact paths are in DEVICE_QA_IOS.md.
No source push, TestFlight update, production provider or shared service change.

## 2026-09-05 explicit same-identity retry store and membership owner (inactive)

- Initial store test compilation **FAILED** on missing inner `try` in two require
  assertions and one throwing boolean assertion:
  `/private/tmp/pinbook-ios-explicit-retry-store-focused.log`.
  Corrected test expressions; store **17/17 PASS**,1.069s:
  `/private/tmp/pinbook-ios-explicit-retry-store-focused-fixed.log`.
- Five new store cases cover read-only exact original matching, fresh consent,
  unchanged identity/hash/PENDING, new CAS generation, wrong registration/phase/
  deadlines, uncertain writes, expiry during commit/reread, competing retry and
  cancellation. No raw token persistence or schema change.
- Existing owner compatibility **16/16 PASS**,0.039s:
  `/private/tmp/pinbook-ios-explicit-retry-owner-compile.log`.
  Nine new owner cases; focused **25/25 PASS**,0.075s:
  `/private/tmp/pinbook-ios-explicit-retry-owner-focused.log`.
  Includes accepted-link recovery after expiry without another accept, nil→NEW
  consent→one explicit accept, invalid binding, unknown status/marker writes,
  concurrent recovery/foreign status, sign-out after slow stages, wall/monotonic
  expiry/device replacement, canceled late status and lost explicit-retry response.
- Existing actualTLS membership composition now has tokenless-recovery AND explicit
  retry scenarios. The retry fixture returns uncertain first accept and eligible
  pending status, then success only after a new explicit Join. Assertions verify
  durable write counts, ONE pre-consent accept, identical original accept bodies,
  exact bearer and unchanged account/no saved code. Synthetic transport fixture,
  not deployed backend admission/locking/idempotency acceptance evidence.
- Full **236/236 PASS**,16.539s:
  `/private/tmp/pinbook-ios-explicit-retry-full-core.log`.
- Simulator build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-explicit-retry-test-build.log`.
  Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-explicit-retry-release.log`.
  No new UIKit/app-host/UI/physical runtime acceptance.
- Latest read-only devicectl check reports iPhone **available (paired)**. Owner
  explicitly approved separate Pinbook QA identity/profiles/install, preserving
  the working TestFlight app/data. Development signing/install is next, not done.
- No retry UI/host activation, provider, physical installation, shared service,
  source push or TestFlight change. Earlier intermittentTLS caveats remain open.

## 2026-09-04 read-only original-invitation acceptance lookup (inactive)

- Six new intercepted HTTP tests cover exact protected request and nullable schema,
  malformed envelopes, foreign membership, nested duplicate keys, unsafe revisions,
  actual4096/4097-byte bounds, HTTP failures never null, invalid origin/input/access,
  post-response expiry/clock rollback, shared auth slot and cancellation.
- Focused onboarding **14/14 PASS**,0.255s:
  `/private/tmp/pinbook-ios-acceptance-route-focused.log`.
- Actual local TLS test covers current membership, eligible-pending null,503 and
  dropped connection. Verifies ONE original-token request with exact fields/bearer,
  unchanged account bytes/writes and no saved invitation. The fixture is not a
  deployed membership service or proof of eligibility/locking semantics.
- Full **222/222 PASS**,18.796s:
  `/private/tmp/pinbook-ios-acceptance-route-core.log`.
- Simulator build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-acceptance-route-test-build.log`.
  Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-acceptance-route-release.log`.
  No fresh app-host/UI/device runtime. Both read-only device discovery tools
  report the physical iPhone unavailable/offline; no installation was attempted.
- No retry coordinator/consent activation is implied by transport. Existing PENDING
  must survive null/errors; a future explicit retry retains original exact identity
  and requires fresh consent/durable generation. Tokenless current remains separate.
- Previous intermittent localhostTLS failures are still unclosed. No trust/deadline
  relaxation, polling, provider/phone/shared resource, signing/version, push or upload.

## 2026-09-04 localized membership confirmation and recovery screen (inactive)

- Initial full core **214/214 PASS**,14.809s:
  `/private/tmp/pinbook-ios-membership-screen-core.log`. Added explicit routing and
  tests for reopened existing metadata; final **215/215 PASS**,14.981s:
  `/private/tmp/pinbook-ios-membership-screen-final-core.log`.
- Nine synthetic screen tests and one real bridge/owner/store composition verify
  unchecked consent, one join, tokenless recovery, existing-record reopening,
  foreign-result rejection, cancellation and immediate closed-state clearing.
- Initial Simulator test compilation **FAILED**:
  `/private/tmp/pinbook-ios-membership-screen-test-build.log`. The new view's PBX
  IDs collided with Assets.xcassets, so the view was absent from compilation.
  Assigned unique IDs to only that new view. Final build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-membership-screen-fixed-test-build.log`.
- Catalog source **306 keys ×15 translated locales + English** passes format
  checks; compiled Debug app and widget translations exactly match source.
  Twenty new keys cover both Chinese scripts and all other supported languages;
  these are assistant-authored drafts, not human linguistic review.
- Three new UI tests compile but have NOT run: Chinese consent/confirmation,
  uncertain join with Check rather than another Join, and background clearing.
  No new UIKit/app-host/physical/provider runtime is inferred from compilation.
- Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-membership-screen-release.log`.
- Compiled Release app AND widget translations also exactly match all306 source
  keys across15 translated locales+English. Xcode object IDs are unique after fix.
- A fresh shared-GUI coordination message was blocked by security review. The
  owner then declined permission: **No, keep the tasks separate**. No retry,
  bypass/indirect message or Simulator launch. Continue Pinbook-local work; no
  other task's idle status is treated as explicit shared-GUI permission.
- Earlier intermittent localhostTLS failures remain unresolved final-validation
  caveats. These green runs do not prove their cause or a fix.
- No normal navigation, account/financial data, signing/version, source push,
  infrastructure, physical device or TestFlight change. See TEAM_MEMBERSHIP_UI_IOS.md.
- Owner offered a connected iPhone; read-only device enumeration reported it
  unavailable. Unlock/reconnect/Trust requested. No installation or physical test
  was attempted, and no hardware acceptance gate is closed by enumeration.

## 2026-09-04 explicit membership owner and tokenless recovery (inactive)

- Existing invitation/store compatibility **23/23 PASS**,1.502s:
  `/private/tmp/pinbook-ios-membership-compile.log`.
- Initial new test compilation failed on two missing inner `try` expressions
  in Swift Testing macros: `/private/tmp/pinbook-ios-membership-focused.log`.
  Corrected assertions; initial twelve cases **12/12 PASS**,0.023s:
  `/private/tmp/pinbook-ios-membership-focused-fixed.log`. No production guard relaxed.
- Added close-waits-for-real-completion and foreign/regressed membership tests,
  plus actual private localhost TLS composition through storage/device drivers.
  Full **204/204 PASS**,14.366s:
  `/private/tmp/pinbook-ios-membership-full-core.log`.
- Parent handoff now rechecks cancellation/current account after child completion,
  without claiming committed metadata was rolled back. Final full core
  **204/204 PASS**,15.900s: `/private/tmp/pinbook-ios-membership-final-core.log`.
- Fourteen synthetic owner tests cover separate/read-only/single-use consent,
  current account/device replacement, wall/monotonic deadlines including access
  lifetime across operations, missing/foreign/denied registration, uncertain marker
  commits, sign-out after slow reads/writes, delayed cancellation and actual close
  ownership, tokenless expired-link recovery and foreign/regressed response refusal.
- Actual local TLS integration sets up synthetic registration and invitation, then
  captures lookup→lookup→ONE uncertain accept→lookup→current. It verifies exact
  bearer/body binding, no raw code in the recovery request or persisted metadata,
  pending→confirmed recovery and unchanged account. This uses synthetic identity,
  CryptoKit keys/Keychain APIs and a transport fixture, not deployed backend proof.
- Earlier intermittent TLS failures remain an OPEN final-validation caveat. Two
  full green runs here do not establish their cause or prove a fix. No trust,
  deadline, cancellation or no-replay policy was relaxed to obtain these results.
- Initial Simulator build-for-testing and unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-membership-test-build.log` and
  `/private/tmp/pinbook-ios-membership-release.log`. Compilation only, before the
  final first-read monotonic anchoring case; no app-host/UI/physical execution.
- Review found the first access deadline was sampled after its account-store read.
  Moved that anchor before the read and added a synthetic six-second read against
  five seconds of remaining access with a stalled wall clock. This must fail before
  device reads or HTTP, not extend access by the read duration. Fifteen owner cases
  now exist; final full regression/compilation evidence follows.
- Final exact source **205/205 PASS**,15.797s:
  `/private/tmp/pinbook-ios-membership-verified-core.log`, including the new slow-read
  expiry case and all actual local TLS cases. Earlier intermittent TLS caveats
  remain unclosed; no new intermittent failure was observed in this slice's full runs.
- Final Simulator build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-membership-verified-test-build.log`.
  Final unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-membership-verified-release.log`.
  These are compile gates, not fresh app-host/UI runtime, real provider/Keychain
  protection, signed distribution or TestFlight availability evidence.
- No normal navigation, live provider/custody activation, shared infrastructure,
  physical phone, source push, signing/version or TestFlight change.

## 2026-09-04 durable membership intent and recovery metadata (inactive)

- Invitation compatibility after initial join-store compilation **11/11 PASS**,
 0.014s: `/private/tmp/pinbook-ios-join-store-compile.log`.
- Initial nine join-store cases **9/9 PASS**,0.987s:
  `/private/tmp/pinbook-ios-join-store-focused.log`.
- Expanded full core **188 tests, 2 issues — FAILED**,22.079s:
  `/private/tmp/pinbook-ios-join-store-full-core.log`. The existing actual localhost
  cancellation test returned transport rather than CancellationError and did not
  observe exactly one request. The new eleven storage tests passed; their success
  does not turn the complete run green. Exact underlying transport cause was not
  captured in that run. No attribution to storage or concurrent compilation.
- Added bounded numeric DEBUG-localhost transport diagnostics and a required
  pre-cancel body-observed assertion. Isolated cancellation/deadline **1/1 PASS**,
  10.465s: `/private/tmp/pinbook-ios-join-tls-cancellation-diagnostic.log`.
- Added byte-capacity headroom and a twelfth storage test. Full **189 tests,
  1 issue — FAILED**,18.441s:
  `/private/tmp/pinbook-ios-join-store-full-diagnostic.log`. Invitation TLS preview
  returned previewUnavailable; diagnostic codes were not emitted before fixture
  teardown in that run, so its underlying cause remains unproven. All twelve
  join-store tests passed. Do not claim this is the same cause as the prior failure.
- Diagnostics now emit only bounded enum/numeric URL and Security errors from
  private DEBUG localhost fixtures. No URL, body, userInfo or credential logging;
  Release rejects diagnostic configuration. Trust/date/hostname validation,
  deadlines and one-use request/no-retry policy are unchanged. The stalled-body
  deadline test now also requires URL timeout -1001, not an arbitrary transport
  error. Invalid diagnostic-without-local-anchor configuration is covered.
- Full core with diagnostics **189/189 PASS**,17.349s:
  `/private/tmp/pinbook-ios-join-store-full-trust-diagnostic.log`. Only expected
  synthetic dropped-connection -1005 and timeout -1001 codes appeared. The earlier
  intermittent failures have NOT been diagnosed or fixed by this green run.
- Initial Simulator build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-join-store-test-build.log`. This predates final capacity/
  clock tightening and the diagnostic additions; final compile evidence follows.
- After same-scope time checks around new/recovered records, full core
  **189/189 PASS**,14.569s: `/private/tmp/pinbook-ios-join-store-final-core.log`.
  Simulator build-for-testing and unsigned iPhone Release PASS:
  `/private/tmp/pinbook-ios-join-store-final-test-build.log` and
  `/private/tmp/pinbook-ios-join-store-release.log`.
- Final load-time reserved-capacity validation included: full core **189/189 PASS**,
  16.171s: `/private/tmp/pinbook-ios-join-store-final-verified-core.log`.
  Twelve storage cases include rollback against a newer record in the SAME scope,
  and loading revalidates future growth headroom as well as the current byte count.
  Intermittent TLS caveats above remain open, not declared fixed by repeated passes.
- Final Simulator build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-join-store-verified-test-build.log`.
  Final unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-join-store-verified-release.log`.
  Build evidence only; no new app-host/UI run or signed distribution artifact.
- No actual Keychain protection, app-host/UI, physical device, provider or deployed
  service acceptance. TEAM_JOIN_RECOVERY_IOS.md describes remaining owner/consent/
  recovery integration. TestFlight, normal navigation and personal records/keys
  remain unchanged.

## 2026-09-04 invitation account consent and exact committed-account handoff (inactive)

- Existing native sign-in compatibility after the snapshot refactor: **7/7 PASS**,
  `/private/tmp/pinbook-ios-invitation-signin-compile.log`.
- Initial new test compilation found two actor-property reads inside a nonisolated
  `&&` assertion autoclosure. Split assertions and corrected the synthetic challenge
  expiry to the fixture's current clock; no production policy was weakened.
- Eleven invitation cases **11/11 PASS**,0.008s:
  `/private/tmp/pinbook-ios-invitation-consent-tests.log`.
- Invitation plus expanded native-owner race cases **20/20 PASS**,0.035s:
  `/private/tmp/pinbook-ios-invitation-account-race-tests.log`. Exact after-commit
  replacement and expiry are injected through a synthetic Keychain forwarding
  adapter, with no production hook or real stored credential modification.
- Full core with composed actual private localhost TLS invitation flow:
  **177/177 PASS**,16.755s,14suites:
  `/private/tmp/pinbook-ios-invitation-full-core.log`. All three mandatory older TLS
  sign-in cases also passed. The earlier intermittent transport failure remains
  undiagnosed; this is not a claim that its underlying cause was fixed.
- Simulator build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-invitation-test-build.log`. Compilation only, not new
  app-host/UI execution, real provider issuance or physical Keychain proof.
- Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-invitation-release.log`. Not a signed release artifact.
- No normal navigation, automatic join, financial record/key change, shared
  infrastructure, source push, release signing/version or TestFlight change.
  TEAM_INVITATION_CONSENT_IOS.md records lifecycle obligations and open gates.

## 2026-09-04 current-session/monotonic device registration owner (inactive)

- Existing onboarding compatibility **8/8 PASS** after access-only ticket support:
  `/private/tmp/pinbook-ios-access-ticket-compatibility.log`; owner compilation plus
  the same suite **8/8 PASS**:
  `/private/tmp/pinbook-ios-registration-owner-compile.log`.
- Initial12new ticket/registration/recovery/lifecycle cases **12/12 PASS**,0.032s:
  `/private/tmp/pinbook-ios-registration-owner-focused.log`.
- Initial full core **162 tests, 1 failure**, NOT a pass:
  `/private/tmp/pinbook-ios-registration-owner-core.log`. Existing real-localhostTLS
  sign-in test returned fixed transportFailure; exact underlying cause was not
  captured. New account-bound registration/TLS tests passed in that run. No claim
  that the failure was caused by, or fixed by, registration changes.
- Isolated existingTLS sign-in **1/1 PASS**,0.224s:
  `/private/tmp/pinbook-ios-registration-owner-tls-regression-focused.log`.
  Added bounded TEST-ONLY route/error/count tracing, no raw tokens/body details or
  production logging. Full rerun **162/162 PASS**,14.157s:
  `/private/tmp/pinbook-ios-registration-owner-core-diagnostic.log`.
- Expanded that sign-in test to THREE mandatory fresh listener/certificate cases.
  Any case failure still fails the suite: no retry-on-failure or credential replay.
  Full **162/162 PASS** including all3cases,14.342s:
  `/private/tmp/pinbook-ios-registration-owner-core-repeated.log`.
- Added stale-device-generation coverage and monotonic expiry during signing before
  dispatch. Final full core **163/163 PASS**,13.498s, including all3TLS cases:
  `/private/tmp/pinbook-ios-registration-owner-final-core.log`.
  Existing intermittentTLS failure remains a recorded final-regression caveat;
  repeated green runs do not prove an underlying fix.
- Thirteen new core tests now cover exact access-only session ticket, refresh/
  sign-out/re-login/forgery/expiry; fresh lookup including REGISTERED; late commit;
  pending wait/recovery/same-key null; foreign/absent registrations; current session
  AFTER device reads/signing/metadata commit; stale device generations; wall and
  monotonic operation/proof limits; retained busy ownership on uncooperative cancel;
  and absent/expired/canceled access before key creation.
- New composed actual localhostTLS owner test checks lookup→challenge→complete→lookup,
  bearer handling, captured raw64P256 verification, durable metadata and unchanged
  account credentials. Uses synthetic Keychain API/CryptoKit fixture keys only.
- Initial Simulator test compilation **PASS**:
  `/private/tmp/pinbook-ios-registration-owner-test-build.log`. Final expanded test
  compilation **PASS**:
  `/private/tmp/pinbook-ios-registration-owner-final-test-build.log`.
  No app-host/UI run, actual SecureEnclave/Keychain protection or real provider proof.
  Fresh Woo GUI release is still absent; unchanged task activity is not a live GUI
  operation and was not counted as a verified wait. Useful headless work continued.
- No normal navigation, real account/key activation, shared resource, phone,
  signing/version, source push or TestFlight change. Next consent/durable-join gates
  are listed in TEAM_DEVICE_REGISTRATION_IOS.md and the complete final checklist.
- Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-registration-owner-release.log`.

## 2026-09-04 protected device identity and uncertain-proof recovery (inactive)

- Onboarding compatibility **8/8 PASS** after adding the validating prepared-
  challenge initializer: `/private/tmp/pinbook-ios-device-custody-compile.log`.
- Initial custody test compilation failed on throwing values inside nested Swift
  Testing macros. Both failed attempts retained, not passes:
  `/private/tmp/pinbook-ios-device-custody-focused.log` and
  `/private/tmp/pinbook-ios-device-custody-focused-fixed.log`.
- Corrected initial11cases **PASS** in0.038s:
  `/private/tmp/pinbook-ios-device-custody-focused-verified.log`.
- Expanded15cases including Keychain policy/CAS adapters and two-owner races
  **PASS** in0.029s: `/private/tmp/pinbook-ios-device-custody-races.log`.
- Full core before composed transport **148/148 PASS**,13.285s:
  `/private/tmp/pinbook-ios-device-custody-final-core.log`.
- Full core with actual localhostTLS lookup→challenge→complete and verification
  of the transmitted raw64 P256 signature **149/149 PASS**,13.156s:
  `/private/tmp/pinbook-ios-device-custody-composed-core.log`.
  Synthetic opaque handles/ephemeral CryptoKit fixture keys only; no real hardware
  key, deployed registration service, provider credentials or system trust change.
- Simulator **build-for-testing PASS**:
  `/private/tmp/pinbook-ios-device-custody-test-build.log`. Production SecureEnclave
  adapter compiles; it was NOT invoked. Existing Apple/Google test-only warnings
  remain. No new app-host execution and no shared-GUI/physical evidence inferred.
- Read Apple's official SecureEnclave/CryptoKit/accessibility guidance and local
  SDK declarations; see TEAM_DEVICE_CUSTODY_IOS.md for source links, policy and
  explicit platform limits. Real Keychain64KiB/CAS/protection/restore and Secure
  Enclave stored-size/lock behavior remain acceptance gates. Normal navigation,
  data/backup keys, account sessions, shared resources and build0.1.0(3) unchanged.
- Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-device-custody-release.log`.

## 2026-09-04 thirteen-route native onboarding transport (inactive)

- Four strict protocol-JSON tests **PASS**:
  `/private/tmp/pinbook-ios-onboarding-json-tests.log`. Initial missing-try compile
  error was corrected before this successful focused run (the focused log was
  reused; no retained standalone copy of that first compile output).
- Initial six intercepted route tests **6/6 PASS** in0.041s:
  `/private/tmp/pinbook-ios-onboarding-http-tests.log`. Two further clock/expiry and
  prepared-proof tests were added for final full validation.
- Initial full core **129 tests, 1 failure**, not a pass:
  `/private/tmp/pinbook-ios-onboarding-full-core.log`. Existing boundary test still
  expected the old32KiB auth limit; updated to verify4096accepted/4097rejected after
  intentionally narrowing auth/nonlist onboarding to4KiB. Google remains32KiB.
- Final full core **133/133 PASS** in14.704s:
  `/private/tmp/pinbook-ios-onboarding-final-core.log`, scratch
  `/private/tmp/pinbook-google-core.K7cTEo`, `-j 2`. Includes four parser tests,
  eight intercepted onboarding tests and two new real localhost TLS tests plus
  all existing custody/archive/auth/provider-wire regression suites.
- All13routes, public/protected bearer scopes, exact field/role/device binding,
  strictfalse vs numericzero, duplicate decoded JSON, list caps/uniqueIDs, null vs
  error, one retained HTTP slot across auth/onboarding, native cancellation,
  clock rollback/access expiry and proof revalidation covered. Actual local TLS
  covers preview/current/list and ambiguous join503/lost response without replay
  or saved-session mutation. Fixtures are synthetic; no deployed backend/provider.
- Simulator **build-for-testing PASS**:
  `/private/tmp/pinbook-ios-onboarding-final-test-build.log`. No app-host runtime
  inferred; existing Apple/Google UIKit fake-driver and device tests still await
  fresh shared-GUI coordination. Existing test-only UIWindow deprecation, mutable
  test-clock capture and deliberate callback-vs-async SDK warnings remain.
- Financial data/backup keys, normal navigation, shared infrastructure, provider
  setup, signing/version settings and published build0.1.0(3) unchanged. No source
  push, real account activation, physical acceptance or TestFlight upload.
- Final unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-onboarding-final-release.log`.

## 2026-09-04 Google native browser and bounded code exchange (inactive)

- Exact AppAuth3.0.0 resolved at a972daac82d449d58ab119e91c68153e29ddac33;
  app and shared-core lockfiles retained. No GIDSignIn, OAuth client ID, URL scheme,
  account connection or navigation activation installed. SDK browser/state/PKCE
  only; Pinbook owns token HTTP. No AppAuth shared-session override/token helper.
- Existing auth HTTP regression **8/8 PASS** after adding the narrowly separate
  Google header profile: `/private/tmp/pinbook-ios-google-token-compile.log`.
  Google code-exchange tests **6/6 PASS** in0.030s, fully intercepted with no network:
  `/private/tmp/pinbook-ios-google-token-focused.log`.
- First actual SDK test attempt hit `.build/build.db` disk I/O errors and ran zero
  matching tests. It exited1 and is NOT a pass:
  `/private/tmp/pinbook-ios-google-oauth-sdk-tests.log`. Disk check showed91GiB free;
  no active swift-test/xcodebuild/xctest process remained. The database/journal had
  link count2; underlying cause is not established. Preserved cache and logs.
- Fresh isolated scratch directory `/private/tmp/pinbook-google-core.K7cTEo`
  removed that cache dependency. Two compile attempts then exposed imported Swift
  API details (throwing BOOL imports as Void; async cancellation of non-Sendable
  SDK session is unsafe). Fixed to explicit main-thread cancellation completion
  and a throwing resume wrapper. Failed compile logs retained:
  `/private/tmp/pinbook-ios-google-oauth-sdk-isolated-tests.log` and
  `/private/tmp/pinbook-ios-google-oauth-sdk-fixed-tests.log`.
- Actual AppAuthCore request/session tests with a silent fake user agent
  **4/4 PASS** in0.003s:
  `/private/tmp/pinbook-ios-google-oauth-sdk-verified-tests.log`. Exact raw nonce,
  independent state/S256, scope/audience, matching and duplicate callbacks, foreign
  URL versus bad state, and cancellation-after-dismissal; no browser/provider used.
- Full core **119/119 PASS** in12.214s, including existing localhost TLS, archive,
  custody, sign-in and device-wire suites:
  `/private/tmp/pinbook-ios-google-final-core.log`, using the isolated scratch path.
- Final iPhone Simulator build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-google-final-test-build.log`. Five new fake Google-driver
  tests compile, but their runtime execution remains pending shared-GUI clearance,
  together with prior Apple and device-wire iPhone tests. No new app-host pass claim.
  App/test binaries both load the same generated dynamic AppAuth product framework,
  not separately embedded copies of its Objective-C classes (otool/nm inspection).
- Final unsigned iPhone Release **PASS**, including exclusion of DEBUG-only fake
  provider/presenter injection:
  `/private/tmp/pinbook-ios-google-final-release.log`.
- No real Google-issued token, Apple account sheet, physical acceptance, provider
  grant, production authority, financial mutation, source push or TestFlight upload.
  See TEAM_GOOGLE_IDENTITY_ADAPTER_IOS.md for source and remaining activation gates.

## 2026-09-04 native device-enrollment wire interoperability (inactive)

- Six new core tests cover exact Node/CryptoKit bytes and signatures, public-key
  validation/thumbprint, local bindings, canonical origins, bounds/time, altered
  challenge fields, raw64 versus DER and single versus double hashing.
- First focused compile failed on two nested `#require` test macros; split their
  intermediate values. Failed log retained:
  `/private/tmp/pinbook-ios-device-wire-focused.log`. Corrected initial five tests
  passed at `/private/tmp/pinbook-ios-device-wire-focused-fixed.log`; sixth added
  fresh native signature generation and optional PUBLIC-ONLY reverse-vector output.
- Full core **109/109 PASS** in15.451s:
  `/private/tmp/pinbook-ios-device-wire-full-core.log`. That log contains only a
  public synthetic interop vector, never its private key or any account credential.
- Review caught Foundation/WHATWG hostname differences for hexadecimal/numeric
  final labels. Reject those noncanonical origin spellings. Final full core
  **109/109 PASS** in16.172s:
  `/private/tmp/pinbook-ios-device-wire-final-core.log`.
- Read-only `scripts/verify-device-enrollment.mjs` passed both retained public
  vectors against the actual backend serializer (checkout0082c7cb, unchanged
  enrollment source79c1b5e9…). Exact message/thumbprint/raw64 and all nine field
  mutations, newline and double-hash negative cases pass. No database/listener.
- Final unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-device-wire-final-release.log`.
- Initial Simulator test compilation passed:
  `/private/tmp/pinbook-ios-device-wire-test-build.log`; final post-origin-hardening
  test compilation **PASS**:
  `/private/tmp/pinbook-ios-device-wire-final-test-build.log`. Runtime app-host
  launch still waits fresh shared-GUI clearance. No new app-host/UI/physical or real
  provider/enrollment acceptance is claimed by the macOS or Node passes.
- No private-key custody/signing API, route, navigation, client ID, account, signing
  configuration, data migration, source push or TestFlight upload added.

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
