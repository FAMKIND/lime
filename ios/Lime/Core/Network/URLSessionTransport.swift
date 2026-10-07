import Foundation

/// LimeCore's network, on iOS: the core decides what to call (the protocol lives in Rust) and this
/// makes the HTTPS request with `URLSession`, so iOS networking (proxies, and background sessions
/// later) is used. Calls are blocking, as LimeCore expects, so they must be made from a background
/// thread (the app calls LimeCore from `Task.detached`).
///
/// `baseURL` is the Supabase project URL; `apiKey` is its public (anon or publishable) key, which
/// is meant to ship in an app and goes in the `apikey` header. The user's token comes from LimeCore
/// per call. The service-role key never belongs here.
final class URLSessionTransport: Transport, @unchecked Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func request(method: String, path: String, headers: [HeaderPair], body: Data) throws -> TransportResponse {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw TransportError.Failed }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        for header in headers { request.setValue(header.value, forHTTPHeaderField: header.name) }
        if !body.isEmpty { request.httpBody = body }

        // Block this (background) thread until the response arrives.
        nonisolated(unsafe) var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            result = (data, response, error)
            done.signal()
        }
        task.resume()
        done.wait()

        guard result.2 == nil, let http = result.1 as? HTTPURLResponse else {
            #if DEBUG
            NetworkLog.record(method: method, path: path, status: 0)
            #endif
            throw TransportError.Failed
        }
        #if DEBUG
        NetworkLog.record(method: method, path: path, status: http.statusCode)
        #endif
        return TransportResponse(status: UInt16(clamping: http.statusCode), body: result.0 ?? Data())
    }
}
