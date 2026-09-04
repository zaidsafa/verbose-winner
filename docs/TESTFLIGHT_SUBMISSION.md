# Pinbook TestFlight submission sheet

Updated: September 4, 2026

## Build 3 candidate

Owner authorized TestFlight publication and source export. Build 2 was freshly
verified as Testing with both existing groups. Build 3 is being prepared with the
same user-facing functionality and inactive internal team/archive foundations.
No sign-in, cloud service, team sharing or recovery-key UI is enabled.

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
- Build: `2` (16-language candidate)
- Primary category: Finance
- Secondary category: Productivity
- User access: Full Access

The existing app record is `6807481054`; do not create a duplicate. The SKU is an internal permanent identifier and is not shown to customers. Every uploaded build must have a unique build number; keep version `0.1.0` and increment the app and widget build numbers together for replacements.

## TestFlight information

### Beta app description

Pinbook is a private, offline-first notebook for periodic expenses. Organize expenses by book, person, date, and currency; record partial payments; review remaining balances by currency; attach receipts; create local statements; and export or restore local backups through Files.

### What to test

New in build 2: 16 interface languages, a language picker in the introduction and Options, and improved Chinese archive wording.

Please switch languages during the introduction and in Options, restart the app to check your choice is saved, and try System Default. Check Simplified and Traditional Chinese separately and the right-to-left layout in Arabic and Urdu. Report awkward translations, clipped text, or incorrect number/currency formatting with the language and screen name.

Using disposable test data, create a book, choose currencies, add an expense, record a partial payment, and confirm balances remain separate by currency. Archive and restore an expense, try all five themes in Light/Dark, and check both Home Screen widgets. Test receipts, PDF/CSV sharing, reminders, and a Files backup/import/recovery round trip. Do not overwrite your only backup. Report crashes or unexpected data changes.

### Beta review contact

The owner's supplied name, international phone number, email, and feedback email
were saved directly in App Store Connect. Personal contact values are not repeated
in the repository. No sign-in or demo account is required.

### Beta review notes

No account or sign-in is required. Pinbook is offline-first and stores financial records locally. Backup and Recovery uses the native Files picker and requires the tester to choose a location. Receipt attachment uses Apple's selected-photo picker. The Home Screen widgets are privacy-safe shortcuts and display no financial amounts. No demo credentials are required.

## App privacy and compliance

- Privacy policy URL: `https://<YOUR DOMAIN>/pinbook/privacy`
- App Privacy answer: **No, we do not collect data from this app.**
- Tracking: No
- Third-party analytics or advertising: None
- Sign-in: None
- Content rights: Pinbook does not contain, show, or access third-party content.
- Export compliance: Pinbook does not implement non-exempt encryption. The bundle declares `ITSAppUsesNonExemptEncryption = NO`.
- Privacy manifest: included in the app bundle; it declares no tracking or collected data and declares app-only UserDefaults access under Apple's `CA92.1` reason.

Publish `docs/PRIVACY_POLICY.md` at the HTTPS privacy-policy URL before completing App Privacy. If any data handling changes before upload, re-audit these answers rather than copying them unchanged.

## App Store listing copy

Screenshots and the full listing are not required to begin internal TestFlight testing, but the following copy is prepared for the later App Store version.

### Subtitle

Private expense notebook

### Promotional text

Keep periodic expenses, partial payments, receipts, and balances organized privately on your iPhone and iPad.

### Description

Pinbook is a calm, private notebook for expenses that need to be charged, deducted, settled, or noted later.

Organize records into separate books, keep totals separated by currency, record partial payments, and see exactly what remains. Attach selected receipt images, build reusable templates, create person-and-currency statements, and schedule private local reminders.

Pinbook works offline and does not require an account. Your financial records stay on your device. When you want a copy, export a local backup through Apple's Files interface and preview every restore before applying it.

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
3. Add the privacy-policy URL and publish the **No Data Collected** answers under **App Privacy**.
4. Add the TestFlight beta description, feedback email, review contact, and review notes.
5. In Xcode select the `Pinbook` scheme and **Any iOS Device (arm64)**, then choose **Product → Archive**.
6. In Organizer select the archive, choose **Distribute App → TestFlight & App Store → Upload**, and let Xcode manage distribution signing. Use **TestFlight Internal Only** only if the build will never be sent to external testers.
7. Wait for App Store Connect to finish processing the build and answer any export-compliance prompt consistently with the declaration above.
8. Under **TestFlight**, use the existing internal and external **Zaid testing** groups and attach build `0.1.0 (2)`. Submit for TestFlight App Review if Apple requests it. Do not add new testers or create a public link unless separately requested.
9. Install Apple's TestFlight app on the iPhone, accept the invitation, and validate the exact processed build. TestFlight builds expire after 90 days.

Internal TestFlight supports up to 100 App Store Connect users. External TestFlight supports up to 10,000 testers and the first external build normally requires TestFlight App Review.
