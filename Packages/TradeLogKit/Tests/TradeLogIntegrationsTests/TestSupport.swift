import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import TradeLogCore
import TradeLogIntegrations

/// Returns (status, body) for a request; throw to simulate a transport error.
typealias MockHandler = @Sendable (URLRequest) throws -> (Int, Data)

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private let handler: MockHandler
    private let lock = NSLock()
    private var recorded: [URLRequest] = []

    init(handler: @escaping MockHandler) {
        self.handler = handler
    }

    /// Serves fixture files by URL path (404 for unknown paths).
    convenience init(routes: [String: String]) {
        self.init { request in
            let path = request.url?.path ?? ""
            guard let name = routes[path] else { return (404, Data("{}".utf8)) }
            return (200, try Fixtures.load(name))
        }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private func record(_ request: URLRequest) {
        lock.lock()
        recorded.append(request)
        lock.unlock()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        let (status, body) = try handler(request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            throw IntegrationError.decoding("Cannot build mock response")
        }
        return (body, response)
    }
}

/// Thread-safe counter for handlers that answer differently on successive calls.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

enum Fixtures {
    static func load(_ name: String) throws -> Data {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") else {
            throw IntegrationError.decoding("Missing fixture \(name)")
        }
        return try Data(contentsOf: url)
    }

    static func string(_ name: String) throws -> String {
        String(decoding: try load(name), as: UTF8.self)
    }
}

func queryItems(_ request: URLRequest) -> [String: String] {
    guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
    var result: [String: String] = [:]
    for item in components.queryItems ?? [] {
        result[item.name] = item.value ?? ""
    }
    return result
}

func dec(_ string: String) -> Decimal {
    Decimal(string: string)!
}
