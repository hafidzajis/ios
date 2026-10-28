import Foundation

public extension Decimal {
    /// Lossy conversion for charts and percentages. Never use for money arithmetic.
    var doubleValue: Double {
        return NSDecimalNumber(decimal: self).doubleValue
    }

    /// Rounds half away from zero ("plain") to `scale` fraction digits.
    func rounded(scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }
}

public enum MoneyFormat {
    /// Formats a value as currency, e.g. "$1,234.50" for USD or "RM1,234.50" for MYR (locale en_US).
    public static func string(_ value: Decimal, currencyCode: String, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let number = NSDecimalNumber(decimal: value)
        if let text = formatter.string(from: number) {
            return text
        }
        return "\(currencyCode) \(value.rounded(scale: fractionDigits))"
    }

    /// Like `string` but always shows a sign: "+$10.00", "-$10.00", "$0.00".
    public static func signed(_ value: Decimal, currencyCode: String) -> String {
        let magnitude: Decimal = value < 0 ? -value : value
        let body = string(magnitude, currencyCode: currencyCode)
        if value > 0 { return "+" + body }
        if value < 0 { return "-" + body }
        return body
    }
}
