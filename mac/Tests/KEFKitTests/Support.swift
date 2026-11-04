import Foundation
@testable import KEFKit

/// Lecture d'une fixture JSON (réponses réelles relevées sur la LS50 Wireless II).
func fixture(_ name: String) throws -> JSONValue {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw KEFError.invalidResponse("fixture \(name) absente")
    }
    return try JSONValue.parse(Data(contentsOf: url))
}

func fixtureData(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw KEFError.invalidResponse("fixture \(name) absente")
    }
    return try Data(contentsOf: url)
}

/// Faux transport HTTP : intercepte les requêtes de `KEFHTTPClient` (aucun accès réseau).
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var logs: [String: [URLRequest]] = [:]

    /// Chaque session de test a son propre identifiant (en-tête) pour pouvoir paralléliser.
    static func session(id: String, handler: @escaping Handler) -> URLSession {
        lock.withLock {
            handlers[id] = handler
            logs[id] = []
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-ID": id]
        return URLSession(configuration: config)
    }

    static func requests(id: String) -> [URLRequest] { lock.withLock { logs[id] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Test-ID") ?? ""
        var req = request
        // Le corps des POST arrive en flux : on le relit pour les assertions.
        if req.httpBody == nil, let stream = req.httpBodyStream {
            stream.open()
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(buffer, maxLength: 4096)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            buffer.deallocate()
            stream.close()
            req.httpBody = data
        }
        let handler: Handler? = Self.lock.withLock {
            Self.logs[id, default: []].append(req)
            return Self.handlers[id]
        }
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(req)
            let response = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// Valeur (décodée) d'un paramètre de requête.
    func query(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    var jsonBody: JSONValue? { httpBody.flatMap { try? JSONValue.parse($0) } }
}
