import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TradeLogCore

// All providers return a dictionary keyed by the symbol exactly as the caller passed it.
// Prices from these public APIs arrive as JSON numbers (not strings), so they are converted with
// `IntegrationParsing.decimal(fromJSONNumber:)` (shortest round-trip text, no binary noise).

// MARK: - CoinGecko

/// Keyless CoinGecko `simple/price`. Trading symbols ("BTCUSDT", "BTC", "BTC-USD", "ETH/USD") are
/// mapped to CoinGecko ids through a built-in table of the largest coins; unknown symbols are skipped.
public struct CoinGeckoPriceProvider: PriceProvider {
    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    static let coinIDs: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "USDT": "tether", "BNB": "binancecoin", "SOL": "solana",
        "XRP": "ripple", "USDC": "usd-coin", "ADA": "cardano", "DOGE": "dogecoin", "TRX": "tron",
        "AVAX": "avalanche-2", "LINK": "chainlink", "DOT": "polkadot", "MATIC": "matic-network",
        "POL": "polygon-ecosystem-token", "LTC": "litecoin", "BCH": "bitcoin-cash", "SHIB": "shiba-inu",
        "UNI": "uniswap", "ATOM": "cosmos", "XLM": "stellar", "ETC": "ethereum-classic", "XMR": "monero",
        "NEAR": "near", "APT": "aptos", "ARB": "arbitrum", "OP": "optimism", "FIL": "filecoin",
        "ICP": "internet-computer", "INJ": "injective-protocol", "SUI": "sui", "TON": "the-open-network",
        "HBAR": "hedera-hashgraph", "AAVE": "aave", "MKR": "maker", "ALGO": "algorand", "VET": "vechain",
        "SAND": "the-sandbox", "MANA": "decentraland", "PEPE": "pepe", "WLD": "worldcoin-wld",
        "RUNE": "thorchain", "FTM": "fantom", "TAO": "bittensor", "IMX": "immutable-x", "GRT": "the-graph",
        "DAI": "dai", "LDO": "lido-dao", "CRV": "curve-dao-token",
    ]

    private static let quoteSuffixes = ["USDT", "USDC", "BUSD", "FDUSD", "PERP", "USD"]

    /// CoinGecko id for a trading symbol, or nil when unknown.
    public static func coinID(for symbol: String) -> String? {
        var s = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
        if let id = coinIDs[s] { return id }
        var changed = true
        while changed {
            changed = false
            for suffix in quoteSuffixes where s.hasSuffix(suffix) && s.count > suffix.count {
                s.removeLast(suffix.count)
                changed = true
                break
            }
            if let id = coinIDs[s] { return id }
        }
        return nil
    }

    public func quotes(for symbols: [String], assetClass: AssetClass) async throws -> [String: Quote] {
        var idForSymbol: [String: String] = [:]
        for symbol in symbols {
            if let id = Self.coinID(for: symbol) { idForSymbol[symbol] = id }
        }
        guard !idForSymbol.isEmpty else { return [:] }
        let ids = Set(idForSymbol.values).sorted().joined(separator: ",")
        let query = QueryString.build([("ids", ids), ("vs_currencies", "usd"), ("include_last_updated_at", "true")])
        let request = try RequestFactory.get("https://api.coingecko.com/api/v3/simple/price?\(query)", headers: ["Accept": "application/json"])
        let data = try await http.sendData(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.decoding("Unexpected CoinGecko response")
        }
        var result: [String: Quote] = [:]
        for (symbol, id) in idForSymbol {
            guard let entry = json[id] as? [String: Any], let usd = entry["usd"] as? Double,
                  let price = IntegrationParsing.decimal(fromJSONNumber: usd), price > 0 else { continue }
            var date = Date()
            if let ts = entry["last_updated_at"] as? Double { date = Date(timeIntervalSince1970: ts) }
            result[symbol] = Quote(symbol: symbol, price: price, date: date)
        }
        return result
    }
}

// MARK: - Binance public

/// Binance public ticker prices (no key). Spot via `api.binance.com`, perps via `fapi.binance.com`.
/// Symbols are normalised to Binance pairs: "BTC" / "BTC-USD" / "btcusdt" -> "BTCUSDT".
public struct BinancePublicPriceProvider: PriceProvider {
    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    private struct Ticker: Decodable {
        let symbol: String
        let price: String
    }

    private static let knownQuotes = ["USDT", "USDC", "BUSD", "FDUSD"]

