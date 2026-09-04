# Separate physical-device QA

Owner approved a separate Pinbook QA development installation on September 5,
2026. This is not a distributable candidate and does not lift the final-only
TestFlight hold. Android coordination is approved only for Pinbook two-device
notes testing; WooOrders remains separate.

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
  faint. Contrast correction and new runtime evidence are required before final
  acceptance; behavioral test success did not catch this visual defect.
- Remaining baseline UI checks are underway; no pass claimed yet.

This is not real Apple/Google login, full locked-device/passcode-removal testing,
Secure Enclave recovery acceptance, reviewed MLS interoperability, or phone-to-phone
notes sync. Cross-device delivery still needs the approved isolated service,
provider configuration, enrolled-device authorization, reviewed encryption/key
distribution and concrete send/fetch/save-before-ACK UI. Use only synthetic notes
in separate QA identities when those dependencies are ready.

## Rebuild

From this checkout, with owner-approved connected phone and development signing:

```sh
xcodebuild -project Pinbook.xcodeproj -scheme Pinbook -configuration Debug \
  -sdk iphoneos -destination 'platform=iOS,id=00008140-001670201ED8801C' \
  -xcconfig Config/DeviceQA.xcconfig \
  -derivedDataPath /private/tmp/pinbook-ios-device-qa-derived -jobs 2 \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build-for-testing
```

Never use this QA configuration for archive/upload or replace the ordinary app.
