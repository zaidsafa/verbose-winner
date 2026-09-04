import Foundation
import CryptoKit
import SwiftData
import Testing
import UIKit
import Darwin
@testable import Pinbook

#if targetEnvironment(simulator)
@Test(.disabled("Requires owner-approved separate QA app on physical iPhone."))
#else
@Test(.enabled(if: Bundle.main.bundleIdentifier == "com.zaidsafa.pinbook.ios.qa"))
#endif
func qaSecureEnclaveKeyReopensAndSignsWithoutExportingPrivateMaterial() throws {
    // The opaque handle lives only in this test's memory: no Keychain, file,
    // provider enrollment or account metadata write, and no logging of material.
    try #require(SecureEnclave.isAvailable)
    let provider = SecureEnclaveTeamDeviceKeys()
    let material = try provider.generate()
    #expect((1...4096).contains(material.sealed.count))
    let reopened = try SecureEnclaveTeamDeviceKeys().publicKey(sealed: material.sealed)
    #expect(reopened.thumbprint == material.publicKey.thumbprint)
    let message = Data("Pinbook QA isolated physical signing check".utf8)
    let signature = try provider.sign(sealed: material.sealed, message: message)
    #expect(signature.count == 64)
    let decoded = try P256.Signing.ECDSASignature(rawRepresentation: signature)
    #expect(reopened.key.isValidSignature(decoded, for: message))
    #expect(!reopened.key.isValidSignature(decoded, for: Data("different QA message".utf8)))
    #expect(throws: TeamDeviceCustodyError.keyUnavailable) {
        try provider.publicKey(sealed: Data())
    }
    #expect(throws: TeamDeviceCustodyError.bindingMismatch) {
        try provider.sign(sealed: material.sealed, message: Data(repeating: 0, count: 4097))
    }
}

#if targetEnvironment(simulator)
@Test(.disabled("Requires owner-approved separate QA app on physical iPhone."))
#else
@Test(.enabled(if: Bundle.main.bundleIdentifier == "com.zaidsafa.pinbook.ios.qa"))
#endif
func qaSecureEnclaveAgreementIdentityReopensAndMatchesSoftwarePeer() throws {
    try #require(SecureEnclave.isAvailable)
    let custody = try TeamAgreementKeyCustody(origin: "https://pinbook.invalid",
        accountID: "public-qa-agreement-account", authorityEpoch: "public-qa-epoch",
        enrollmentID: "public-qa-agreement-enrollment", requireAccess: {})
    let retained = try custody.prepare()
    #expect(try custody.current().keyThumbprint == retained.keyThumbprint)

    let peerKey = P256.KeyAgreement.PrivateKey()
    let peerWire = try TeamDeviceEnrollmentWire.publicKey(
        P256.Signing.PublicKey(x963Representation: peerKey.publicKey.x963Representation))
    let peer = TeamAgreementPublic(keyThumbprint: peerWire.thumbprint, publicKey: peerWire)
    let partyU = Data("delivery".utf8), partyV = Data("physical-qa-peer".utf8)
    var retainedKEK = try custody.derive(peer: peer, algorithm: "ECDH-ES+A256KW",
        partyU: partyU, partyV: partyV)
    let retainedAgreement = try P256.KeyAgreement.PublicKey(
        x963Representation: retained.publicKey.key.x963Representation)
    var peerSecret = try peerKey.sharedSecretFromKeyAgreement(with: retainedAgreement)
        .withUnsafeBytes { Data($0) }
    var peerKEK = try TeamDeliveryCryptoPrimitives.concatKDF(sharedSecret: peerSecret,
        algorithm: "ECDH-ES+A256KW", partyU: partyU, partyV: partyV, bits: 256)
    var contentKey = Data((0..<32).map(UInt8.init))
    defer {
        retainedKEK.resetBytes(in: retainedKEK.startIndex..<retainedKEK.endIndex)
        peerSecret.resetBytes(in: peerSecret.startIndex..<peerSecret.endIndex)
        peerKEK.resetBytes(in: peerKEK.startIndex..<peerKEK.endIndex)
        contentKey.resetBytes(in: contentKey.startIndex..<contentKey.endIndex)
    }
    #expect(retainedKEK == peerKEK)
    let wrapped = try TeamDeliveryCryptoPrimitives.wrapA256(kek: retainedKEK, key: contentKey)
    #expect(try TeamDeliveryCryptoPrimitives.unwrapA256(kek: peerKEK, wrapped: wrapped) == contentKey)
}

@Test func personalBackupReaderChecksActualBytesAndShortReads() throws {
    var chunks = [Data("ab".utf8), Data("cd".utf8), Data()]
    let data = try BackupFileRead.readBounded(maximumBytes: 4) { requested in
        #expect(requested <= 5)
        return chunks.removeFirst()
    }
    #expect(data == Data("abcd".utf8))
    #expect(chunks.isEmpty)
    #expect(try BackupFileRead.readBounded(maximumBytes: 0) { _ in Data() }.isEmpty)
    #expect(throws: BackupRecoveryError.fileTooLarge) {
        try BackupFileRead.readBounded(maximumBytes: 4) { _ in Data(repeating: 0, count: 5) }
    }
    var reads = 0
    #expect(throws: BackupRecoveryError.fileTooLarge) {
        try BackupFileRead.readBounded(maximumBytes: 4) { _ in
            reads += 1
            return Data(repeating: 0, count: reads == 1 ? 4 : 1)
        }
    }
    #expect(reads == 2)
    #expect(throws: BackupRecoveryError.fileAccessFailed) {
        try BackupFileRead.readBounded { _ in throw BackupRecoveryError.fileAccessFailed }
    }
}

