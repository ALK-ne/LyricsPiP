import Foundation

/// Fetches time-synced lyrics from lrclib.net's free public API.
/// Chosen over Spotify's private internal lyrics endpoint since it doesn't
/// require any Spotify auth at all and carries much lower ToS/stability risk.
struct LyricsService {
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if http.statusCode == 404 {
            return nil
        }
        guard http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(LrclibTrack.self, from: data)
        guard let synced = decoded.syncedLyrics, !synced.isEmpty else { return nil }
        return LRCParser.parse(synced)
    }
}

private struct LrclibTrack: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?
}
