import Foundation

/// Estimates the current playback position between Spotify playback updates
/// by extrapolating from the last known position. Updates arrive via the
/// dealer WebSocket / connect-state path (track changes push instantly; a
/// safety refresh runs every ~25s) while the lyric display ticks every 0.2s —
/// see PlaybackWatcher.
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