@Test func personalBackupReaderRejectsUnsafeFilesAndCoordinatesLocalRead() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PinbookRead-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("backup.json")
    let bytes = Data("{\"formatVersion\":8}".utf8)
    try bytes.write(to: file)
    #expect(try await BackupFileRead.load(file) == bytes)
    #expect(try BackupFileRead.readRegularFile(file, maximumBytes: bytes.count) == bytes)
    #expect(throws: BackupRecoveryError.fileTooLarge) {
        try BackupFileRead.readRegularFile(file, maximumBytes: bytes.count - 1)
    }
    let link = directory.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    let fifo = directory.appendingPathComponent("pipe.json")
    #expect(mkfifo(fifo.path, 0o600) == 0)
    for url in [directory, link, fifo, directory.appendingPathComponent("missing.json"), URL(string: "https://example.invalid/backup.json")!] {
        #expect(throws: BackupRecoveryError.fileAccessFailed) {
            try BackupFileRead.readRegularFile(url)
        }
    }
}

@Test func personalBackupReaderHonorsCancellation() async throws {
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try BackupFileRead.readBounded { _ in
            Issue.record("Cancelled reads must not request content")
            return Data()
        }
    }
    do {
        _ = try await task.value
        Issue.record("Cancelled read should fail")
    } catch is CancellationError { }
}

@MainActor
@Test func cancelledPersonalRestoreDoesNotCreatePreviewOrMutateRecords() async throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    try PinbookBootstrap.prepare(context)
    let data = try JSONEncoder().encode(PinbookBackup())
    let task = Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        return try await BackupRecoveryService(context: context).prepareRestore(data: data)
    }
    do {
        _ = try await task.value
        Issue.record("Cancelled restore must not create a preview")
    } catch is CancellationError { }
    #expect(try context.fetch(FetchDescriptor<BackupActivityItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<BackupSnapshotItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<ExpenseItem>()).isEmpty)
}

@MainActor
@Test func productionBootstrapCreatesOnlyInfrastructureRecords() throws {
    #expect(!PinbookLaunchConfiguration.production.showsTeamRecoveryPreviewFixture)
    #expect(!PinbookLaunchConfiguration.production.showsTeamKeySetupFixture)
    #expect(!PinbookLaunchConfiguration.production.showsTeamMembershipFixture)
    #expect(!PinbookLaunchConfiguration.production.showsTeamInvitationAccountFixture)
    #expect(!PinbookLaunchConfiguration.production.showsTeamInvitationWorkflowFixture)
#if DEBUG
    #expect(!PinbookLaunchConfiguration(arguments: ["-PinbookTeamInvitationWorkflow"]).showsTeamInvitationWorkflowFixture)
    #expect(PinbookLaunchConfiguration(arguments: ["-PinbookFixture", "empty", "-PinbookTeamInvitationWorkflow"]).showsTeamInvitationWorkflowFixture)
    #expect(PinbookLaunchConfiguration(arguments: ["-PinbookFixture", "empty", "-PinbookTeamInvitationWorkflow", "-PinbookInvitationWorkflowScenario", "invalid"]).invitationWorkflowFixtureScenario == "new")
    #expect(!PinbookLaunchConfiguration(arguments: ["-PinbookTeamInvitationAccount"]).showsTeamInvitationAccountFixture)
    #expect(PinbookLaunchConfiguration(arguments: ["-PinbookFixture", "empty", "-PinbookTeamInvitationAccount"]).showsTeamInvitationAccountFixture)
    #expect(PinbookLaunchConfiguration(arguments: ["-PinbookFixture", "empty", "-PinbookTeamInvitationAccount", "-PinbookInvitationAccountScenario", "invalid"]).invitationAccountFixtureScenario == "new")
    #expect(!PinbookLaunchConfiguration(arguments: ["-PinbookTeamMembership"]).showsTeamMembershipFixture)
    #expect(PinbookLaunchConfiguration(arguments: ["-PinbookFixture", "empty", "-PinbookTeamMembership"]).showsTeamMembershipFixture)
    #expect(!PinbookLaunchConfiguration(arguments: ["-PinbookTeamKeySetup"]).showsTeamKeySetupFixture)
    #expect(PinbookLaunchConfiguration(arguments: ["-PinbookFixture", "empty", "-PinbookTeamKeySetup"]).showsTeamKeySetupFixture)
    #expect(!PinbookLaunchConfiguration(arguments: ["-PinbookTeamRecoveryPreview"]).showsTeamRecoveryPreviewFixture)
    #expect(PinbookLaunchConfiguration(arguments: ["-PinbookFixture", "empty", "-PinbookTeamRecoveryPreview"]).showsTeamRecoveryPreviewFixture)
#endif
    let container = try inMemoryContainer()
    let context = container.mainContext

    try PinbookBootstrap.prepare(context)

    #expect(try context.fetch(FetchDescriptor<BookItem>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<AppearanceSettingsItem>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<ExpenseItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<SettlementItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<ExpenseTemplateItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<ReceiptMetadataItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<BackupActivityItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<BackupSnapshotItem>()).isEmpty)
    let settings = try #require(context.fetch(FetchDescriptor<AppearanceSettingsItem>()).first)
    #expect(settings.favoriteCurrencies.isEmpty)
    #expect(settings.preferredCurrency == nil)
}

@Test func onboardingPolicySeparatesNewReturningAndTestLaunches() {
    #expect(PinbookOnboardingPolicy.shouldPresent(
        mode: .automatic,
        hasCompleted: false,
        overrideDismissed: false
    ))
    #expect(!PinbookOnboardingPolicy.shouldPresent(
        mode: .automatic,
        hasCompleted: true,
        overrideDismissed: false
    ))
    #expect(PinbookOnboardingPolicy.shouldPresent(
        mode: .show,
        hasCompleted: true,
        overrideDismissed: false
    ))
    #expect(!PinbookOnboardingPolicy.shouldPresent(
        mode: .skip,
        hasCompleted: false,
        overrideDismissed: false
    ))
    #expect(!PinbookOnboardingPolicy.shouldPresent(
        mode: .show,
        hasCompleted: false,
        overrideDismissed: true
    ))
}

