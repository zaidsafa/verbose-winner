# Pinbook TestFlight submission sheet

Prepared: September 1, 2026

This sheet is ready to copy into App Store Connect. Replace every value in angle brackets before submitting an external beta or App Store version.

## App record

- Platform: iOS
- Name: `Pinbook`
- Primary language: English (U.S.)
- Bundle ID: `com.zaidsafa.pinbook.ios`
- Widget bundle ID: `com.zaidsafa.pinbook.ios.widgets`
- SKU: `PINBOOK-IOS-001`
- Version: `0.1.0`
- Build: `1`
- Primary category: Finance
- Secondary category: Productivity
- User access: Full Access

The SKU is an internal permanent identifier and is not shown to customers. Every uploaded build must have a unique build number; keep version `0.1.0` and increment build `1` to `2`, `3`, and so on for replacements.

## TestFlight information

### Beta app description

Pinbook is a private, offline-first notebook for periodic expenses. Organize expenses by book, person, date, and currency; record partial payments; review remaining balances by currency; attach receipts; create local statements; and export or restore local backups through Files.

### What to test

Please test first-run onboarding in English, Arabic, and Simplified Chinese; create a book; select favorite currencies; add an expense; record a partial payment; verify Summary remains separated by currency; mark and recover an expense from Noted; switch all five skins in Light and Dark; add both Home Screen widgets and confirm Quick Expense and Balance Overview open the correct screen. Use only disposable test data. For Backup & Recovery, save to a test Files location, preview the import before applying, then verify recovery. Report any clipped text, low contrast, wrong currency formatting, data loss, or crash.

### Beta review contact

- First name: `<FIRST NAME>`
- Last name: `<LAST NAME>`
- Phone: `<PHONE INCLUDING COUNTRY CODE>`
- Email: `<YOUR SUPPORT EMAIL>`
- Feedback email: `<YOUR SUPPORT EMAIL>`

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
- English, Arabic, and Simplified Chinese
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
2. In App Store Connect, choose **Apps → + → New App** and create the app record using the values above. The app record must exist before the first upload.
3. Add the privacy-policy URL and publish the **No Data Collected** answers under **App Privacy**.
4. Add the TestFlight beta description, feedback email, review contact, and review notes.
5. In Xcode select the `Pinbook` scheme and **Any iOS Device (arm64)**, then choose **Product → Archive**.
6. In Organizer select the archive, choose **Distribute App → TestFlight & App Store → Upload**, and let Xcode manage distribution signing. Use **TestFlight Internal Only** only if the build will never be sent to external testers.
7. Wait for App Store Connect to finish processing the build and answer any export-compliance prompt consistently with the declaration above.
8. Under **TestFlight**, create an internal group, attach build `0.1.0 (1)`, and add App Store Connect users. For external testing, create an external group, provide the review information, and submit the first build for TestFlight App Review.
9. Install Apple's TestFlight app on the iPhone, accept the invitation, and validate the exact processed build. TestFlight builds expire after 90 days.

Internal TestFlight supports up to 100 App Store Connect users. External TestFlight supports up to 10,000 testers and the first external build normally requires TestFlight App Review.
