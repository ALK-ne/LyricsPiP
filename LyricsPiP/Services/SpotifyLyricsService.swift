import Foundation
import LyricsPiPCore

/// Fetches Spotify's own synced lyrics (the ones shown in the Spotify app) from
/// the internal `color-lyrics/v2/track/<id>` endpoint. Keyed purely by track id,
/// so it needs no artist/album matching — which sidesteps the playlist
/// missing-artist problem entirely and gives coverage matching the user's
/// Spotify library. Used as the primary source, with lrclib as fallback.
struct SpotifyLyricsService {
    let sessionClient: SpotifyWebSessionClient
    let httpClient: any HTTPClient

    init(sessionClient: SpotifyWebSessionClient, httpClient: any HTTPClient = URLSessionHTTPClient.shared) {
        self.sessionClient = sessionClient
        self.httpClient = httpClient
    }

    /// Returns synced lyric lines for the track, or nil when Spotify has no
    /// line-synced lyrics for it (404 or UNSYNCED).
    func fetchSyncedLyrics(trackId: String) async throws -> [LyricLine]? {
        let token = try await sessionClient.validAccessToken()
        let host = SpotifyWebConstants.defaultSpclientHost
        guard let url = URL(string: "https://\(host)/color-lyrics/v2/track/\(trackId)?format=json&vocalRemoval=false&market=from_token") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SpotifyWebConstants.browserUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, http) = try await httpClient.data(for: request)
        // 404 = no lyrics for this track; anything non-200 falls back to lrclib.
        guard http.statusCode == 200 else { return nil }

        let decoded = try JSONDecoder().decode(SpotifyColorLyrics.self, from: data)
        return decoded.syncedLines
    }
}