@Test func languageContractIncludesAndroidParityAndCorrectDirection() {
    #expect(PinbookLanguage.allCases.map(\.rawValue) == [
        "system", "en", "ar", "tr", "zh-Hans", "zh-Hant", "es", "fr", "de",
        "pt-BR", "hi", "id", "ja", "ko", "ru", "it", "ur",
    ])
    #expect(PinbookLanguage.system.effectiveLocale(systemLocale: Locale(identifier: "tr_TR")).identifier == "tr_TR")
    #expect(PinbookLanguage.arabic.layoutDirection() == .rightToLeft)
    #expect(PinbookLanguage.urdu.layoutDirection() == .rightToLeft)
    #expect(PinbookLanguage.traditionalChinese.layoutDirection() == .leftToRight)
    #expect(PinbookLanguage.system.layoutDirection(preferredLanguages: ["ur-PK"]) == .rightToLeft)
    #expect(PinbookLanguage.system.resolved(preferredLanguages: ["zh-TW"]) == .traditionalChinese)
    #expect(PinbookLanguage.system.resolved(preferredLanguages: ["zh-CN"]) == .simplifiedChinese)
    #expect(PinbookLanguage.system.resolved(preferredLanguages: ["pt-PT"]) == .brazilianPortuguese)
    #expect(PinbookLanguage.system.resolved(preferredLanguages: ["nl-NL", "de-DE"]) == .german)
    #expect(PinbookLanguage.system.resolved(preferredLanguages: ["nl-NL"]) == .english)
    #expect(PinbookLanguage.system.layoutDirection(preferredLanguages: ["fa-IR"]) == .leftToRight)
    #expect(PinbookLanguage.system.layoutDirection(preferredLanguages: ["nl-NL", "ur-PK"]) == .rightToLeft)
    #expect(PinbookLanguage.system.layoutDirection(preferredLanguages: ["fa-IR", "de-DE"]) == .leftToRight)
}

@Test func everyParityLanguageIsCompiledAndContainsTranslatedInterfaceAndServiceCopy() throws {
    #expect(PinbookLanguage.availableCases == PinbookLanguage.allCases)
    for language in PinbookLanguage.allCases where language != .system && language != .english {
        let bundle = language.bundle()
        #expect(bundle.bundleURL.lastPathComponent == "\(language.rawValue).lproj")
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        let values = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        #expect(values.count == 336)
        for key in ["Language", "Welcome to Pinbook", "Purpose and person are required.", "This backup is corrupt or contains invalid data.", "This backup exceeds the 128 MiB limit. Your records have not been changed.", "I agree to join this team with the role shown.", "We couldn't confirm the result. Check membership before trying anything else.", "Check whether this account still belongs to the team.",
                    "Check previous join", "Check the previous attempt before sending another join request.",
                    "The previous join is still pending. Confirm again to retry the same invitation.",
                    "Retry join", "I agree to retry joining this team with the role shown.",
                    "The previous attempt could not be checked. You can check it again or close this screen.",
                    "Account access", "Review the team and role before signing in.",
                    "Signing in does not register this device or join the team.",
                    "I agree to sign in for this invitation.", "Continue to sign in", "Continue with this account",
                    "Checking account access…",
                    "Account access could not be confirmed. Close this screen before signing in again.",
                    "Account access is ready. Registering this device and joining need separate confirmation.",
                    "Account screen closed. Open the invitation again to continue.",
                    "Account cleanup could not be confirmed. Do not retry this invitation yet.",
                    "Register this device", "This device needs its own registration before you can join the team.",
                    "Registration does not join the team or share your private notes.",
                    "I agree to register this device for the account shown.", "Registering device…",
                    "An earlier registration is still pending. Wait until the time shown, then continue.",
                    "The previous attempt was not found. Confirm again to retry with the same device.",
                    "Registration could not be confirmed. Continue to check the previous attempt before trying again.",
                    "Continue registration", "This device is registered. Continue to review your team membership.",
                    "Device screen closed. Open the invitation again to continue.",
                    "Setup could not continue. Close this screen and reopen the invitation.",
                    "Team setup closed. Open the invitation again to continue."] {
            let value = try #require(values[key])
            #expect(!value.isEmpty && value != key)
        }
    }
}

@Test func chosenLanguageBundlesLocalizeServiceErrorsIndependentlyOfSystemLanguage() {
    let arabic = String(localized: "Purpose and person are required.", bundle: PinbookLanguage.arabic.bundle(), locale: Locale(identifier: "ar"))
    let chinese = String(localized: "Purpose and person are required.", bundle: PinbookLanguage.simplifiedChinese.bundle(), locale: Locale(identifier: "zh-Hans"))
    #expect(arabic == "الغرض والشخص مطلوبان.")
    #expect(chinese == "用途和人员为必填项。")
}

@Test func widgetDeepLinksRouteWithoutExposingFinancialData() throws {
    let add = try #require(PinbookDeepLink(url: URL(string: "pinbook://expense/new")!))
    #expect(add == .newExpense)
    #expect(add.destinationTab == .expenses)
    #expect(add.opensExpenseEditor)

    let summary = try #require(PinbookDeepLink(url: URL(string: "pinbook://summary")!))
    #expect(summary == .summary)
    #expect(summary.destinationTab == .summary)
    #expect(!summary.opensExpenseEditor)

    #expect(PinbookDeepLink(url: URL(string: "https://example.com")!) == nil)
    #expect(PinbookDeepLink(url: URL(string: "pinbook://unknown")!) == nil)
}

