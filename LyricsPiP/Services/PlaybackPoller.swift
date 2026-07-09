import Foundation

/// Polls Spotify's official `/me/player/currently-playing` Web API endpoint
/// (authenticated via the sp_dc-derived Bearer token from `SpotifyWebSessionClient`)
/// and interpolates playback position between polls for smoother lyric sync.
@MainActor
final class PlaybackPoller: ObservableObject {
    @Published private(set) var currentTrack: CurrentTrack?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var estimatedPositionMs: Int = 0

    private let sessionClient: SpotifyWebSessionClient
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    private var basePositionMs: Int = 0
    private var basePollDate: Date = Date()

    private let pollInterval: TimeInterval = 2.5
    private let tickInterval: TimeInterval = 0.2

    init(sessionClient: SpotifyWebSessionClient) {
        self.sessionClient = sessionClient
        start()
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
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

    private func pollOnce() async {
        guard sessionClient.isLoggedIn else { return }
        do {
            let token = try await sessionClient.validAccessToken()
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 204 {
                currentTrack = nil
                isPlaying = false
                return
            }
            guard http.statusCode == 200 else { return }

            let decoded = try JSONDecoder().decode(CurrentlyPlayingResponse.self, from: data)
            guard let item = decoded.item else {
                currentTrack = nil
                isPlaying = false
                return
            }

            let track = CurrentTrack(
                id: item.id,
                name: item.name,
                artist: item.artists.first?.name ?? "",
                album: item.album.name,
                durationMs: item.durationMs
            )
            if track != currentTrack {
                currentTrack = track
            }
            isPlaying = decoded.isPlaying
            basePositionMs = decoded.progressMs ?? 0
            basePollDate = Date()
            estimatedPositionMs = basePositionMs
        } catch {
            // Transient network/auth failure — the next poll cycle retries.
            // A persistent failure surfaces via sessionClient.lastError (cookie invalidated).
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
