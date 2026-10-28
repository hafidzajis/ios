import Foundation
import TradeLogCore

enum Fmt {
    static func number(_ value: Double?, digits: Int = 2) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func decimal(_ value: Decimal?, digits: Int = 2) -> String {
        guard let value else { return "—" }
        return value.doubleValue.formatted(.number.precision(.fractionLength(digits)))
    }

    /// Prices/quantities: up to 8 fraction digits, trailing zeros trimmed.
    static func plain(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return value.doubleValue.formatted(.number.precision(.fractionLength(0 ... 8)).grouping(.never))
    }

    static func percent(_ fraction: Double?, digits: Int = 1) -> String {
        guard let fraction, fraction.isFinite else { return "—" }
        return (fraction * 100).formatted(.number.precision(.fractionLength(digits))) + "%"
    }

    static func r(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let d = value.doubleValue
        return (d >= 0 ? "+" : "") + d.formatted(.number.precision(.fractionLength(2))) + "R"
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "—"
    }
}

extension BreakdownDimension {
    var title: String {
        switch self {
        case .setup: return "Setup"
        case .tag: return "Tag"
        case .symbol: return "Symbol"
        case .assetClass: return "Asset class"
        case .weekday: return "Weekday"
        case .hourOfDay: return "Hour"
        case .emotion: return "Emotion"
        case .followedPlan: return "Followed plan"
        }
    }
}

extension TaxMethod {
    var title: String { self == .fifo ? "FIFO" : "Perp P&L" }
}
