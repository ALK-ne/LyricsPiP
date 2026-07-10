import Foundation

/// Narrow seam over URLSession so the token/polling/lyrics flows can be
/// exercised in unit tests with canned responses. Implementations must
/// return an `HTTPURLResponse`; a non-HTTP response is a transport error
/// the implementation should throw, which also centralizes the
/// "response as? HTTPURLResponse" check previously repeated at call sites.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
