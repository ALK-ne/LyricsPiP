import Foundation
import LyricsPiPCore

enum SpotifySessionError: Error {
    /// No sp_dc cookie stored — the user needs to log in.
    case notLoggedIn
    /// Spotify explicitly reported the session as anonymous: the sp_dc
    /// cookie itself is dead and only a re-login can fix it. This is the
    /// only error that logs the user out.
    case cookieInvalidated
    /// Non-200 from Spotify (rate limiting, WAF, transient outage) — not
    /// proof the cookie is invalid, so callers just retry later.
    case serverError(statusCode: Int)
    /// The response body wasn't in the expected shape.
    case malformedResponse
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

    private let httpClient: any HTTPClient
    private let logger: any LyricsPiPLogging
    private let totpProvider: SpotifyTOTPProvider

    private var cachedAccessToken: String?
    private var accessTokenExpiration: Date?

    init(
        httpClient: any HTTPClient = URLSessionHTTPClient.shared,
        logger: (any LyricsPiPLogging)? = nil
    ) {
        self.httpClient = httpClient
        self.logger = logger ?? DebugLog.shared
        self.totpProvider = SpotifyTOTPProvider(httpClient: httpClient)
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

        // Spotify's web player requires a TOTP code alongside the sp_dc cookie
        // (added as an anti-scraping measure) — see SpotifyTOTP.swift. Mirror
        // the community-established retry pattern: try "transport" first,
        // fall back to "init" if that's rejected.
        do {
            return try await requestAccessToken(spDc: spDc, reason: "transport")
        } catch {
            return try await requestAccessToken(spDc: spDc, reason: "init")
        }
    }

    private func requestAccessToken(spDc: String, reason: String) async throws -> String {
        logger.log("[Session] トークン取得開始 (reason=\(reason))")

        let serverTime = await fetchServerTime()
        logger.log("[Session] サーバー時刻取得: \(serverTime)")

        let totp: SpotifyTOTPCode
        do {
            totp = try await totpProvider.currentCode(at: serverTime)
            logger.log("[Session] TOTP取得成功 (ver=\(totp.version))")
        } catch {
            logger.log("[Session] TOTP取得失敗: \(error.localizedDescription)")
            lastError = "TOTPシークレットの取得に失敗しました: \(error.localizedDescription)"
            throw error
        }

        var components = URLComponents(string: "https://open.spotify.com/api/token")!
        components.queryItems = [
            URLQueryItem(name: "reason", value: reason),
            URLQueryItem(name: "productType", value: "web-player"),
            URLQueryItem(name: "totp", value: totp.value),
            URLQueryItem(name: "totpServer", value: totp.value),
            URLQueryItem(name: "totpVer", value: String(totp.version))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("sp_dc=\(spDc)", forHTTPHeaderField: "Cookie")
        request.setValue(SpotifyWebConstants.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://open.spotify.com/", forHTTPHeaderField: "Referer")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await httpClient.data(for: request)
        } catch {
            // Transient network failure — keep the session as logged-in so the
            // next poll cycle retries automatically instead of bouncing the
            // user back to the login screen.
            logger.log("[Session] ネットワークエラー: \(error.localizedDescription)")
            lastError = "ネットワークエラー: \(error.localizedDescription)"
            throw error
        }

        logger.log("[Session] /api/token 応答: HTTP \(http.statusCode)")

        guard http.statusCode == 200 else {
            // Non-200 from Spotify (rate limiting, WAF, transient outage) is not
            // proof the cookie itself is invalid — don't log the user out for this.
            let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "(バイナリ/デコード不可)"
            logger.log("[Session] 応答本文: \(bodyPreview)")
            lastError = "Spotifyからエラー応答が返ってきました(HTTP \(http.statusCode))。しばらくして再試行します。"
            throw SpotifySessionError.serverError(statusCode: http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(SpotifyAccessToken.self, from: data) else {
            let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "(バイナリ/デコード不可)"
            logger.log("[Session] JSON解析失敗。応答本文: \(bodyPreview)")
            lastError = "応答の解析に失敗しました。しばらくして再試行します。"
            throw SpotifySessionError.malformedResponse
        }

        guard !decoded.isAnonymous else {
            // This is the only reliable signal that the sp_dc cookie itself is invalid.
            logger.log("[Session] isAnonymous=true → クッキー無効と判定")
            isLoggedIn = false
            lastError = "sp_dcクッキーが無効になりました。再ログインしてください。"
            throw SpotifySessionError.cookieInvalidated
        }

        logger.log("[Session] トークン取得成功")
        cachedAccessToken = decoded.accessToken
        accessTokenExpiration = decoded.expirationDate
        lastError = nil
        return decoded.accessToken
    }

    /// Uses Spotify's own edge time (via the HTTP Date header) rather than the
    /// device clock, since the TOTP check is time-sensitive and this avoids
    /// any local clock-skew issues entirely.
    private func fetchServerTime() async -> Int {
        var request = URLRequest(url: URL(string: "https://open.spotify.com/")!)
        request.httpMethod = "HEAD"
        request.setValue(SpotifyWebConstants.browserUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (_, http) = try? await httpClient.data(for: request),
              let dateString = http.value(forHTTPHeaderField: "Date") else {
            return Int(Date().timeIntervalSince1970)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(identifier: "GMT")

        guard let date = formatter.date(from: dateString) else {
            return Int(Date().timeIntervalSince1970)
        }
        return Int(date.timeIntervalSince1970)
    }
}
