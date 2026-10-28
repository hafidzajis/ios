import Foundation
import TradeLogCore

/// All broker / exchange connectors the app can offer.
public enum ConnectorRegistry {
    public static let all: [any BrokerConnector.Type] = [
        BinanceConnector.self,
        BybitConnector.self,
        AlpacaConnector.self,
        IBKRFlexConnector.self,
    ]

    public static func type(for id: String) -> (any BrokerConnector.Type)? {
        all.first { $0.connectorID == id }
    }
}
