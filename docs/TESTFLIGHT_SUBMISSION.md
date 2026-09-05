# Pinbook TestFlight submission sheet

Updated: September 5, 2026

## Next-release gate

The owner checked build 3 and reports it is good. Keep it available and do not
upload or distribute incremental TestFlight updates. The next upload must be the
complete agreed feature set, integrated and validated as a final candidate.
Continue development locally; unresolved access, provider and security gates
must be resolved before claiming completion.

## Build 3 published to TestFlight

Owner authorized TestFlight publication and source export. Build 2 was freshly
verified as Testing with both existing groups. Build 3 was published with the
same user-facing functionality and inactive internal team/archive foundations.
No sign-in, cloud service, team sharing or recovery-key UI is enabled.

Build `0.1.0 (3)`, Apple ID `c43396a3-4fbd-4475-bbf9-6fcc819ee3c2`, uploaded
September 4 at 15:47 Asia/Shanghai and completed processing. Both existing internal
and external Zaid testing groups show **Testing**. External submission used
automatic notification; no new testers or public links were created. The text
below is saved in What to Test. No re-upload or re-submission is needed.

Suggested build 3 What to Test:

Build 3 is a regression-testing update with internal foundations for future
features; team sharing is not available in this build.

Please test the introduction and language selection, including both Chinese
scripts and Arabic/Urdu right-to-left layout. Check all five themes in Light and
Dark appearance, currency search/symbols, expenses, partial payments and balances.
Using disposable test data, test local backup/export and restore through Files,
receipts, PDF/CSV sharing, reminders and both Home Screen widgets. Keep a separate
backup before testing restore. Report crashes, unreadable text or unexpected data
changes, with the screen name, language and steps to reproduce.

Review notes remain offline-first/no sign-in. Internal archive cryptography uses
Apple CryptoKit only, with no third-party or proprietary cryptographic primitive;
it is not exposed in the app. The existing NO non-exempt encryption declaration is
retained based on Apple's OS-cryptography guidance, not a claim of no encryption.
Reference: [Apple encryption export guidance](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).

## Prior build 2 record

Build `0.1.0 (2)` has been uploaded, both existing test groups assigned, and external Submit for Review clicked with automatic tester notification checked. Final review status could not be refreshed because the Mac locked. Do not duplicate the upload/submission. The remaining angle-bracket values below are future-publication placeholders, not values to submit.

## App record

- Platform: iOS
- Name: `Pinbook: Expense Ledger`
- Primary language: English (U.S.)
- Bundle ID: `com.zaidsafa.pinbook.ios`
- Widget bundle ID: `com.zaidsafa.pinbook.ios.widgets`
- SKU: `PINBOOK-IOS-001`
- Version: `0.1.0`
- Current published build: `3`
- Next final-candidate build: `4` (reserve this number; increment app and widget together only after all release gates pass)
- Primary category: Finance
- Secondary category: Productivity
- User access: Full Access

The existing app record is `6807481054`; do not create a duplicate. The SKU is an internal permanent identifier and is not shown to customers. Every uploaded build must have a unique build number; keep version `0.1.0` and increment the app and widget build numbers together for replacements.

## TestFlight information

### Beta app description

Pinbook is a private, offline-first notebook for periodic expenses. Organize expenses by book, person, date, and currency; record partial payments; review remaining balances by currency; attach receipts; create local statements; export or restore local backups through Files; and optionally sync a private backup through Google Drive.

### What to test

This final candidate adds optional private Google Drive sync and completes the
agreed UX, localization, currency, theme, onboarding, widget and recovery work.

Please use disposable test data. Connect Google Drive from Options → Backup &
Recovery, confirm the consent screen says Pinbook cannot read other Drive files,
then test Sync now, sync when Pinbook opens, a second-device merge, and Disconnect.
Confirm local records remain safe after a network failure or cancelled sign-in.

Also switch languages during the introduction and in Options, restart the app to
check your choice is saved, and try System Default. Check both Chinese scripts and
Arabic/Urdu right-to-left layout. Test all five themes in Light and Dark, currency
search/symbols, expenses, partial payments, balances, receipts, PDF/CSV sharing,
reminders, both widgets, and a Files backup/import/recovery round trip. Report any
crash, unreadable text, clipped translation or unexpected data change with the
screen name, language and steps to reproduce.

### Beta review contact

The owner's supplied name, international phone number, email, and feedback email
were saved directly in App Store Connect. Personal contact values are not repeated
in the repository. No sign-in or demo account is required.

### Beta review notes

No Pinbook account is required. Pinbook is offline-first and stores financial records locally. Optional Google Drive sync asks the tester to sign in to their own Google account and grants only the private app-data-folder scope; Pinbook cannot read other Drive files. Manual Backup and Recovery uses the native Files picker and requires the tester to choose a location. Receipt attachment uses Apple's selected-photo picker. The Home Screen widgets are privacy-safe shortcuts and display no financial amounts. No demo credentials are required.

## App privacy and compliance

