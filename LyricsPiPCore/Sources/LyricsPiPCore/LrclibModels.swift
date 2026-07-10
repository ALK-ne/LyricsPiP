import Foundation

/// Response of lrclib.net `/api/get`.
public struct LrclibTrack: Decodable, Equatable, Sendable {
    public let syncedLyrics: String?
    public let plainLyrics: String?

    public init(syncedLyrics: String?, plainLyrics: String?) {
        self.syncedLyrics = syncedLyrics
        self.plainLyrics = plainLyrics
    }

    /// Parsed synced lines, or nil when the track has no synced lyrics
    /// (plain-only lyrics can't be time-synced, so they're not used).
    public var syncedLines: [LyricLine]? {
        guard let syncedLyrics, !syncedLyrics.isEmpty else { return nil }
        return LRCParser.parse(syncedLyrics)
    }
}
