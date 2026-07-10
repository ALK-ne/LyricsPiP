import Foundation

/// Estimates the current playback position between Spotify polls by
/// extrapolating from the last polled position (the currently-playing
/// endpoint has a standing ~30-35s rate limit, so polls are ~40s apart
/// while the lyric display ticks every 0.2s — see PlaybackPoller).
public struct PlaybackPositionInterpolator: Equatable, Sendable {
    public private(set) var basePositionMs: Int
    public private(set) var baseDate: Date

    public init(positionMs: Int = 0, at date: Date = Date()) {
        basePositionMs = positionMs
        baseDate = date
    }

    /// Re-anchors on a freshly polled position.
    public mutating func rebase(positionMs: Int, at date: Date = Date()) {
        basePositionMs = positionMs
        baseDate = date
    }

    public func position(at date: Date = Date()) -> Int {
        basePositionMs + Int(date.timeIntervalSince(baseDate) * 1000)
    }
}
