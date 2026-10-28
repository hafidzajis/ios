import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import TradeLogCore

// MARK: - HTTP client

/// `HTTPClient` backed by `URLSession`. Uses `dataTask` + continuation so it behaves identically
/// on Apple platforms and on Linux (swift-corelibs-foundation), where `data(for:)` may be missing.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: IntegrationError.decoding("Response was not an HTTP response"))
                    return
                }
                continuation.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }
}

// MARK: - Shared helpers

/// HMAC-SHA256 signing. (Named `HMACSigner` to avoid clashing with `HMAC<H>` from CryptoKit / swift-crypto.)
public enum HMACSigner {
    /// Lower-case hex HMAC-SHA256 of `message` keyed with the UTF-8 bytes of `secret`.
    public static func sha256Hex(message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return code.map { String(format: "%02x", $0) }.joined()
    }
}

/// Percent-encoded query-string building. Signed APIs sign the exact string that is sent, so the
/// same builder output is used both for the signature and for the URL.
public enum QueryString {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Keeps the given order (needed by exchanges whose documented examples sign in a fixed order).
    public static func build(_ items: [(String, String)]) -> String {
        items.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
    }

    /// Alphabetically sorted by key.
    public static func buildSorted(_ items: [String: String]) -> String {
        build(items.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }
}

public enum RequestFactory {
    public static func get(_ urlString: String, headers: [String: String] = [:], timeout: TimeInterval = 30) throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw IntegrationError.decoding("Invalid URL: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}

public extension HTTPClient {
    /// Sends the request and returns the body; throws `IntegrationError.http` on a non-2xx status.
    func sendData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await self.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw IntegrationError.http(status: response.statusCode, body: String(decoding: data.prefix(2000), as: UTF8.self))
        }
        return data
    }

    /// Sends the request and decodes a 2xx JSON body. Non-2xx -> `IntegrationError.http`,
    /// undecodable body -> `IntegrationError.decoding`.
    func sendJSON<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await sendData(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw IntegrationError.decoding("\(error)")
        }
    }
}

/// Number parsing helpers. Exchange payloads send money as JSON strings -> `Decimal(string:)`.
public enum IntegrationParsing {
    public static func decimal(_ string: String, field: String) throws -> Decimal {
        guard let value = Decimal(string: string.trimmingCharacters(in: .whitespaces)) else {
            throw IntegrationError.decoding("Invalid number '\(string)' for \(field)")
        }
        return value
    }

    /// Missing / empty / unparsable -> nil.
    public static func decimalOrNil(_ string: String?) -> Decimal? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty else { return nil }
        return Decimal(string: string)
    }

    /// For APIs that send prices as JSON *numbers* (CoinGecko, Finnhub, BNM). The shortest round-trip
    /// text of the Double is used, which avoids binary noise like 0.1000000000000000055.
    public static func decimal(fromJSONNumber value: Double) -> Decimal? {
        guard value.isFinite else { return nil }
        return Decimal(string: "\(value)")
    }

    public static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    public static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}

public enum DateParsing {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// ISO8601 with or without fractional seconds (any number of fraction digits).
    public static func iso8601(_ raw: String) -> Date? {
        let s = normalizeFraction(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        return fractionalFormatter.date(from: s) ?? plainFormatter.date(from: s)
    }

    public static func iso8601String(_ date: Date) -> String {
        plainFormatter.string(from: date)
    }

    /// Truncates / pads the fraction to exactly 3 digits (what ISO8601DateFormatter reliably parses).
    static func normalizeFraction(_ s: String) -> String {
        guard let dot = s.firstIndex(of: ".") else { return s }
        var end = s.index(after: dot)
        var digits = ""
        while end < s.endIndex, s[end].isASCII, s[end].isNumber {
            digits.append(s[end])
            end = s.index(after: end)
        }
        let three = String((digits + "000").prefix(3))
        return String(s[..<dot]) + "." + three + String(s[end...])
    }
}

/// Reads a comma-separated credential list like "BTCUSDT, ethusdt".
func commaSeparatedSymbols(_ raw: String?) -> [String] {
    guard let raw = raw else { return [] }
    var seen = Set<String>()
    var result: [String] = []
    for part in raw.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" }) {
        let symbol = part.trimmingCharacters(in: .whitespaces).uppercased()
        if !symbol.isEmpty, seen.insert(symbol).inserted {
            result.append(symbol)
        }
    }
    return result
}

/// Removes duplicates (by `ImportedExecution.id`) and sorts ascending by date.
func uniqueSorted(_ executions: [ImportedExecution]) -> [ImportedExecution] {
    var seen = Set<String>()
    var result: [ImportedExecution] = []
    for execution in executions where seen.insert(execution.id).inserted {
        result.append(execution)
    }
    return result.sorted { lhs, rhs in
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.externalID < rhs.externalID
    }
}
