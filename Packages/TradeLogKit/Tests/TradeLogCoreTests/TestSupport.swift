import Foundation
@testable import TradeLogCore

func d(_ s: String) -> Decimal {
    return Decimal(string: s) ?? 0
}

func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0)
}

func fill(_ action: FillAction, _ iso: String, _ price: String, _ qty: String, fee: String = "0") -> FillInput {
    return FillInput(action: action, date: date(iso), price: d(price), quantity: d(qty), fee: d(fee))
}