- Privacy policy URL: `https://<YOUR DOMAIN>/pinbook/privacy`
- App Privacy answer: **Yes, we collect data from this app.** Google Drive sync stores data off device on an ongoing basis after the user enables it, so it does not meet Apple's optional-disclosure exception.
- Data types: **Other Financial Info**, **Other User Content**, and **Photos or Videos**.
- For each data type: purpose **App Functionality**; **linked to the user**; **not used for tracking**.
- Tracking: No
- Third-party analytics or advertising: None
- Sign-in: Optional Google authorization for personal Drive sync; no Pinbook account.
- Content rights: Pinbook does not contain, show, or access third-party content.
- Export compliance: Pinbook does not implement non-exempt encryption. The bundle declares `ITSAppUsesNonExemptEncryption = NO`.
- Privacy manifest: included in the app bundle; it declares the three Drive-backed data types above, no tracking, and app-only UserDefaults access under Apple's `CA92.1` reason.

Publish `docs/PRIVACY_POLICY.md` at the HTTPS privacy-policy URL before completing App Privacy. If any data handling changes before upload, re-audit these answers rather than copying them unchanged.

## Google OAuth release gate

- The configured `drive.appdata` permission is a Google-listed **non-sensitive**
  scope. Sensitive/restricted-scope verification and a restricted-scope security
  assessment are not required for this scope.
- The Google Auth Platform project is currently **External / Testing** with only
  the owner's account as a test user. Testing authorizations expire after seven
  days and other TestFlight users cannot authorize the app.
- Before external TestFlight distribution, publish the privacy/support pages on
  an owned HTTPS domain, finish Google OAuth Branding with those URLs, add the
  authorized domain, and change Audience to **In production**. Complete Google's
  lighter brand verification if requested for the app name/logo.
- Do not describe external Drive sync as available until that production audience
  state and a fresh non-owner account authorization are verified.

Official references:

- https://developers.google.com/workspace/drive/api/guides/api-specific-auth
- https://developers.google.com/identity/protocols/oauth2
- https://support.google.com/cloud/answer/15549945

## App Store listing copy

Screenshots and the full listing are not required to begin internal TestFlight testing, but the following copy is prepared for the later App Store version.

### Subtitle

Private expense notebook

### Promotional text

Keep periodic expenses, partial payments, receipts, and balances organized privately on your iPhone and iPad.

### Description

Pinbook is a calm, private notebook for expenses that need to be charged, deducted, settled, or noted later.

Organize records into separate books, keep totals separated by currency, record partial payments, and see exactly what remains. Attach selected receipt images, build reusable templates, create person-and-currency statements, and schedule private local reminders.

Pinbook works offline and does not require a Pinbook account. Your financial records stay on your device by default. You can export a local backup through Apple's Files interface, preview every restore before applying it, or explicitly connect Google Drive to sync a private backup between your devices. Pinbook requests only its hidden app-data folder and cannot read your other Drive files.

Highlights:

- Books for separate people, projects, or workflows
- World currency catalog with 159 ISO currency codes
- Partial payments and remaining balances
- Currency-separated summaries without hidden conversion
- Favorites, templates, and Quick Add
- Private selected-photo receipt attachments
- Local PDF and CSV statements
- Local reminders with generic notification text
- Manual backup, restore preview, and recovery snapshot
- Optional private Google Drive sync
- 16 languages, including English, Arabic, Turkish, Simplified and Traditional Chinese, Spanish, French, German, Brazilian Portuguese, Hindi, Indonesian, Japanese, Korean, Russian, Italian, and Urdu
- Five adaptive themes and two privacy-safe widgets

### Keywords

`expenses,ledger,receipts,payments,balances,offline,private,currency,bookkeeping,statements`

### URLs and ownership

- Support URL: `https://<YOUR DOMAIN>/pinbook/support`
- Marketing URL: optional
- Copyright: `© 2026 <YOUR LEGAL NAME OR COMPANY>`
- Age rating: answer **None** for all objectionable-content categories based on the current build; App Store Connect calculates the final rating.

## Upload checklist

1. In Xcode, open **Pinbook.xcodeproj**. Under **Signing & Capabilities**, confirm team `Zaid Alsheikh (F98S3VN5NL)` and **Automatically manage signing** for both `Pinbook` and `PinbookWidgets`.
2. In App Store Connect, open the existing **Pinbook: Expense Ledger** app (`6807481054`). Do not create another app or bundle ID.
3. Complete the Google OAuth release gate above; external testers must not depend on the current one-user Testing configuration.
4. Add the privacy-policy URL and publish the Drive data disclosures listed under **App privacy and compliance**.
5. Add the TestFlight beta description, feedback email, review contact, and review notes.
6. In Xcode select the `Pinbook` scheme and **Any iOS Device (arm64)**, then choose **Product → Archive**.
7. In Organizer select the archive, choose **Distribute App → TestFlight & App Store → Upload**, and let Xcode manage distribution signing. Use **TestFlight Internal Only** only if the build will never be sent to external testers.
8. Wait for App Store Connect to finish processing the build and answer any export-compliance prompt consistently with the declaration above.
9. Under **TestFlight**, use the existing internal and external **Zaid testing** groups and attach the one newly processed final build. Submit for TestFlight App Review if Apple requests it. Do not reattach an older build, add new testers, or create a public link unless separately requested.
10. Install Apple's TestFlight app on the iPhone, accept the invitation, and validate the exact processed build. TestFlight builds expire after 90 days.

Internal TestFlight supports up to 100 App Store Connect users. External TestFlight supports up to 10,000 testers and the first external build normally requires TestFlight App Review.
