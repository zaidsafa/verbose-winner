# Validation plan

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
  are recorded in `/private/tmp/pinbook-ios-team-foundation-release-final.log` and
  `/private/tmp/pinbook-ios-team-foundation-debug-final.log`.
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
