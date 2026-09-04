# Separate physical-device QA

Owner approved a separate Pinbook QA development installation on September 5,
2026. This is not a distributable candidate and does not lift the final-only
TestFlight hold. Android coordination is approved only for Pinbook two-device
notes testing; WooOrders remains separate.

## Latest retained invitation workflow checkpoint

The isolated QA presentation now traverses account access, device registration,
and membership with three distinct decisions. Physical app-host **308/308 PASS**,
8.672s, and the five new UI journeys **5/5 PASS**,106.359s. They cover Simplified
Chinese, Arabic RTL/existing account, three separate consents, explicit retry with
fresh consent each time, uncertain no-replay behavior, and background closure.

Exported Chinese dark-mode and Arabic RTL device-registration screenshots are
readable, use semantic foregrounds, keep machine IDs left-to-right, and retain a
scrollable action path. Artifacts:
`/private/tmp/Pinbook-QA-Physical-Workflow-Screen-20260905.xcresult`,
`/private/tmp/pinbook-qa-physical-workflow-screen-20260905.log`, and
`/private/tmp/pinbook-workflow-attachments-20260905-2/`.

This is synthetic UI/on-device model evidence, not live provider issuance,
registration, membership, notes synchronization, or TestFlight publication.
Complete physical UI regression **29/29 PASS**,422.507s, zero failures/skips:
`/private/tmp/Pinbook-QA-Physical-Workflow-Screen-Full-20260905.xcresult`.
QA then launched normally without fixture arguments. No ordinary app was targeted.
See TEAM_INVITATION_WORKFLOW_IOS.md and VALIDATION.md.

## Latest exact-account device-flow checkpoint

Core-only registration and invitation/device/membership connector changes passed
**299/299 physical app-host tests**,8.459s, zero skips/failures:
`/private/tmp/Pinbook-QA-Physical-Invitation-Device-Flow-20260905.xcresult`.
Tests on the phone use synthetic account/key/transport adapters for the new flow;
they do not enroll a live account or synchronize notes. No native UI code changed
and no UI suite was rerun for this checkpoint. Signed QA and ordinary unsigned
Release PASS,323 compiled app/widget translations match source, and QA launched
normally after testing. See VALIDATION.md and TEAM_INVITATION_DEVICE_FLOW_IOS.md.
Normal device-consent/parent navigation is still the next implementation step.

## Latest invitation account screen checkpoint

September5 isolated account preflight now supports read-only review, explicit
existing-account continuation or new unchecked sign-in consent. DEBUG presentation
uses public synthetic identities, not Apple/Google or live team requests. Normal
app navigation remains unchanged.

- Full candidate **287 app +24 UI PASS**,311 total, no skips/failures:
  `/private/tmp/Pinbook-QA-Physical-Invitation-Account-20260905.xcresult`.
  Chinese unchecked consent and Arabic existing-account screenshots inspected;
  RTL/LTR identities, wrapping, neutral disabled text and enabled mint button clear.
- After a core-only handoff expiry/ownership refinement and added regression,
  rebuilt **288 app +4 affected UI PASS**,292 total, no skips/failures:
  `/private/tmp/Pinbook-QA-Physical-Invitation-Account-Final-20260905.xcresult`.
  The remaining20 UI were not rerun after that core refinement; UI source unchanged.
- Final signed QA build and ordinary unsigned Release PASS. All323 localized
  entries match source in both compiled app/widget artifacts. QA normal launch
  succeeded after tests, without fixture arguments. Exact logs and screenshots in
  VALIDATION.md. No interim TestFlight publication or ordinary-app replacement.
- Real provider issuance, device enrollment, membership navigation, shared notes,
  account lifecycle/hardware recovery and final full-scope acceptance remain open.

## Isolation contract

| Setting | Ordinary app | Development QA |
| --- | --- | --- |
| App ID | com.zaidsafa.pinbook.ios | com.zaidsafa.pinbook.ios.qa |
| Widget ID | com.zaidsafa.pinbook.ios.widgets | com.zaidsafa.pinbook.ios.qa.widgets |
| Display name | Pinbook | Pinbook QA |
| Link scheme | pinbook | pinbook-qa |

