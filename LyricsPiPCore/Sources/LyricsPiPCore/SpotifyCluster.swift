import Foundation

/// A parsed snapshot of Spotify playback state taken from the internal
/// connect-state "cluster" (the dealer WebSocket / spclient path that the
/// real web player uses).
///
/// This replaces the old public Web API `currently-playing` response: as of
/// Spotify's December 2025 change, the sp_dc/web-player token is rate-limited
/// to uselessness on every `api.spotify.com` endpoint (a single
/// `/me/player` call re-arms a 24h block), while the connect-state path stays
/// fully functional. See README "既知のリスク・制約".
public struct PlaybackSnapshot: Equatable, Sendable {
    public let track: CurrentTrack?
    public let positionMs: Int
    /// Epoch-ms server timestamp the position was measured at. Used to
    /// interpolate the true current position accounting for transit delay
    /// between Spotify capturing the state and us receiving it.
    public let timestampMs: Int64
    public let isPaused: Bool

    public init(track: CurrentTrack?, positionMs: Int, timestampMs: Int64, isPaused: Bool) {
        self.track = track
        self.positionMs = positionMs
        self.timestampMs = timestampMs
        self.isPaused = isPaused
    }
}

public enum TrackMetadataMerge {
    /// Chooses which track to keep when a new snapshot arrives.
    ///
    /// connect-state occasionally emits a *partial* cluster update for the
    /// track that's already playing, momentarily dropping `artist_name` (and
    /// in principle `title`) to empty. Without guarding, that blip would
    /// overwrite good metadata and flicker the UI. This keeps the existing
    /// track when the incoming one is the *same* track with emptier fields,
    /// and otherwise accepts the incoming track (new song, or a richer update
    /// that fills a field back in).
    public static func resolve(existing: CurrentTrack?, incoming: CurrentTrack?) -> CurrentTrack? {
        guard let incoming else { return nil }
        guard let existing, existing.id == incoming.id else { return incoming }
        if incoming.artist.isEmpty && !existing.artist.isEmpty { return existing }
        if incoming.name.isEmpty && !existing.name.isEmpty { return existing }
        return incoming
    }
}

public enum SpotifyClusterParser {
    /// Parses a connect-state cluster JSON body into a playback snapshot.
    /// Returns `nil` when there is no `player_state` at all (nothing loaded).
    public static func parse(_ data: Data) -> PlaybackSnapshot? {
        guard let cluster = try? JSONDecoder().decode(RawCluster.self, from: data) else { return nil }
        return snapshot(from: cluster)
    }

    public static func snapshot(from cluster: RawCluster) -> PlaybackSnapshot? {
        guard let ps = cluster.playerState else { return nil }

        let track: CurrentTrack? = {
            guard let raw = ps.track, let md = raw.metadata, let title = md.title else { return nil }
            // Spotify int64 fields are serialized as strings in this JSON.
            let durationMs = md.duration.flatMap { Int($0) } ?? ps.duration.flatMap { Int($0) } ?? 0
            let id = raw.uri?.components(separatedBy: ":").last ?? (raw.uri ?? "")
            return CurrentTrack(
                id: id,
                name: title,
                artist: md.artistName ?? "",
                album: md.albumTitle ?? "",
                durationMs: durationMs
            )
        }()

        return PlaybackSnapshot(
            track: track,
            positionMs: ps.positionAsOfTimestamp.flatMap { Int($0) } ?? 0,
            timestampMs: ps.timestamp.flatMap { Int64($0) } ?? 0,
            isPaused: ps.isPaused ?? false
        )
    }
}

// MARK: - Raw Decodable mirror of the connect-state cluster (only the fields we use)

public struct RawCluster: Decodable {
    public let playerState: PlayerState?

    enum CodingKeys: String, CodingKey {
        case playerState = "player_state"
    }

    public struct PlayerState: Decodable {
        public let timestamp: String?
        public let positionAsOfTimestamp: String?
        public let duration: String?
        public let isPaused: Bool?
        public let isPlaying: Bool?
        public let track: Track?

        enum CodingKeys: String, CodingKey {
            case timestamp
            case positionAsOfTimestamp = "position_as_of_timestamp"
            case duration
            case isPaused = "is_paused"
            case isPlaying = "is_playing"
            case track
        }
    }

    public struct Track: Decodable {
        public let uri: String?
        public let metadata: Metadata?
    }

    public struct Metadata: Decodable {
        public let title: String?
        public let artistName: String?
        public let albumTitle: String?
        public let duration: String?

        enum CodingKeys: String, CodingKey {
            case title
            case artistName = "artist_name"
            case albumTitle = "album_title"
            case duration
        }
    }
}