@Test func qaLinksAreIsolatedFromTheWorkingApp() {
    let production = URL(string: "pinbook://expense/new")!
    let qa = URL(string: "pinbook-qa://expense/new")!
    #expect(PinbookDeepLink(url: qa, expectedScheme: "pinbook-qa") == .newExpense)
    #expect(PinbookDeepLink(url: production, expectedScheme: "pinbook-qa") == nil)
    #expect(PinbookDeepLink(url: qa, expectedScheme: "pinbook") == nil)
    #expect(PinbookDeepLink(url: production, expectedScheme: "") == nil)
    #expect(PinbookDeepLink(url: URL(string: "other://summary")!, expectedScheme: "other") == nil)
}

@Test func currencyCatalogIncludesEveryFoundationCommonISOCodeAndASymbol() {
    let options = PinbookCurrencyCatalog.options(locale: Locale(identifier: "en_US"))
    #expect(options.count >= 150)
    #expect(Set(options.map(\.code)) == Set(Locale.commonISOCurrencyCodes))
    #expect(options.map(\.code) == options.map(\.code).sorted())
    #expect(options.allSatisfy { !$0.symbol.isEmpty && !$0.localizedName.isEmpty })
    #expect(options.contains { $0.code == "CNY" })
    #expect(options.contains { $0.code == "USD" })
    #expect(options.contains { $0.code == "KWD" })
}

@Test func everySkinMaintainsReadablePrimaryAndAccentContrast() {
    for style in [UIUserInterfaceStyle.light, .dark] {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let label = UIColor.label.resolvedColor(with: traits)
        for skin in PinbookSkin.allCases {
            let surface = skin.resolvedSurface(for: style)
            #expect(contrastRatio(label, surface) >= 4.5)
            for backdrop in skin.resolvedBackdrop(for: style) {
                #expect(contrastRatio(label, backdrop) >= 4.5)
            }
            #expect(contrastRatio(skin.resolvedAccent(for: style), surface) >= 3.0)
            #expect(contrastRatio(skin.resolvedProminentLabel(for: style), skin.resolvedAccent(for: style)) >= 4.5)
        }
    }
}

@MainActor
@Test func swiftDataPersistsExpenseAndPartialPayment() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let expense = ExpenseItem(
        amountMinor: 12_345,
        currency: "CNY",
        purpose: "Courier",
        counterparty: "Customer"
    )
    let payment = SettlementItem(expenseID: expense.id, amountMinor: 2_345)
    context.insert(expense)
    context.insert(payment)
    try context.save()

    let storedExpenses = try context.fetch(FetchDescriptor<ExpenseItem>())
    let storedPayments = try context.fetch(FetchDescriptor<SettlementItem>())
    #expect(storedExpenses.count == 1)
    #expect(ExpenseCalculations.remainingMinor(for: expense, settlements: storedPayments) == 10_000)
}

@MainActor
@Test func summaryNeverCombinesCurrencies() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    context.insert(ExpenseItem(amountMinor: 100, currency: "USD", purpose: "A", counterparty: "P"))
    context.insert(ExpenseItem(amountMinor: 200, currency: "EUR", purpose: "B", counterparty: "P"))
    try context.save()

    let totals = ExpenseCalculations.totalsByCurrency(
        expenses: try context.fetch(FetchDescriptor<ExpenseItem>()),
        settlements: []
    )
    #expect(totals == ["USD": 100, "EUR": 200])
}

@MainActor
@Test func bookManagementPreservesAnActiveUnarchivedBook() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    try PinbookBootstrap.prepare(context)
    let settings = try #require(context.fetch(FetchDescriptor<AppearanceSettingsItem>()).first)
    let defaultBook = try #require(context.fetch(FetchDescriptor<BookItem>()).first)

    let createdTravel = try BookOperations.create(named: "  Travel  ", in: context)
    let travel = try #require(createdTravel)
    #expect(travel.name == "Travel")
    try BookOperations.select(travel, settings: settings, in: context)
    #expect(settings.activeBookID == travel.id)

    try BookOperations.setArchived(true, for: travel, settings: settings, in: context)
    #expect(!travel.isArchived)

    try BookOperations.setArchived(true, for: defaultBook, settings: settings, in: context)
    #expect(defaultBook.isArchived)
    try BookOperations.setArchived(false, for: defaultBook, settings: settings, in: context)
    try BookOperations.rename(defaultBook, to: "  Household  ", in: context)
    #expect(defaultBook.name == "Household")
    #expect(!defaultBook.isArchived)
}

@MainActor
@Test func activeBookQueriesIsolateOpenNotedAndCurrencyTotals() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let first = ExpenseItem(
        amountMinor: 1_000,
        currency: "USD",
        purpose: "First",
        counterparty: "A",
        bookID: "first"
    )
    let firstNoted = ExpenseItem(
        amountMinor: 2_000,
        currency: "USD",
        purpose: "First noted",
        counterparty: "A",
        bookID: "first",
        isNoted: true
    )
    let second = ExpenseItem(
        amountMinor: 9_000,
        currency: "EUR",
        purpose: "Second",
        counterparty: "B",
        bookID: "second"
    )
    [first, firstNoted, second].forEach(context.insert)
    try context.save()

    let stored = try context.fetch(FetchDescriptor<ExpenseItem>())
    let firstOpen = PinbookQueries.expenses(stored, in: "first", noted: false)
    let firstArchived = PinbookQueries.expenses(stored, in: "first", noted: true)
    #expect(firstOpen.map(\.id) == [first.id])
    #expect(firstArchived.map(\.id) == [firstNoted.id])
    #expect(ExpenseCalculations.totalsByCurrency(expenses: firstOpen, settlements: []) == ["USD": 1_000])
}

