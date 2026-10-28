import Foundation
import SwiftData

@Model
final class Account {
    var uuid: UUID = UUID()
    var name: String = ""
    var broker: String = ""
    var connectorID: String?
    var baseCurrency: String = "USD"
    var startingCapital: Decimal = 0
    var notes: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Trade.account)
    var trades: [Trade]?

    @Relationship(deleteRule: .nullify, inverse: \Connection.account)
    var connections: [Connection]?

    init(name: String, broker: String = "", connectorID: String? = nil, startingCapital: Decimal = 0) {
        self.uuid = UUID()
        self.name = name
        self.broker = broker
        self.connectorID = connectorID
        self.startingCapital = startingCapital
        self.createdAt = Date()
    }
}