`Config/DeviceQA.xcconfig` is explicit opt-in, Apple Development signing, and
`SKIP_INSTALL=YES`. Default project settings retain ordinary identity/version.
The widget reads its own compiled link scheme; app links reject the other scheme.
Signed QA app/widget entitlements contain their distinct application identifiers,
with no explicit Keychain-sharing or App Group entitlement. App container,
standard preferences and default Keychain access are therefore separately scoped.
No production provider configuration or personal automatic cloud sync is enabled.
QA UI fixtures use an in-memory store; Files tests open/dismiss pickers without
selecting a document or saving a backup.

## Build and installation evidence

- Device: iPhone 16 Pro, iOS26.6.1 (23G83), arm64e.
- Signed build-for-testing PASS: `/private/tmp/pinbook-ios-device-qa-build.log`.
- Artifact: `/private/tmp/pinbook-ios-device-qa-derived/Build/Products/Debug-iphoneos/Pinbook.app`.
- Test plan: `/private/tmp/pinbook-ios-device-qa-derived/Build/Products/Pinbook_iphoneos26.5-arm64.xctestrun`.
- Main app and UI runner signature verification passed with normal system trust
  access. Sandboxed verification initially reported CSSMERR_TP_NOT_TRUSTED;
  trust settings were not changed or bypassed.
- Exact compiled app/widget IDs, names and schemes match the table. QA app
  installed successfully through devicectl; read-only exact lookup confirmed
  `Pinbook QA | com.zaidsafa.pinbook.ios.qa | 0.1.0 (3)`.
- Installation receipt: `/private/tmp/pinbook-qa-install-20260905.json`;
  installed lookup: `/private/tmp/pinbook-qa-installed-20260905.json`.
- Ordinary unsigned Release build PASS with original app/widget IDs and `pinbook`
  scheme: `/private/tmp/pinbook-ios-qa-isolation-default-release.log`.
- Source and compiled QA app/widget catalog parity PASS: 306 keys, 15 translated
  locales plus English. Translation drafts are not human linguistic review.
- Ordinary TestFlight app was not established by the baseline device lookup.
  Do not claim a verified before/after inventory or inspect its records. Only the
  distinct QA bundle was targeted for installation/testing. No version bump,
  archive, source push or TestFlight upload occurred.

## Physical runtime evidence

- App-host tests: **263/263 PASS**, zero skips/failures. Includes QA deep-link
  isolation and real file-protection attribute check (`FileProtectionType.complete`).
  Result: `/private/tmp/Pinbook-QA-Physical-App-20260905.xcresult`.
  Log: `/private/tmp/pinbook-qa-physical-app-tests-20260905.log`.
- Membership UI: **3/3 PASS**,33.103s: unchecked consent/Chinese confirmation,
  uncertain join followed by Check rather than another Join, and immediate
  background clearing. Result:
  `/private/tmp/Pinbook-QA-Physical-Membership-UI-20260905.xcresult`.
  Log: `/private/tmp/pinbook-qa-physical-membership-ui-20260905.log`.
- Chinese confirmation screenshot exported and visually inspected: readable
  wrapping/identity/role layout, but white-on-jade prominent-button text is too
  faint. This observation triggered the correction below; behavioral test success
  alone did not catch the visual defect.
- Remaining baseline UI: **13/13 PASS**,182.692s, zero failures. Result:
  `/private/tmp/Pinbook-QA-Physical-Baseline-UI-20260905.xcresult`.
  Log: `/private/tmp/pinbook-qa-physical-baseline-ui-20260905.log`.
  Combined original UI coverage is16/16; contrast changes are a new candidate
  requiring fresh runtime checks. Night Ink light appearance, Chinese onboarding,
  and world-currency picker screenshots were inspected. Currency rows currently
  substituted a colon-currency icon when Foundation returned an ISO-code symbol;
  this misleading substitution is now removed as described below.

## Corrected visual candidate and hardware check

- Shared `PinbookProminentButtonStyle` wraps native Liquid Glass with explicit
  white-on-dark-accent / black-on-bright-accent labels. Existing destructive roles
  retain the native red treatment; button actions, disabled state and accessibility
  continue through native buttons. Numeric label/accent contrast is at least4.5:1
  for every skin in both appearances.