    public static func binanceSymbol(for symbol: String) -> String {
        var s = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
        if s.hasSuffix("PERP") && s.count > 4 { s.removeLast(4) }
        if knownQuotes.contains(where: { s.hasSuffix($0) && s.count > $0.count }) { return s }
        if s.hasSuffix("USD") && s.count > 3 {
            s.removeLast(3)
            return s + "USDT"
        }
        return s + "USDT"
    }

    public func quotes(for symbols: [String], assetClass: AssetClass) async throws -> [String: Quote] {
        guard assetClass != .usStock, !symbols.isEmpty else { return [:] }
        var inputsForPair: [String: [String]] = [:]
        for symbol in symbols {
            inputsForPair[Self.binanceSymbol(for: symbol), default: []].append(symbol)
        }
        let pairs = inputsForPair.keys.sorted()
        let json = "[" + pairs.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let base = assetClass == .cryptoPerp ? "https://fapi.binance.com/fapi/v1/ticker/price" : "https://api.binance.com/api/v3/ticker/price"
        let request = try RequestFactory.get("\(base)?symbols=\(QueryString.encode(json))")
        let tickers = try await http.sendJSON(request, as: [Ticker].self)
        let now = Date()
        var result: [String: Quote] = [:]
        for ticker in tickers {
            guard let price = Decimal(string: ticker.price), price > 0, let inputs = inputsForPair[ticker.symbol] else { continue }
            for input in inputs {
                result[input] = Quote(symbol: input, price: price, date: now)
            }
        }
        return result
    }
}

// MARK: - Finnhub

/// Finnhub US stock quotes (free API key). One request per symbol; symbols with price 0 are skipped.
public struct FinnhubPriceProvider: PriceProvider {
    private let apiKey: String
    private let http: HTTPClient

    public init(apiKey: String, http: HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    private struct QuoteResponse: Decodable {
        let c: Double?
        let t: Double?
    }

    public func quotes(for symbols: [String], assetClass: AssetClass) async throws -> [String: Quote] {
        guard !symbols.isEmpty else { return [:] }
        var result: [String: Quote] = [:]
        var firstError: Error?
        for symbol in symbols {
            do {
                let query = QueryString.build([("symbol", symbol), ("token", apiKey)])
                let request = try RequestFactory.get("https://finnhub.io/api/v1/quote?\(query)")
                let response = try await http.sendJSON(request, as: QuoteResponse.self)
                guard let current = response.c, current != 0,
                      let price = IntegrationParsing.decimal(fromJSONNumber: current) else { continue }
                let date = (response.t ?? 0) > 0 ? Date(timeIntervalSince1970: response.t ?? 0) : Date()
                result[symbol] = Quote(symbol: symbol, price: price, date: date)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if result.isEmpty, let error = firstError { throw error }
        return result
    }
}

// MARK: - Composite

/// Routes US stocks to a stock provider (e.g. Finnhub) and crypto to a crypto provider (e.g. Binance
/// public) with a fallback (CoinGecko) for symbols the first crypto provider could not price.
public struct CompositePriceProvider: PriceProvider {
    private let stock: PriceProvider?
    private let crypto: PriceProvider
    private let cryptoFallback: PriceProvider

    public init(stock: PriceProvider?, crypto: PriceProvider, cryptoFallback: PriceProvider) {
        self.stock = stock
        self.crypto = crypto
        self.cryptoFallback = cryptoFallback
    }

    /// Default wiring: Finnhub (when a key is given) / Binance public / CoinGecko.
    public init(finnhubAPIKey: String?, http: HTTPClient = URLSessionHTTPClient()) {
        let key = finnhubAPIKey?.trimmingCharacters(in: .whitespaces) ?? ""
        self.init(
            stock: key.isEmpty ? nil : FinnhubPriceProvider(apiKey: key, http: http),
            crypto: BinancePublicPriceProvider(http: http),
            cryptoFallback: CoinGeckoPriceProvider(http: http)
        )
    }

    public func quotes(for symbols: [String], assetClass: AssetClass) async throws -> [String: Quote] {
        switch assetClass {
        case .usStock:
            guard let stock = stock else { return [:] }
            return try await stock.quotes(for: symbols, assetClass: assetClass)
        case .cryptoSpot, .cryptoPerp:
            var result: [String: Quote] = [:]
            var primaryError: Error?
            do {
                result = try await crypto.quotes(for: symbols, assetClass: assetClass)
            } catch {
                primaryError = error
            }
            let missing = symbols.filter { result[$0] == nil }
            if !missing.isEmpty {
                do {
                    let extra = try await cryptoFallback.quotes(for: missing, assetClass: assetClass)
                    for (symbol, quote) in extra { result[symbol] = quote }
                } catch {
                    if result.isEmpty { throw primaryError ?? error }
                }
            }
            return result
        }
    }
}
