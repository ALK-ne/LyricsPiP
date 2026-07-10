import Foundation
import LyricsPiPCore

/// Production `HTTPClient` backed by `URLSession.shared`. Centralizes the
/// "response must be an HTTPURLResponse" check that used to be repeated at
/// every call site.
struct URLSessionHTTPClient: HTTPClient {
    static let shared = URLSessionHTTPClient()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