@MainActor
@Test func templatesAndFavoritesStayInsideTheirBook() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let firstFavorite = ExpenseItem(
        amountMinor: 1_500,
        currency: "USD",
        purpose: "Favorite",
        counterparty: "A",
        bookID: "first",
        isFavorite: true
    )
    let secondFavorite = ExpenseItem(
        amountMinor: 2_500,
        currency: "EUR",
        purpose: "Other favorite",
        counterparty: "B",
        bookID: "second",
        isFavorite: true
    )
    let firstTemplate = ExpenseTemplateItem(
        bookID: "first",
        name: "First template",
        amountMinor: 900,
        currency: "USD",
        purpose: "Template",
        counterparty: "A"
    )
    let deletedTemplate = ExpenseTemplateItem(
        bookID: "first",
        name: "Deleted",
        amountMinor: 100,
        currency: "USD",
        purpose: "Deleted",
        counterparty: "A"
    )
    [firstFavorite, secondFavorite].forEach(context.insert)
    [firstTemplate, deletedTemplate].forEach(context.insert)
    try context.save()
    try TemplateOperations.setDeleted(true, for: deletedTemplate, in: context)
    #expect(deletedTemplate.isTombstoned)

    let expenses = try context.fetch(FetchDescriptor<ExpenseItem>())
    let templates = try context.fetch(FetchDescriptor<ExpenseTemplateItem>())
    #expect(PinbookQueries.favoriteExpenses(expenses, in: "first").map(\.id) == [firstFavorite.id])
    #expect(PinbookQueries.templates(templates, in: "first").map(\.id) == [firstTemplate.id])
}

@MainActor
@Test func quickAddCopiesDraftIntoAFreshUnstarredExpense() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let source = ExpenseItem(
        amountMinor: 12_345,
        currency: "KWD",
        purpose: "Recurring",
        counterparty: "Supplier",
        bookID: "source",
        category: "Samples",
        tags: ["repeat"],
        privateNote: "Private",
        isFavorite: true
    )
    context.insert(source)
    try context.save()

    let copy = try QuickAddOperations.createExpense(
        from: ExpenseDraft(favorite: source),
        in: "active",
        context: context,
        now: 123_456
    )
    #expect(copy.id != source.id)
    #expect(copy.bookID == "active")
    #expect(copy.amountMinor == source.amountMinor)
    #expect(copy.currency == source.currency)
    #expect(copy.tags == ["repeat"])
    #expect(!copy.isFavorite)
    #expect(!copy.isNoted)
    #expect(copy.reminderAt == nil)
    #expect(copy.occurredAt == 123_456)
}

@Test func receiptFileStoreSavesLoadsRemovesAndRejectsTraversal() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookReceiptStore-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    let source = Data([0x89, 0x50, 0x4E, 0x47])

    let fileName = try await store.save(data: source, preferredFileName: "customer receipt.PNG")
    #expect(fileName.hasSuffix(".png"))
    #expect(!fileName.contains("customer"))
    #expect(try await store.load(fileName: fileName) == source)

    var rejectedTraversal = false
    do {
        _ = try await store.load(fileName: "../outside.png")
    } catch ReceiptFileStoreError.invalidFileName {
        rejectedTraversal = true
    }
    #expect(rejectedTraversal)

    try await store.remove(fileName: fileName)
    var removedFileIsUnavailable = false
    do {
        _ = try await store.load(fileName: fileName)
    } catch {
        removedFileIsUnavailable = true
    }
    #expect(removedFileIsUnavailable)
}

@MainActor
@Test func statementScopeStaysInsideBookPersonAndCurrency() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let selected = ExpenseItem(
        amountMinor: 1_000,
        currency: "USD",
        purpose: "Selected",
        counterparty: "A",
        bookID: "first"
    )
    let otherCurrency = ExpenseItem(
        amountMinor: 2_000,
        currency: "EUR",
        purpose: "Other currency",
        counterparty: "A",
        bookID: "first"
    )
    let otherPerson = ExpenseItem(
        amountMinor: 3_000,
        currency: "USD",
        purpose: "Other person",
        counterparty: "B",
        bookID: "first"
    )
    let otherBook = ExpenseItem(
        amountMinor: 4_000,
        currency: "USD",
        purpose: "Other book",
        counterparty: "A",
        bookID: "second"
    )
    [selected, otherCurrency, otherPerson, otherBook].forEach(context.insert)
    try context.save()

    let stored = try context.fetch(FetchDescriptor<ExpenseItem>())
    let scoped = PinbookQueries.statementExpenses(stored, in: "first", person: "A", currency: "USD")
    #expect(scoped.map(\.id) == [selected.id])
}

@Test func localStatementsPreserveExactMinorUnitsAndCreateReadableFiles() throws {
    let expense = ExpenseRecord(
        id: "expense",
        amountMinor: 12_345,
        currency: "USD",
        purpose: "Freight, \"priority\"",
        counterparty: "North Star",
        occurredAt: 1_788_192_000_000,
        createdAt: 1_788_192_000_000,
        updatedAt: 1_788_192_000_000,
        isNoted: false
    )
    let activePayment = SettlementRecord(
        id: "active",
        expenseId: expense.id,
        amountMinor: 2_345,
        note: nil,
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 1,
        isDeleted: false
    )
    let deletedPayment = SettlementRecord(
        id: "deleted",
        expenseId: expense.id,
        amountMinor: 9_999,
        note: nil,
        occurredAt: 2,
        createdAt: 2,
        updatedAt: 2,
        isDeleted: true
    )
    let generator = LocalStatementGenerator()

    let csv = try generator.csv(for: [expense], settlements: [activePayment, deletedPayment])
    let csvText = try #require(String(data: csv, encoding: .utf8))
    #expect(Array(csv.prefix(3)) == [0xEF, 0xBB, 0xBF])
    #expect(csvText.hasPrefix("occurred_at"))
    #expect(csvText.contains("\"Freight, \"\"priority\"\"\""))
    #expect(csvText.contains(",12345,2345,10000,USD,open"))

    let pdf = try generator.pdf(for: [expense], settlements: [activePayment, deletedPayment])
    #expect(pdf.count > 1_000)
    #expect(String(data: pdf.prefix(4), encoding: .ascii) == "%PDF")
}

