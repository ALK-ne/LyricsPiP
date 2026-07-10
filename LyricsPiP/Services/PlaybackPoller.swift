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
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    private var basePositionMs: Int = 0
    private var basePollDate: Date = Date()

    private let pollInterval: TimeInterval = 5.0
    private let tickInterval: TimeInterval = 0.2

    private static let blockedUntilKey = "spotify_poll_blocked_until"

    init(sessionClient: SpotifyWebSessionClient) {
        self.sessionClient = sessionClient
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
                    DebugLog.shared.log("[Poll] 保存済みのレート制限中。あと\(Int(remaining))秒はリクエストを送りません")
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
        let elapsedMs = Int(Date().timeIntervalSince(basePollDate) * 1000)
        estimatedPositionMs = basePositionMs + elapsedMs
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
            DebugLog.shared.log("[Poll] 未ログインのためスキップ")
            return nil
        }
        do {
            let token = try await sessionClient.validAccessToken()
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                DebugLog.shared.log("[Poll] 応答がHTTPURLResponseでない")
                return nil
            }

            DebugLog.shared.log("[Poll] currently-playing 応答: HTTP \(http.statusCode)")

            if http.statusCode == 429 {
                let retryAfterHeader = http.value(forHTTPHeaderField: "Retry-After")
                let retrySeconds = retryAfterHeader.flatMap(Double.init) ?? 30
                let delay = max(retrySeconds, pollInterval)
                DebugLog.shared.log("[Poll] 429レート制限。\(Int(delay))秒待って再試行します")
                return delay
            }

            if http.statusCode == 204 {
                DebugLog.shared.log("[Poll] 204: 再生中の曲なし")
                currentTrack = nil
                isPlaying = false
                return nil
            }
            guard http.statusCode == 200 else {
                let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "(バイナリ/デコード不可)"
                DebugLog.shared.log("[Poll] エラー応答本文: \(bodyPreview)")
                return nil
            }

            let decoded = try JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data)
            guard let item = decoded.item else {
                DebugLog.shared.log("[Poll] itemがnull(再生停止中?)")
                currentTrack = nil
                isPlaying = false
                return nil
            }

            let track = CurrentTrack(
                id: item.id,
                name: item.name,
                artist: item.artists.first?.name ?? "",
                album: item.album.name,
                durationMs: item.durationMs
            )
            if track != currentTrack {
                DebugLog.shared.log("[Poll] 曲検知: \(track.name) / \(track.artist)")
                currentTrack = track
            }
            isPlaying = decoded.isPlaying
            basePositionMs = decoded.progressMs ?? 0
            basePollDate = Date()
            estimatedPositionMs = basePositionMs
            return nil
        } catch {
            // Transient network/auth failure — the next poll cycle retries.
            // A persistent failure surfaces via sessionClient.lastError (cookie invalidated).
            DebugLog.shared.log("[Poll] 例外: \(error.localizedDescription)")
            return nil
        }
    }
}

private struct CurrentlyPlayingResponse: Decodable {
    let progressMs: Int?
    let isPlaying: Bool
    let item: Item?

    struct Item: Decodable {
        let id: String
        let name: String
        let durationMs: Int
        let artists: [Artist]
        let album: Album

        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let name: String }

        enum CodingKeys: String, CodingKey {
            case id, name, artists, album
            case durationMs = "duration_ms"
        }
    }

    enum CodingKeys: String, CodingKey {
        case progressMs = "progress_ms"
        case isPlaying = "is_playing"
        case item
    }
}
