import Foundation
import LyricsPiPCore

/// Polls Spotify's official `/me/player/currently-playing` Web API endpoint
/// (authenticated via the sp_dc-derived Bearer token from `SpotifyWebSessionClient`)
/// and interpolates playback position between polls for smoother lyric sync.
@MainActor
final class PlaybackPoller: ObservableObject {
    @Published private(set) var currentTrack: CurrentTrack?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var estimatedPositionMs: Int = 0
    /// Set while a Spotify-issued rate limit is being honored, even across
    /// app relaunches (see `blockedUntilKey`). ContentView surfaces this so
    /// the user isn't tempted to force-quit/reopen — which would otherwise
    /// fire an immediate fresh request and risk escalating the block further.
    @Published private(set) var rateLimitedUntil: Date?

    private let sessionClient: SpotifyWebSessionClient
    private let httpClient: any HTTPClient
    private let logger: any LyricsPiPLogging
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    private var interpolator = PlaybackPositionInterpolator()

    // Verified locally (tools/spotify-auth-repro.mjs) that this endpoint,
    // accessed via an sp_dc/TOTP-derived token, has a standing ~30-35s rate
    // limit regardless of wait time — not a one-off penalty. 40s stays safely
    // above that observed ceiling.
    private let pollInterval: TimeInterval = 40.0
    private let tickInterval: TimeInterval = 0.2

    private static let blockedUntilKey = "spotify_poll_blocked_until"

    init(
        sessionClient: SpotifyWebSessionClient,
        httpClient: any HTTPClient = URLSessionHTTPClient.shared,
        logger: (any LyricsPiPLogging)? = nil
    ) {
        self.sessionClient = sessionClient
        self.httpClient = httpClient
        self.logger = logger ?? DebugLog.shared
        rateLimitedUntil = Self.persistedBlockedUntil()
        start()
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let blockedUntil = Self.persistedBlockedUntil(), blockedUntil > Date() {
                    let remaining = blockedUntil.timeIntervalSince(Date())
                    self.rateLimitedUntil = blockedUntil
                    self.logger.log("[Poll] 保存済みのレート制限中。あと\(Int(remaining))秒はリクエストを送りません")
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    continue
                }

                let retryAfter = await self.pollOnce()
                if let retryAfter {
                    let until = Date().addingTimeInterval(retryAfter)
                    Self.setBlockedUntil(until)
                    self.rateLimitedUntil = until
                } else {
                    Self.setBlockedUntil(nil)
                    self.rateLimitedUntil = nil
                }
                let delay = retryAfter ?? self.pollInterval
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        tickTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.tickInterval * 1_000_000_000))
                self.tick()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        guard isPlaying else { return }
        estimatedPositionMs = interpolator.position(at: Date())
    }

    /// Persisted so a force-quit + relaunch during a rate-limit window
    /// doesn't fire an immediate fresh request against Spotify's servers
    /// (which is what escalated a handful of 429s into a 24-hour block).
    private static func persistedBlockedUntil() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: blockedUntilKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func setBlockedUntil(_ date: Date?) {
        if let date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: blockedUntilKey)
        } else {
            UserDefaults.standard.removeObject(forKey: blockedUntilKey)
        }
    }

    /// Returns a server-specified retry delay (from `Retry-After` on a 429)
    /// when the caller should wait longer than the normal poll interval.
    private func pollOnce() async -> TimeInterval? {
        guard sessionClient.isLoggedIn else {
            logger.log("[Poll] 未ログインのためスキップ")
            return nil
        }
        do {
            let token = try await sessionClient.validAccessToken()
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(SpotifyWebConstants.browserUserAgent, forHTTPHeaderField: "User-Agent")

            let (data, http) = try await httpClient.data(for: request)

            logger.log("[Poll] currently-playing 応答: HTTP \(http.statusCode)")

            if http.statusCode == 429 {
                let retryAfterHeader = http.value(forHTTPHeaderField: "Retry-After")
                let retrySeconds = retryAfterHeader.flatMap(Double.init) ?? 30
                let delay = max(retrySeconds, pollInterval)
                logger.log("[Poll] 429レート制限。\(Int(delay))秒待って再試行します")
                return delay
            }

            if http.statusCode == 204 {
                logger.log("[Poll] 204: 再生中の曲なし")
                currentTrack = nil
                isPlaying = false
                return nil
            }
            guard http.statusCode == 200 else {
                let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "(バイナリ/デコード不可)"
                logger.log("[Poll] エラー応答本文: \(bodyPreview)")
                return nil
            }

            let decoded = try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: data)
            guard let track = decoded.currentTrack else {
                logger.log("[Poll] itemがnull(再生停止中?)")
                currentTrack = nil
                isPlaying = false
                return nil
            }

            if track != currentTrack {
                logger.log("[Poll] 曲検知: \(track.name) / \(track.artist)")
                currentTrack = track
            }
            isPlaying = decoded.isPlaying
            interpolator.rebase(positionMs: decoded.progressMs ?? 0, at: Date())
            estimatedPositionMs = interpolator.basePositionMs
            return nil
        } catch {
            // Transient network/auth failure — the next poll cycle retries.
            // A persistent failure surfaces via sessionClient.lastError (cookie invalidated).
            logger.log("[Poll] 例外: \(error.localizedDescription)")
            return nil
        }
    }
}
