import Foundation
import SwiftData
import TradeLogCore

@Model
final class Fill {
    var uuid: UUID = UUID()
    var actionRaw: String = FillAction.open.rawValue
    var date: Date = Date()
    var price: Decimal = 0
    var quantity: Decimal = 0
    var fee: Decimal = 0
    /// "source:externalID" values (joined with "|") of imported executions, used to de-duplicate re-imports.
    var externalID: String?
    var trade: Trade?

    var action: FillAction {
        get { FillAction(rawValue: actionRaw) ?? .open }
        set { actionRaw = newValue.rawValue }
    }

    var externalIDs: [String] {
        (externalID ?? "").split(separator: "|").map(String.init)
    }

    init(uuid: UUID = UUID(), action: FillAction, date: Date, price: Decimal, quantity: Decimal, fee: Decimal = 0, externalID: String? = nil) {
        self.uuid = uuid
        self.actionRaw = action.rawValue
        self.date = date
        self.price = price
        self.quantity = quantity
        self.fee = fee
        self.externalID = externalID
    }
}