@Test func statementCSVNeutralizesSpreadsheetFormulas() throws {
    let first = ExpenseRecord(
        id: "first",
        amountMinor: 100,
        currency: "USD",
        purpose: "=1+1",
        counterparty: "+SUM(A1:A2)",
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 1,
        isNoted: false
    )
    let second = ExpenseRecord(
        id: "second",
        amountMinor: 200,
        currency: "USD",
        purpose: "-2+3",
        counterparty: "@SUM(A1:A2)",
        occurredAt: 2,
        createdAt: 2,
        updatedAt: 2,
        isNoted: false
    )

    let csv = try LocalStatementGenerator().csv(for: [first, second], settlements: [])
    let text = try #require(String(data: csv, encoding: .utf8))
    #expect(text.contains(",'=1+1,'+SUM(A1:A2),"))
    #expect(text.contains(",'-2+3,'@SUM(A1:A2),"))
}

@Test func statementArithmeticOverflowFailsExplicitly() throws {
    let expense = ExpenseRecord(
        id: "overflow",
        amountMinor: Int64.max,
        currency: "USD",
        purpose: "Overflow",
        counterparty: "Test",
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 1,
        isNoted: false
    )
    let payments = [
        SettlementRecord(
            id: "max",
            expenseId: expense.id,
            amountMinor: Int64.max,
            note: nil,
            occurredAt: 1,
            createdAt: 1,
            updatedAt: 1,
            isDeleted: false
        ),
        SettlementRecord(
            id: "one",
            expenseId: expense.id,
            amountMinor: 1,
            note: nil,
            occurredAt: 2,
            createdAt: 2,
            updatedAt: 2,
            isDeleted: false
        ),
    ]

    do {
        _ = try LocalStatementGenerator().csv(for: [expense], settlements: payments)
        Issue.record("CSV generation should reject settlement overflow")
    } catch let error as StatementGenerationError {
        #expect(error == .arithmeticOverflow)
    }

    let second = ExpenseRecord(
        id: "second-overflow",
        amountMinor: Int64.max,
        currency: "USD",
        purpose: "Overflow total",
        counterparty: "Test",
        occurredAt: 2,
        createdAt: 2,
        updatedAt: 2,
        isNoted: false
    )
    do {
        _ = try LocalStatementGenerator().pdf(for: [expense, second], settlements: [])
        Issue.record("PDF generation should reject total overflow")
    } catch let error as StatementGenerationError {
        #expect(error == .arithmeticOverflow)
    }
}

@Test func statementPDFPaintsWhitePagesWithDarkInkInDarkMode() throws {
    let expense = ExpenseRecord(
        id: "dark-pdf",
        amountMinor: 12_345,
        currency: "USD",
        purpose: "Print-safe statement",
        counterparty: "Dark appearance",
        occurredAt: 1_788_192_000_000,
        createdAt: 1_788_192_000_000,
        updatedAt: 1_788_192_000_000,
        isNoted: false
    )
    var generationResult: Result<Data, Error>?
    UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
        generationResult = Result {
            try LocalStatementGenerator().pdf(for: [expense], settlements: [])
        }
    }
    let pdf = try #require(generationResult).get()
    let dataProvider = try #require(CGDataProvider(data: pdf as CFData))
    let document = try #require(CGPDFDocument(dataProvider))
    let page = try #require(document.page(at: 1))
    let width = 595
    let height = 842
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(UIColor.magenta.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.drawPDFPage(page)

    let corner = (10 * width + 10) * 4
    #expect(pixels[corner] > 245)
    #expect(pixels[corner + 1] > 245)
    #expect(pixels[corner + 2] > 245)
    let darkPixelCount = stride(from: 0, to: pixels.count, by: 4).filter { index in
        pixels[index] < 80 && pixels[index + 1] < 80 && pixels[index + 2] < 80
    }.count
    #expect(darkPixelCount > 100)
}

@Test func reminderRequestIsDeterministicAndLockScreenPrivate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let spec = ReminderRequestFactory.make(
        expenseID: "expense-1",
        at: date,
        title: "Expense reminder",
        calendar: calendar
    )

    #expect(spec.identifier == "pinbook-expense-expense-1")
    #expect(calendar.date(from: spec.dateComponents) == date)
    #expect(spec.body == "Open Pinbook to review a scheduled expense.")
    #expect(!spec.body.contains("Rent"))
    #expect(!spec.body.contains("USD"))
    #expect(!spec.body.contains("100"))
}

