import Foundation

/// Response of `open.spotify.com/api/token` (web-player session token).
public struct SpotifyAccessToken: Decodable, Equatable, Sendable {
    public let clientId: String
    public let accessToken: String
    public let accessTokenExpirationTimestampMs: Int
    /// `true` is the only reliable signal that the sp_dc cookie itself is
    /// invalid — every other failure mode (429/WAF/outage) must be treated
    /// as transient. See SpotifyWebSessionClient.
    public let isAnonymous: Bool

    public var expirationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(accessTokenExpirationTimestampMs) / 1000)
    }
}

/// Response of `api.spotify.com/v1/me/player/currently-playing`.
public struct SpotifyCurrentlyPlaying: Decodable, Equatable, Sendable {
    public let progressMs: Int?
    public let isPlaying: Bool
    public let item: Item?

    public struct Item: Decodable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let durationMs: Int
        public let artists: [Artist]
        public let album: Album

        public struct Artist: Decodable, Equatable, Sendable {
            public let name: String
        }

        public struct Album: Decodable, Equatable, Sendable {
            public let name: String
        }

        enum CodingKeys: String, CodingKey {
            case id, name, artists, album
            case durationMs = "duration_ms"
        }
    }

    /// The playing track as the app's model type, or nil when nothing is playing.
    public var currentTrack: CurrentTrack? {
        item.map {
            CurrentTrack(
                id: $0.id,
                name: $0.name,
                artist: $0.artists.first?.name ?? "",
                album: $0.album.name,
                durationMs: $0.durationMs
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case progressMs = "progress_ms"
        case isPlaying = "is_playing"
        case item
    }
}
