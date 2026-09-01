# Pinbook iOS Codex handoff

Updated: 2026-09-01 (Asia/Shanghai)

## Ownership and source

- iOS repository: `zaidsafa/verbose-winner`
- Android read-only product reference: `zaidsafa/studious-potato`
- Android release reference: Pinbook 0.4.2, `versionCode 8`, source `442ae6a5bd2dc8ee26d6a1006dd9dda9fe4c0985`
- Initial iOS `main` bootstrap: `7b7fb061e22539632a13b9b5aa5c378235c83684`
- Active feature branch: `codex/pinbook-ios-foundation`

## Implemented scope

- Swift package foundation with Android backup-v8-compatible records.
- ISO currency-aware minor-unit money parsing and formatting.
- Deterministic newest-record merge with local-wins-ties behavior.
- Explicit service boundaries for Drive backup, receipts, statements, reminders, and later OCR.

## Validation

- `swift test --disable-sandbox --scratch-path /private/tmp/pinbook-ios-swift-build` passed all 5 tests on Xcode 26.6 / Swift 6.3.3.
- The alternate scratch path was required because the managed environment denied SwiftPM's user cache and nested sandbox; this is an environment boundary, not a source failure.

## Limitations

- App target, SwiftData store, and iOS 26 Liquid Glass SwiftUI feature shell are the next coherent update.
- Drive/OAuth, receipt import, statements, notifications, conflict-recovery UI, and OCR are architectural seams only, not implemented features.
- No Apple signing, OAuth credentials, external account settings, TestFlight, or App Store state has been created or changed.

## Exact next actions

1. Validate, commit, and push the core foundation.
2. Add the native iOS app target, local SwiftData persistence, and Expenses/Summary/Noted/Options shell.
3. Add app-target tests and run unsigned simulator compilation plus available unit tests.