@MainActor
@Test func receiptLifecycleKeepsMetadataAndPrivateFileInStep() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookReceiptLifecycle-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    let container = try inMemoryContainer()
    let context = container.mainContext
    let expense = ExpenseItem(
        amountMinor: 1_000,
        currency: "USD",
        purpose: "Receipt test",
        counterparty: "Supplier"
    )
    context.insert(expense)
    try context.save()
    let source = Data("private receipt".utf8)

    let metadata = try await ReceiptLifecycle.attach(
        data: source,
        preferredFileName: "receipt.jpg",
        mimeType: "image/jpeg",
        displayName: "Receipt photo",
        to: expense,
        context: context,
        store: store
    )
    #expect(metadata.expenseID == expense.id)
    #expect(!metadata.isTombstoned)
    #expect(try await store.load(fileName: metadata.fileName) == source)

    try await ReceiptLifecycle.remove(metadata, context: context, store: store)
    #expect(metadata.isTombstoned)
    let storedMetadata = try context.fetch(FetchDescriptor<ReceiptMetadataItem>())
    #expect(storedMetadata.count == 1)
    #expect(storedMetadata.first?.isTombstoned == true)
    var removedFileIsUnavailable = false
    do {
        _ = try await store.load(fileName: metadata.fileName)
    } catch {
        removedFileIsUnavailable = true
    }
    #expect(removedFileIsUnavailable)
}

@MainActor
@Test func failedReceiptTombstoneSaveKeepsThePrivateFile() async throws {
    enum ExpectedFailure: Error { case save }

    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookReceiptFailedRemoval-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    let source = Data("keep this receipt".utf8)
    let fileName = try await store.save(data: source, preferredFileName: "receipt.jpg")
    let metadata = ReceiptMetadataItem(
        expenseID: "expense",
        fileName: fileName,
        mimeType: "image/jpeg",
        displayName: "Receipt photo",
        updatedAt: 123
    )
    var rollbackCalled = false

    do {
        try await ReceiptLifecycle.remove(
            metadata,
            store: store,
            persist: { throw ExpectedFailure.save },
            rollback: {
                rollbackCalled = true
                metadata.isTombstoned = false
                metadata.updatedAt = 123
            }
        )
        Issue.record("Receipt removal should surface the tombstone save failure")
    } catch ExpectedFailure.save {
        // Expected: the private file must not be removed before metadata persists.
    }

    #expect(rollbackCalled)
    #expect(!metadata.isTombstoned)
    #expect(metadata.updatedAt == 123)
    #expect(try await store.load(fileName: fileName) == source)
}

@Test func scrollClearanceKeepsFinalRowsAboveTheLiquidGlassTabBar() {
    #expect(PinbookLayout.tabBarScrollClearance >= 96)
}

@MainActor
@Test func localBackupExportsAndroidV8WithReceiptBytesAndAllEntityTypes() async throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookBackupExport-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    try PinbookBootstrap.prepare(context)

    let expense = ExpenseItem(
        id: "expense",
        amountMinor: 12_345,
        currency: "USD",
        purpose: "Courier",
        counterparty: "Customer",
        category: "Delivery",
        tags: ["urgent"],
        privateNote: "private",
        updatedAt: 20
    )
    context.insert(expense)
    context.insert(SettlementItem(id: "payment", expenseID: expense.id, amountMinor: 2_345, updatedAt: 21))
    context.insert(ExpenseTemplateItem(
        id: "template",
        bookID: "default",
        name: "Monthly",
        amountMinor: 900,
        currency: "EUR",
        purpose: "Template",
        counterparty: "Supplier",
        updatedAt: 22
    ))
    try context.save()
    let receiptBytes = Data("private receipt bytes".utf8)
    _ = try await ReceiptLifecycle.attach(
        data: receiptBytes,
        preferredFileName: "receipt.png",
        mimeType: "image/png",
        displayName: "Receipt photo",
        to: expense,
        context: context,
        store: store
    )

    let prepared = try await BackupRecoveryService(context: context, receiptStore: store)
        .prepareExport(now: 1_788_192_000_000)
    let decoded = try JSONDecoder().decode(PinbookBackup.self, from: prepared.data)
    #expect(decoded.formatVersion == 8)
    #expect(decoded.books.count == 1)
    #expect(decoded.expenses.count == 1)
    #expect(decoded.settlements.count == 1)
    #expect(decoded.templates.count == 1)
    #expect(decoded.receiptAttachments.count == 1)
    #expect(decoded.appearance != nil)
    #expect(Data(base64Encoded: decoded.receiptAttachments[0].contentBase64) == receiptBytes)
    #expect(prepared.fileName.contains("v8"))
    #expect(decoded.totalRecordCount == 6)
}

@MainActor
@Test func corruptAndUnsupportedBackupsNeverMutateFinancialRecords() async throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    try PinbookBootstrap.prepare(context)
    context.insert(ExpenseItem(
        id: "original",
        amountMinor: 500,
        currency: "USD",
        purpose: "Keep me",
        counterparty: "Person",
        updatedAt: 10
    ))
    try context.save()
    let service = BackupRecoveryService(context: context)

    let invalidCases: [(Data, BackupRecoveryError)] = [
        (Data("not-json".utf8), .invalidBackup),
        (Data(#"{"formatVersion":9}"#.utf8), .unsupportedBackupVersion),
    ]
    for (invalidData, expectedError) in invalidCases {
        do {
            _ = try await service.prepareRestore(data: invalidData)
            Issue.record("Invalid backup should be rejected")
        } catch let error as BackupRecoveryError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Invalid backup should use a localized recovery error")
        }
        let expenses = try context.fetch(FetchDescriptor<ExpenseItem>())
        #expect(expenses.count == 1)
        #expect(expenses.first?.id == "original")
        #expect(expenses.first?.purpose == "Keep me")
        #expect(try context.fetch(FetchDescriptor<BackupSnapshotItem>()).isEmpty)
    }
    let failures = try context.fetch(FetchDescriptor<BackupActivityItem>())
    #expect(failures.count == 2)
    #expect(failures.allSatisfy { $0.kind == .failedRestore && $0.status == .failed })
}