- Contrast candidate: **263 app tests +17 UI tests PASS**,280 total, zero failures
  or skips. UI245.158s; ten skin/appearance screenshots were exported and visually
  inspected. All ten show the intended readable light/dark label polarity.
  Result: `/private/tmp/Pinbook-QA-Physical-Contrast-20260905.xcresult`;
  log: `/private/tmp/pinbook-qa-physical-contrast-tests-20260905.log`.
  Screenshots: `/private/tmp/pinbook-qa-contrast-attachments-20260905/manifest.json`.
- Subsequent currency change displays Foundation's actual localized symbol or
  unambiguous ISO-code fallback, never another currency's icon. VoiceOver labels
  include code, localized name and symbol; switch state remains native.
- Latest QA candidate: **264 app tests +2 affected UI tests PASS**,266 total,
  zero failures or skips. The two UI cases are currency search and Chinese
  membership confirmation; their screenshots were visually inspected, showing
  accurate ISO/symbol badges and dark text on the jade Done button. The entire17
  UI suite was run on the immediately preceding contrast candidate, not rerun in
  full after the currency-only UI change.
  Result: `/private/tmp/Pinbook-QA-Physical-Currency-Hardware-20260905.xcresult`;
  log: `/private/tmp/pinbook-qa-physical-currency-hardware-20260905.log`.
- New QA-only physical Secure Enclave test PASS,0.014s: generate with the actual
  provider, reopen its opaque in-memory handle, sign, verify the64-byte P256
  signature, reject a changed message and invalid sizes. No Keychain/file/account
  metadata, enrollment or network write; no private/opaque material is exported
  or logged. Disabled outside the exact QA identity or on Simulator. This is not
  cross-process persistence, lock/unlock, passcode removal or recovery acceptance.
- Latest signed QA build and strict signature verification PASS:
  `/private/tmp/pinbook-qa-currency-hardware-build-20260905.log`.
  Ordinary unsigned Release with unchanged production ID/scheme PASS:
  `/private/tmp/pinbook-ios-contrast-currency-release-20260905.log`.
  Both compiled QA and Release app/widget catalogs exactly match all306 keys.
- QA was launched normally after tests, without synthetic launch arguments:
  `/private/tmp/pinbook-qa-normal-launch-20260905.json`. This is process-launch
  success, not a separate visual first-run acceptance claim.

This is not real Apple/Google login, full locked-device/passcode-removal testing,
Secure Enclave recovery acceptance, reviewed MLS interoperability, or phone-to-phone
notes sync. Cross-device delivery still needs the approved isolated service,
provider configuration, enrolled-device authorization, reviewed encryption/key
distribution and concrete send/fetch/save-before-ACK UI. Use only synthetic notes
in separate QA identities when those dependencies are ready.

## Rebuild

September5 follow-up: the explicit original-invitation retry screen and readable
disabled native glass labels now pass **272 app +20 UI tests**,292 total with no
failures/skips, on the physical QA phone. All312 catalog entries match compiled
QA and Release app/widget output. Exact result:
`/private/tmp/Pinbook-QA-Physical-Retry-Final-20260905.xcresult`.
See TEAM_MEMBERSHIP_RETRY_IOS.md and VALIDATION.md for the initial stale-catalog
assertion failure, correction and screenshot evidence. The complete UI result
precedes a subsequent test-only addition of Android's public Keystore vector;
do not conflate it with live cross-device notes delivery.
The public Android vector subsequently verified on the physical iPhone; the
test-only rebuild passed all273 app tests with no skips/failures. Result:
`/private/tmp/Pinbook-QA-Physical-Android-Vector-20260905.xcresult`.
See TEAM_DEVICE_ENROLLMENT_WIRE_IOS.md. QA was returned to normal launch afterward.

From this checkout, with owner-approved connected phone and development signing:

```sh
xcodebuild -project Pinbook.xcodeproj -scheme Pinbook -configuration Debug \
  -sdk iphoneos -destination 'platform=iOS,id=00008140-001670201ED8801C' \
  -xcconfig Config/DeviceQA.xcconfig \
  -derivedDataPath /private/tmp/pinbook-ios-device-qa-derived -jobs 2 \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build-for-testing
```

Never use this QA configuration for archive/upload or replace the ordinary app.
