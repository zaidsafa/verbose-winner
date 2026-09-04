# Pinbook iOS Codex handoff

Updated: 2026-09-04 (Asia/Shanghai)

## Current isolated team-delivery workstream

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
- GitHub push was rejected by auto-review on 2026-09-04. Explicit owner approval
  is required to export this source and its four prior local localization/TestFlight
  ancestors to `https://github.com/zaidsafa/verbose-winner.git`, branch
  `codex/team-delivery-foundation`. No branch upload/PR/merge occurred. Do not retry
  via another tool, task or transport. Source stays local until approval is resolved.
- Local Swift tests: 24/24 passed (9 existing, 15 new). Simulator: 44 app tests
  passed, one hardware-only protection check explicitly skipped; 10/10 existing
  UI tests passed. Hardware protection is not claimed. See `docs/VALIDATION.md`
  for exact final-source versus Simulator evidence boundaries.
- Both final-source unsigned builds passed: generic iPhone Release and generic
  Simulator Debug. Compiled binaries include the final rollback-failure guard.
- Android requests the next local portable archive slice. Feasibility review was
  returned directly; implementation is waiting for the frozen plaintext schema and
  cross-platform fixture. See `docs/TEAM_DELIVERY_IOS.md`. Do not invent group crypto.
- Infrastructure and Android were notified directly. Admission remains NEEDS_INFO.
  Auth/crypto/enrollment/recovery, portable encrypted Android/iOS archive transfer,
  complete durable media handling and deployment admission remain prerequisites.
  No E2EE, public activation, physical deletion, or worldwide compliance claim.

## Current TestFlight publication

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
