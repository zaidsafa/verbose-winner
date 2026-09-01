import SwiftUI

enum PinbookLayout {
    static let tabBarScrollClearance: CGFloat = 128
}

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

    var subtitle: LocalizedStringKey {
        switch self {
        case .paperGlass: "Warm paper with calm jade glass"
        case .cleanLedger: "Crisp blue structure for focused work"
        case .softPastel: "Gentle color with a softer rhythm"
        case .editorial: "Confident typography and warm contrast"
        case .nightInk: "Deep navy designed for low light"
        }
    }

    var symbol: String {
        switch self {
        case .paperGlass: "doc.richtext"
        case .cleanLedger: "tablecells"
        case .softPastel: "sparkles"
        case .editorial: "newspaper"
        case .nightInk: "moon.stars.fill"
        }
    }

    var accent: Color {
        let colors = accentColors
        return adaptiveColor(light: colors.light, dark: colors.dark)
    }

    var backdrop: LinearGradient {
        let stops = backdropColors
        let colors = [
            adaptiveColor(light: stops.light.0, dark: stops.dark.0),
            adaptiveColor(light: stops.light.1, dark: stops.dark.1),
        ]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var contentSurface: Color {
        let colors = surfaceColors
        return adaptiveColor(light: colors.light, dark: colors.dark)
    }

    var preferredScheme: ColorScheme? { self == .nightInk ? .dark : nil }

    func resolvedAccent(for style: UIUserInterfaceStyle) -> UIColor {
        style == .dark ? accentColors.dark : accentColors.light
    }

    func resolvedSurface(for style: UIUserInterfaceStyle) -> UIColor {
        style == .dark ? surfaceColors.dark : surfaceColors.light
    }

    func resolvedBackdrop(for style: UIUserInterfaceStyle) -> [UIColor] {
        let colors = backdropColors
        return style == .dark ? [colors.dark.0, colors.dark.1] : [colors.light.0, colors.light.1]
    }

    private var accentColors: (light: UIColor, dark: UIColor) {
        switch self {
        case .paperGlass:
            (UIColor(red: 0.10, green: 0.37, blue: 0.30, alpha: 1), UIColor(red: 0.45, green: 0.86, blue: 0.73, alpha: 1))
        case .cleanLedger:
            (UIColor(red: 0.06, green: 0.37, blue: 0.68, alpha: 1), UIColor(red: 0.46, green: 0.75, blue: 1.00, alpha: 1))
        case .softPastel:
            (UIColor(red: 0.62, green: 0.25, blue: 0.48, alpha: 1), UIColor(red: 0.98, green: 0.64, blue: 0.84, alpha: 1))
        case .editorial:
            (UIColor(red: 0.62, green: 0.20, blue: 0.13, alpha: 1), UIColor(red: 1.00, green: 0.66, blue: 0.48, alpha: 1))
        case .nightInk:
            (UIColor(red: 0.23, green: 0.34, blue: 0.70, alpha: 1), UIColor(red: 0.58, green: 0.74, blue: 1.00, alpha: 1))
        }
    }

    private var surfaceColors: (light: UIColor, dark: UIColor) {
        switch self {
        case .paperGlass:
            (UIColor(red: 1.00, green: 0.99, blue: 0.96, alpha: 1), UIColor(red: 0.12, green: 0.12, blue: 0.10, alpha: 1))
        case .cleanLedger:
            (UIColor(red: 0.98, green: 0.995, blue: 1.00, alpha: 1), UIColor(red: 0.08, green: 0.13, blue: 0.19, alpha: 1))
        case .softPastel:
            (UIColor(red: 1.00, green: 0.97, blue: 0.99, alpha: 1), UIColor(red: 0.16, green: 0.10, blue: 0.16, alpha: 1))
        case .editorial:
            (UIColor(red: 1.00, green: 0.98, blue: 0.94, alpha: 1), UIColor(red: 0.18, green: 0.12, blue: 0.09, alpha: 1))
        case .nightInk:
            (UIColor(red: 0.97, green: 0.98, blue: 1.00, alpha: 1), UIColor(red: 0.10, green: 0.13, blue: 0.21, alpha: 1))
        }
    }

    private var backdropColors: (
        light: (UIColor, UIColor),
        dark: (UIColor, UIColor)
    ) {
        switch self {
        case .paperGlass:
            (
                (UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 1), UIColor(red: 0.87, green: 0.93, blue: 0.88, alpha: 1)),
                (UIColor(red: 0.11, green: 0.10, blue: 0.08, alpha: 1), UIColor(red: 0.08, green: 0.14, blue: 0.12, alpha: 1))
            )
        case .cleanLedger:
            (
                (UIColor(red: 0.91, green: 0.96, blue: 0.99, alpha: 1), UIColor(red: 0.82, green: 0.91, blue: 0.96, alpha: 1)),
                (UIColor(red: 0.04, green: 0.10, blue: 0.17, alpha: 1), UIColor(red: 0.06, green: 0.16, blue: 0.24, alpha: 1))
            )
        case .softPastel:
            (
                (UIColor(red: 0.98, green: 0.90, blue: 0.94, alpha: 1), UIColor(red: 0.90, green: 0.92, blue: 0.99, alpha: 1)),
                (UIColor(red: 0.18, green: 0.08, blue: 0.14, alpha: 1), UIColor(red: 0.10, green: 0.11, blue: 0.22, alpha: 1))
            )
        case .editorial:
            (
                (UIColor(red: 0.96, green: 0.92, blue: 0.85, alpha: 1), UIColor(red: 0.92, green: 0.84, blue: 0.76, alpha: 1)),
                (UIColor(red: 0.17, green: 0.10, blue: 0.07, alpha: 1), UIColor(red: 0.23, green: 0.12, blue: 0.09, alpha: 1))
            )
        case .nightInk:
            (
                (UIColor(red: 0.92, green: 0.94, blue: 0.99, alpha: 1), UIColor(red: 0.79, green: 0.85, blue: 0.96, alpha: 1)),
                (UIColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1), UIColor(red: 0.12, green: 0.17, blue: 0.28, alpha: 1))
            )
        }
    }
}

private func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
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
