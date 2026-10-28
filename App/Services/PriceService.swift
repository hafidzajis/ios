import Foundation
import Observation
import TradeLogCore
import TradeLogIntegrations

@MainActor
@Observable
final class PriceService {
    /// Keyed by "assetClass:symbol", see `key(_:_:)`.
    private(set) var quotes: [String: Quote] = [:]
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?

    static func key(_ assetClass: AssetClass, _ symbol: String) -> String {
        "\(assetClass.rawValue):\(symbol.uppercased())"
    }

    func price(for trade: Trade) -> Decimal? {
        quotes[Self.key(trade.assetClass, trade.symbol)]?.price
    }

    /// Fetches quotes for the symbols of the given open trades.
    func refresh(openTrades: [Trade]) async {
        guard !isRefreshing else { return }
        var symbolsByClass: [AssetClass: Set<String>] = [:]
        for t in openTrades where t.isOpen && !t.isArchived {
            symbolsByClass[t.assetClass, default: []].insert(t.symbol.uppercased())
        }
        guard !symbolsByClass.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var errors: [String] = []

        for (assetClass, symbols) in symbolsByClass {
            let list = symbols.sorted()
            switch assetClass {
            case .usStock:
                guard let key = KeychainStore.get(account: KeychainStore.finnhubAccount), !key.isEmpty else {
                    errors.append("Add a Finnhub API key in Settings for stock prices.")
                    continue
                }
                do {
                    let result = try await FinnhubPriceProvider(apiKey: key).quotes(for: list, assetClass: .usStock)
                    store(result, assetClass: assetClass)
                } catch {
                    errors.append("Stocks: \(error.localizedDescription)")
                }
            case .cryptoSpot, .cryptoPerp:
                var missing = Set(list)
                do {
                    let result = try await BinancePublicPriceProvider().quotes(for: list, assetClass: assetClass)
                    store(result, assetClass: assetClass)
                    missing.subtract(result.keys.map { $0.uppercased() })
                } catch {
                    errors.append("Binance: \(error.localizedDescription)")
                }
                if !missing.isEmpty {
                    do {
                        let result = try await CoinGeckoPriceProvider().quotes(for: missing.sorted(), assetClass: assetClass)
                        store(result, assetClass: assetClass)
                    } catch {
                        errors.append("CoinGecko: \(error.localizedDescription)")
                    }
                }
            }
        }
        lastUpdated = Date()
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func store(_ result: [String: Quote], assetClass: AssetClass) {
        for (symbol, quote) in result {
            quotes[Self.key(assetClass, symbol)] = quote
        }
    }
}
