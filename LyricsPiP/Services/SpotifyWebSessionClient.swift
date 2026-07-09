import Foundation

enum SpotifySessionError: Error {
    case notLoggedIn
    case cookieRejected
}

/// Holds the Spotify web session (`sp_dc` cookie) and turns it into short-lived
/// Bearer access tokens, mirroring what open.spotify.com's own web player does.
/// This intentionally bypasses the official Developer Dashboard / OAuth Client ID
/// flow, since that now requires the app owner to hold an active Premium
/// subscription (see project README for the full rationale and risks).
@MainActor
final class SpotifyWebSessionClient: ObservableObject {
    @Published private(set) var isLoggedIn: Bool
    @Published var lastError: String?

    private static let spDcKey = "spotify_sp_dc"

    private var cachedAccessToken: String?
    private var accessTokenExpiration: Date?

    init() {
        isLoggedIn = KeychainStore.get(forKey: Self.spDcKey) != nil
    }

    func saveSpDcCookie(_ value: String) {
        KeychainStore.set(value, forKey: Self.spDcKey)
        cachedAccessToken = nil
        accessTokenExpiration = nil
        isLoggedIn = true
        lastError = nil
    }

    func logout() {
        KeychainStore.remove(forKey: Self.spDcKey)
        cachedAccessToken = nil
        accessTokenExpiration = nil
        isLoggedIn = false
    }

    /// Returns a currently-valid Bearer token, refreshing via the stored
    /// sp_dc cookie if the cached one is missing or about to expire.
    func validAccessToken() async throws -> String {
        if let token = cachedAccessToken,
           let expiration = accessTokenExpiration,
           expiration > Date().addingTimeInterval(30) {
            return token
        }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        guard let spDc = KeychainStore.get(forKey: Self.spDcKey) else {
            isLoggedIn = false
            throw SpotifySessionError.notLoggedIn
        }

        var request = URLRequest(
            url: URL(string: "https://open.spotify.com/get_access_token?reason=transport&productType=web_player")!
        )
        request.setValue("sp_dc=\(spDc)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(AccessTokenResponse.self, from: data),
              !decoded.isAnonymous else {
            isLoggedIn = false
            lastError = "sp_dcクッキーが無効になりました。再ログインしてください。"
            throw SpotifySessionError.cookieRejected
        }

        cachedAccessToken = decoded.accessToken
        accessTokenExpiration = Date(
            timeIntervalSince1970: TimeInterval(decoded.accessTokenExpirationTimestampMs) / 1000
        )
        return decoded.accessToken
    }
}

private struct AccessTokenResponse: Decodable {
    let clientId: String
    let accessToken: String
    let accessTokenExpirationTimestampMs: Int
    let isAnonymous: Bool
}
