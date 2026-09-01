import Foundation

public struct MoneyAmount: Codable, Equatable, Hashable, Sendable {
    public let minorUnits: Int64
    public let currencyCode: String

    public init(minorUnits: Int64, currencyCode: String) throws {
        let code = currencyCode.uppercased()
        guard code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            throw MoneyError.invalidCurrencyCode(currencyCode)
        }
        self.minorUnits = minorUnits
        self.currencyCode = code
    }

    public var decimalValue: Decimal {
        Decimal(minorUnits) / Decimal(Self.scale(for: currencyCode))
    }

    public func formatted(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        formatter.minimumFractionDigits = Self.fractionDigits(for: currencyCode)
        formatter.maximumFractionDigits = Self.fractionDigits(for: currencyCode)
        return formatter.string(from: decimalValue as NSDecimalNumber)
            ?? "\(currencyCode) \(decimalValue)"
    }

    public static func parse(
        _ input: String,
        currencyCode: String,
        locale: Locale = .current
    ) throws -> MoneyAmount {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let decimal = Decimal(string: trimmed, locale: locale)
        else { throw MoneyError.invalidAmount(input) }

        let code = currencyCode.uppercased()
        let scaled = decimal * Decimal(scale(for: code))
        var source = scaled
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        guard rounded == scaled else { throw MoneyError.tooManyFractionDigits }

        let number = NSDecimalNumber(decimal: rounded)
        let minimum = NSDecimalNumber(value: Int64.min)
        let maximum = NSDecimalNumber(value: Int64.max)
        guard number.compare(minimum) != .orderedAscending,
              number.compare(maximum) != .orderedDescending
        else { throw MoneyError.outOfRange }

        return try MoneyAmount(minorUnits: number.int64Value, currencyCode: code)
    }

    public static func fractionDigits(for currencyCode: String) -> Int {
        switch currencyCode.uppercased() {
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND": 3
        case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG",
             "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF": 0
        default: 2
        }
    }

    private static func scale(for currencyCode: String) -> Int64 {
        switch fractionDigits(for: currencyCode) {
        case 0: 1
        case 3: 1_000
        default: 100
        }
    }
}

public enum MoneyError: Error, Equatable, Sendable {
    case invalidCurrencyCode(String)
    case invalidAmount(String)
    case tooManyFractionDigits
    case outOfRange
}
