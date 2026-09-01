import Foundation
import SwiftData

struct PinbookLaunchConfiguration: Equatable {
    var usesFixtures = false
    var initialTab = PinbookTab.expenses
    var skin: PinbookSkin?
    var themeMode: String?

    static let production = PinbookLaunchConfiguration()

    init() {}

    static var current: PinbookLaunchConfiguration {
#if DEBUG
        PinbookLaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
#else
        .production
#endif
    }

#if DEBUG
    init(arguments: [String]) {
        usesFixtures = arguments.value(after: "-PinbookFixture") == "populated"

        switch arguments.value(after: "-PinbookTab") {
        case "summary": initialTab = .summary
        case "noted": initialTab = .noted
        case "options": initialTab = .options
        default: initialTab = .expenses
        }

        if let value = arguments.value(after: "-PinbookSkin") {
            skin = PinbookSkin(rawValue: value)
        }

        if let value = arguments.value(after: "-PinbookTheme"), ["system", "light", "dark"].contains(value) {
            themeMode = value
        }
    }
#endif
}

#if DEBUG
@MainActor
enum PinbookDebugFixtures {
    static func prepare(_ context: ModelContext, configuration: PinbookLaunchConfiguration) throws {
        guard configuration.usesFixtures else { return }

        let settings = try context.fetch(FetchDescriptor<AppearanceSettingsItem>()).first
        settings?.favoriteCurrencies = ["CNY", "KWD", "USD"]
        settings?.preferredCurrency = "CNY"
        if let skin = configuration.skin {
            settings?.interfaceSkin = skin.rawValue
        }
        if let themeMode = configuration.themeMode {
            settings?.themeMode = themeMode
        }

        guard try context.fetch(FetchDescriptor<ExpenseItem>()).isEmpty else {
            try context.save()
            return
        }

        let rent = ExpenseItem(
            id: "fixture-rent",
            amountMinor: 1_260_000,
            currency: "CNY",
            purpose: "Monthly warehouse rent",
            counterparty: "Guangzhou Logistics Center",
            category: "Operations",
            tags: ["recurring"],
            isFavorite: true,
            occurredAt: 1_788_192_000_000,
            createdAt: 1_788_192_000_000,
            updatedAt: 1_788_278_400_000
        )
        let freight = ExpenseItem(
            id: "fixture-freight",
            amountMinor: 285_075,
            currency: "USD",
            purpose: "International freight and customs clearance",
            counterparty: "North Star Shipping",
            category: "Freight",
            reminderAt: 1_789_437_600_000,
            occurredAt: 1_787_760_000_000,
            createdAt: 1_787_760_000_000,
            updatedAt: 1_787_760_000_000
        )
        let samples = ExpenseItem(
            id: "fixture-samples",
            amountMinor: 123_456,
            currency: "KWD",
            purpose: "Supplier samples",
            counterparty: "Al Noor Trading",
            category: "Samples",
            occurredAt: 1_786_982_400_000,
            createdAt: 1_786_982_400_000,
            updatedAt: 1_786_982_400_000
        )
        let noted = ExpenseItem(
            id: "fixture-noted",
            amountMinor: 42_000,
            currency: "USD",
            purpose: "Prototype packaging",
            counterparty: "Mira Print Studio",
            category: "Packaging",
            occurredAt: 1_786_204_800_000,
            createdAt: 1_786_204_800_000,
            updatedAt: 1_788_364_800_000,
            isNoted: true,
            notedAt: 1_788_364_800_000
        )

        [rent, freight, samples, noted].forEach(context.insert)
        context.insert(SettlementItem(
            id: "fixture-rent-payment",
            expenseID: rent.id,
            amountMinor: 460_000,
            note: "First installment",
            occurredAt: 1_788_278_400_000,
            createdAt: 1_788_278_400_000,
            updatedAt: 1_788_278_400_000
        ))
        context.insert(ExpenseTemplateItem(
            id: "fixture-template-utilities",
            bookID: "default",
            name: "Warehouse utilities",
            amountMinor: 168_000,
            currency: "CNY",
            purpose: "Monthly utilities",
            counterparty: "Guangzhou Utilities",
            category: "Operations",
            tags: ["recurring"],
            createdAt: 1_787_760_000_000,
            updatedAt: 1_787_760_000_000
        ))
        try context.save()
    }
}

private extension Array where Element == String {
    func value(after flag: String) -> String? {
        guard let index = firstIndex(of: flag), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
#endif
