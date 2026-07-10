import Foundation
import LyricsPiPCore

/// Fetches time-synced lyrics from lrclib.net's free public API.
/// Chosen over Spotify's private internal lyrics endpoint since it doesn't
/// require any Spotify auth at all and carries much lower ToS/stability risk.
struct LyricsService {
    let httpClient: any HTTPClient

    init(httpClient: any HTTPClient = URLSessionHTTPClient.shared) {
        self.httpClient = httpClient
    }

    func fetchSyncedLyrics(artist: String, track: String, album: String, durationMs: Int) async throws -> [LyricLine]? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(durationMs / 1000))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("LyricsPiP (personal use)", forHTTPHeaderField: "User-Agent")

        let (data, http) = try await httpClient.data(for: request)

        if http.statusCode == 404 {
            return nil
        }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(LrclibTrack.self, from: data)
        return decoded.syncedLines
    }
}
