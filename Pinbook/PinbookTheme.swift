import SwiftUI

enum PinbookSkin: String, CaseIterable, Identifiable {
    case paperGlass = "paperGlass"
    case cleanLedger = "cleanLedger"
    case softPastel = "softPastel"
    case editorial = "editorial"
    case nightInk = "nightInk"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .paperGlass: "Paper glass"
        case .cleanLedger: "Clean ledger"
        case .softPastel: "Soft pastel"
        case .editorial: "Editorial"
        case .nightInk: "Night ink"
        }
    }

    var accent: Color {
        switch self {
        case .paperGlass: Color(red: 0.20, green: 0.39, blue: 0.34)
        case .cleanLedger: Color(red: 0.12, green: 0.36, blue: 0.62)
        case .softPastel: Color(red: 0.64, green: 0.35, blue: 0.52)
        case .editorial: Color(red: 0.63, green: 0.23, blue: 0.18)
        case .nightInk: Color(red: 0.47, green: 0.64, blue: 0.96)
        }
    }

    var backdrop: LinearGradient {
        let colors: [Color] = switch self {
        case .paperGlass: [Color(red: 0.97, green: 0.94, blue: 0.86), Color(red: 0.87, green: 0.93, blue: 0.88)]
        case .cleanLedger: [Color(red: 0.91, green: 0.96, blue: 0.99), Color(red: 0.82, green: 0.91, blue: 0.96)]
        case .softPastel: [Color(red: 0.98, green: 0.90, blue: 0.94), Color(red: 0.90, green: 0.92, blue: 0.99)]
        case .editorial: [Color(red: 0.96, green: 0.92, blue: 0.85), Color(red: 0.92, green: 0.84, blue: 0.76)]
        case .nightInk: [Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.12, green: 0.17, blue: 0.28)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var contentSurface: Color {
        switch self {
        case .nightInk: Color(red: 0.11, green: 0.14, blue: 0.22).opacity(0.94)
        default: Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92)
        }
    }

    var preferredScheme: ColorScheme? { self == .nightInk ? .dark : nil }
}

private struct PinbookSkinKey: EnvironmentKey {
    static let defaultValue = PinbookSkin.paperGlass
}

extension EnvironmentValues {
    var pinbookSkin: PinbookSkin {
        get { self[PinbookSkinKey.self] }
        set { self[PinbookSkinKey.self] = newValue }
    }
}

extension Int64 {
    func formattedMoney(currency: String, locale: Locale = .current) -> String {
        let formatted = (try? MoneyAmount(minorUnits: self, currencyCode: currency).formatted(locale: locale))
            ?? "\(currency) \(self)"
        return "\u{2066}\(formatted)\u{2069}"
    }
}