@MainActor
@Test func appliedRestoreCreatesSnapshotAndRecoveryRollsBackExactly() async throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let root = FileManager.default.temporaryDirectory
        .appending(path: "PinbookBackupRecovery-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ReceiptFileStore(rootDirectory: root)
    try PinbookBootstrap.prepare(context)
    context.insert(ExpenseItem(
        id: "shared",
        amountMinor: 100,
        currency: "USD",
        purpose: "Original local",
        counterparty: "Person",
        updatedAt: 10
    ))
    try context.save()
    let service = BackupRecoveryService(context: context, receiptStore: store)
    let baseline = try await service.captureBackup(exportedAt: nil)
    let updated = ExpenseRecord(
        id: "shared",
        amountMinor: 150,
        currency: "USD",
        purpose: "Newer imported",
        counterparty: "Person",
        bookId: "default",
        occurredAt: 1,
        createdAt: 1,
        updatedAt: 20,
        isNoted: false
    )
    let addedEUR = ExpenseRecord(
        id: "added-eur",
        amountMinor: 200,
        currency: "EUR",
        purpose: "Separate currency",
        counterparty: "Person",
        bookId: "default",
        occurredAt: 2,
        createdAt: 2,
        updatedAt: 20,
        isNoted: false
    )
    let incoming = try PinbookBackup(
        formatVersion: 8,
        exportedAt: 30,
        expenses: [addedEUR, updated],
        books: baseline.books,
        appearance: baseline.appearance
    )
    let encoded = try JSONEncoder().encode(incoming)

    let prepared = try await service.prepareRestore(data: encoded)
    let expenseSummary = try #require(prepared.preview.summaries.first { $0.entity == .expenses })
    #expect(expenseSummary.added == 1)
    #expect(expenseSummary.updated == 1)
    let snapshot = try await service.applyRestore(prepared, now: 40)
    let applied = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(Set(applied.map(\.currency)) == ["USD", "EUR"])
    #expect(applied.first { $0.id == "shared" }?.purpose == "Newer imported")
    #expect(try context.fetch(FetchDescriptor<BackupSnapshotItem>()).count == 1)

    try await service.recover(snapshot, now: 50)
    let recovered = try context.fetch(FetchDescriptor<ExpenseItem>())
    #expect(recovered.count == 1)
    #expect(recovered.first?.id == "shared")
    #expect(recovered.first?.purpose == "Original local")
    #expect(snapshot.recoveredAt == 50)
    let activities = try context.fetch(FetchDescriptor<BackupActivityItem>())
    #expect(activities.contains { $0.kind == .preview && $0.status == .succeeded })
    #expect(activities.contains { $0.kind == .appliedRestore && $0.status == .succeeded })
    #expect(activities.contains { $0.kind == .recovery && $0.status == .succeeded })
}

#if DEBUG
@Test func launchArgumentsSelectDeterministicFixturePresentation() {
    let configuration = PinbookLaunchConfiguration(arguments: [
        "Pinbook",
        "-PinbookFixture", "populated",
        "-PinbookTab", "summary",
        "-PinbookSkin", "nightInk",
        "-PinbookTheme", "dark",
    ])

    #expect(configuration.usesFixtures)
    #expect(configuration.usesEphemeralStore)
    #expect(configuration.onboardingMode == .skip)
    #expect(configuration.initialTab == .summary)
    #expect(configuration.skin == .nightInk)
    #expect(configuration.themeMode == "dark")

    let onboarding = PinbookLaunchConfiguration(arguments: [
        "Pinbook",
        "-PinbookFixture", "empty",
        "-PinbookOnboarding", "show",
    ])
    #expect(!onboarding.usesFixtures)
    #expect(onboarding.usesEphemeralStore)
    #expect(onboarding.onboardingMode == .show)
}

@MainActor
@Test func debugFixtureUsesInfrastructureAndDeterministicSampleRecords() throws {
    let container = try inMemoryContainer()
    let context = container.mainContext
    let configuration = PinbookLaunchConfiguration(arguments: [
        "Pinbook", "-PinbookFixture", "populated", "-PinbookSkin", "softPastel",
    ])

    try PinbookBootstrap.prepare(context)
    try PinbookDebugFixtures.prepare(context, configuration: configuration)

    let settings = try #require(context.fetch(FetchDescriptor<AppearanceSettingsItem>()).first)
    let expenses = try context.fetch(FetchDescriptor<ExpenseItem>())
    let settlements = try context.fetch(FetchDescriptor<SettlementItem>())
    #expect(settings.interfaceSkin == PinbookSkin.softPastel.rawValue)
    #expect(settings.favoriteCurrencies == ["CNY", "KWD", "USD"])
    #expect(expenses.count == 4)
    #expect(expenses.filter(\.isNoted).count == 1)
    #expect(expenses.filter(\.isFavorite).map(\.id) == ["fixture-rent"])
    #expect(expenses.filter { $0.reminderAt != nil }.map(\.id) == ["fixture-freight"])
    #expect(settlements.count == 1)
    #expect(try context.fetch(FetchDescriptor<ExpenseTemplateItem>()).count == 1)
    #expect(
        ExpenseCalculations.totalsByCurrency(
            expenses: expenses.filter { !$0.isNoted },
            settlements: settlements
        ) == ["CNY": 800_000, "USD": 285_075, "KWD": 123_456]
    )
}
#endif

@MainActor
private func inMemoryContainer() throws -> ModelContainer {
    let schema = Schema(PinbookSchema.models)
    let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func contrastRatio(_ first: UIColor, _ second: UIColor) -> Double {
    let brighter = max(relativeLuminance(first), relativeLuminance(second))
    let darker = min(relativeLuminance(first), relativeLuminance(second))
    return (brighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(_ color: UIColor) -> Double {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
    func linear(_ value: CGFloat) -> Double {
        let component = Double(value)
        return component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
}
