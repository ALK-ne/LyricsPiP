import Foundation

/// Response of Spotify's internal `color-lyrics/v2/track/<id>` endpoint — the
/// same synced lyrics the Spotify app itself shows (Musixmatch/syncpower
/// sourced). Keyed purely by track id, so it needs no artist/album/duration
/// matching and its coverage tracks the user's actual Spotify library.
public struct SpotifyColorLyrics: Decodable, Equatable, Sendable {
    public let lyrics: Lyrics?

    public struct Lyrics: Decodable, Equatable, Sendable {
        public let syncType: String?
        public let lines: [Line]?

        public struct Line: Decodable, Equatable, Sendable {
            public let startTimeMs: String?
            public let words: String?
        }
    }

    /// Parsed synced lines, or nil when the track isn't line-synced (Spotify
    /// also returns `UNSYNCED` plain text for some tracks, which can't drive
    /// the timed display).
    public var syncedLines: [LyricLine]? {
        guard lyrics?.syncType == "LINE_SYNCED", let lines = lyrics?.lines else { return nil }
        let parsed = lines.compactMap { line -> LyricLine? in
            guard let ms = line.startTimeMs.flatMap(Double.init) else { return nil }
            return LyricLine(time: ms / 1000, text: line.words ?? "")
        }
        return parsed.isEmpty ? nil : parsed
    }
}
