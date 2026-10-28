import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TradeLogCore

/// USD -> MYR rates from Bank Negara Malaysia's Open API (keyless).
///
/// - Day endpoint: `GET /public/exchange-rate/USD/date/yyyy-MM-dd?session=1700&quote=rm`
///   with `Accept: application/vnd.BNM.API.v1+json`. `middle_rate` is used, falling back to
///   `selling_rate`, then `buying_rate`.
/// - Weekends / holidays answer 404 (or an empty `data`): the provider walks back day by day for up
///   to 7 days.
/// - Month endpoint: `GET /public/exchange-rate/USD/year/{y}/month/{m}` is used by `rates(for:)` to
///   batch-fetch. Its exact JSON shape is not certain to us, so the parser accepts any structure
///   (array or object) in which objects carry a `date` plus rate fields, and silently falls back to
///   per-day requests if the month fetch fails or yields nothing.
/// - Day keys are `yyyy-MM-dd` in Asia/Kuala_Lumpur.
public actor BNMRateProvider: FXRateProvider {
    public static let timeZoneID = "Asia/Kuala_Lumpur"
    static let maxLookbackDays = 7
    static let baseURL = "https://api.bnm.gov.my/public/exchange-rate/USD"
    static let acceptHeader = "application/vnd.BNM.API.v1+json"

    private let http: HTTPClient
    private var cache: [String: Decimal] = [:]
    private var missing: Set<String> = []
    private var fetchedMonths: Set<String> = []

    public init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    // MARK: Day keys

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// `yyyy-MM-dd` of the date in Kuala Lumpur.
    public static func dayKey(for date: Date) -> String {
        let c = calendar().dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar().date(from: components)
    }

    static func previousDayKey(_ key: String) -> String? {
        guard let date = date(fromDayKey: key), let previous = calendar().date(byAdding: .day, value: -1, to: date) else { return nil }
        return dayKey(for: previous)
    }

    // MARK: FXRateProvider

    public func usdToMYR(on date: Date) async throws -> Decimal {
        let key = Self.dayKey(for: date)
        if let rate = try await resolve(dayKey: key) { return rate }
        throw IntegrationError.http(status: 404, body: "No BNM USD/MYR rate within \(Self.maxLookbackDays) days before \(key)")
    }

    /// Rates for many days (missing days resolve to the latest earlier rate). Failures are skipped.
    public func rates(for dayKeys: Set<String>) async -> [String: Decimal] {
        let months = Set(dayKeys.compactMap { key -> String? in
            let parts = key.split(separator: "-")
            guard parts.count == 3 else { return nil }
            return "\(parts[0])-\(parts[1])"
        })
        for month in months.sorted() {
            await prefetchMonth(month)
        }
        var result: [String: Decimal] = [:]
        for key in dayKeys.sorted() {
            if let rate = try? await resolve(dayKey: key) {
                result[key] = rate
            }
        }
        return result
    }

    // MARK: Resolution

    private func resolve(dayKey: String) async throws -> Decimal? {
        if let cached = cache[dayKey] { return cached }
        var key = dayKey
        for _ in 0...Self.maxLookbackDays {
            if let cached = cache[key] {
                cache[dayKey] = cached
                return cached
            }
            if !missing.contains(key) {
                if let rate = try await fetchDay(key) {
                    cache[key] = rate
                    cache[dayKey] = rate
                    return rate
                }
                missing.insert(key)
            }
            guard let previous = Self.previousDayKey(key) else { break }
            key = previous
        }
        return nil
    }

    private func request(path: String) throws -> URLRequest {
        try RequestFactory.get("\(Self.baseURL)\(path)", headers: ["Accept": Self.acceptHeader])
    }

    /// nil when BNM has no rate for that day (404 / empty body).
    private func fetchDay(_ key: String) async throws -> Decimal? {
        let req = try request(path: "/date/\(key)?session=1700&quote=rm")
        let (data, response) = try await http.data(for: req)
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else {
            throw IntegrationError.http(status: response.statusCode, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
        let rates = Self.extractRates(from: data)
        return rates[key] ?? rates.values.first
    }

    private func prefetchMonth(_ monthKey: String) async {
        if fetchedMonths.contains(monthKey) { return }
        let parts = monthKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        do {
            let req = try request(path: "/year/\(parts[0])/month/\(parts[1])?session=1700&quote=rm")
            let (data, response) = try await http.data(for: req)
            guard (200..<300).contains(response.statusCode) else { return }
            let rates = Self.extractRates(from: data)
            guard !rates.isEmpty else { return }
            for (key, rate) in rates { cache[key] = rate }
            fetchedMonths.insert(monthKey)
            // Days of that month without a rate (and already past) are weekends / holidays.
            let today = Self.dayKey(for: Date())
            if let first = Self.date(fromDayKey: "\(monthKey)-01"),
               let days = Self.calendar().range(of: .day, in: .month, for: first) {
                for day in days {
                    let key = monthKey + "-" + String(format: "%02d", day)
                    if cache[key] == nil, key < today { missing.insert(key) }
                }
            }
        } catch {
            return // fall back to per-day requests
        }
    }

    // MARK: JSON

    /// Collects `date -> rate` from every JSON object that has a `date` and a rate field.
    static func extractRates(from data: Data) -> [String: Decimal] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        var result: [String: Decimal] = [:]
        collect(json, into: &result)
        return result
    }

    private static func collect(_ node: Any, into result: inout [String: Decimal]) {
        if let dict = node as? [String: Any] {
            if let date = dict["date"] as? String, let rate = pickRate(dict) {
                result[String(date.prefix(10))] = rate
            }
            for value in dict.values { collect(value, into: &result) }
        } else if let array = node as? [Any] {
            for element in array { collect(element, into: &result) }
        }
    }

    private static func pickRate(_ dict: [String: Any]) -> Decimal? {
        for key in ["middle_rate", "selling_rate", "buying_rate"] {
            if let value = decimal(dict[key]), value > 0 { return value }
        }
        return nil
    }

    private static func decimal(_ any: Any?) -> Decimal? {
        guard let any = any else { return nil }
        if let d = any as? Double { return IntegrationParsing.decimal(fromJSONNumber: d) }
        if let i = any as? Int { return Decimal(i) }
        if let s = any as? String { return Decimal(string: s) }
        if let n = any as? NSNumber { return IntegrationParsing.decimal(fromJSONNumber: n.doubleValue) }
        return nil
    }
}
