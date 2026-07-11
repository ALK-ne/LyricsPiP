import Foundation
import Combine
import LyricsPiPCore

/// Combines the currently-playing track/position from `PlaybackWatcher` with
/// lyrics to expose "which line is active right now". Lyrics come from Spotify's
/// own synced lyrics first (keyed by track id, matches the Spotify app), falling
/// back to lrclib when Spotify has none.
@MainActor
final class LyricsSyncEngine: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var activeIndex: Int?
    @Published private(set) var noLyricsFound: Bool = false

    private let spotifyLyrics: SpotifyLyricsService
    private let lyricsService: LyricsService
    private let logger: any LyricsPiPLogging
    private var cancellables = Set<AnyCancellable>()
    /// The track id we've SUCCESSFULLY loaded lyrics for (nil while unresolved),
    /// so an artist-filled retry or a repeat event doesn't refetch needlessly.
    private var loadedTrackId: String?
    private var fetchTask: Task<Void, Never>?

    init(
        watcher: PlaybackWatcher,
        spotifyLyrics: SpotifyLyricsService,
        lyricsService: LyricsService? = nil,
        logger: (any LyricsPiPLogging)? = nil
    ) {
        self.spotifyLyrics = spotifyLyrics
        self.lyricsService = lyricsService ?? LyricsService()
        self.logger = logger ?? DebugLog.shared

        watcher.$currentTrack
            .removeDuplicates()
            .sink { [weak self] track in
                self?.handleTrackChange(track)
            }
            .store(in: &cancellables)

        watcher.$estimatedPositionMs
            .sink { [weak self] positionMs in
                self?.updateActiveIndex(positionMs: positionMs)
            }
            .store(in: &cancellables)
    }

    private func handleTrackChange(_ track: CurrentTrack?) {
        fetchTask?.cancel()

        guard let track else {
            loadedTrackId = nil
            lines = []
            activeIndex = nil
            noLyricsFound = false
            return
        }
        // Already have lyrics loaded for this exact track — nothing to do
        // (guards against the artist-filled retry event and repeat pushes).
        guard track.id != loadedTrackId else { return }

        // New/unresolved track — drop the previous lyrics right away.
        lines = []
        activeIndex = nil
        noLyricsFound = false

        fetchTask = Task { [weak self] in
            guard let self else { return }

            // 1. Spotify's own synced lyrics — keyed by track id, so no artist
            //    needed and coverage matches the Spotify app. Try this first.
            if let spotify = try? await self.spotifyLyrics.fetchSyncedLyrics(trackId: track.id),
               !spotify.isEmpty {
                guard !Task.isCancelled else { return }
                self.logger.log("[Lyrics] Spotify歌詞: \(spotify.count)行 (\(track.name))")
                self.lines = spotify
                self.loadedTrackId = track.id
                return
            }

            // 2. lrclib fallback — needs a real artist. During playlist playback
            //    artist_name arrives a beat later (resolved separately); if it's
            //    not here yet, stop and let the artist-filled update retry.
            guard !track.artist.isEmpty else {
                self.logger.log("[Lyrics] Spotify歌詞なし、アーティスト解決待ち: \(track.name)")
                return
            }
            do {
                let fetched = try await self.lyricsService.fetchSyncedLyrics(
                    artist: track.artist,
                    track: track.name,
                    album: track.album,
                    durationMs: track.durationMs
                )
                guard !Task.isCancelled else { return }
                if let fetched, !fetched.isEmpty {
                    self.logger.log("[Lyrics] lrclib歌詞: \(fetched.count)行 (\(track.name))")
                    self.lines = fetched
                    self.loadedTrackId = track.id
                } else {
                    self.logger.log("[Lyrics] 同期歌詞なし(Spotify/lrclib両方): \(track.name)")
                    self.noLyricsFound = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.logger.log("[Lyrics] lrclib取得失敗: \(error.localizedDescription)")
                self.noLyricsFound = true
            }
        }
    }

    private func updateActiveIndex(positionMs: Int) {
        activeIndex = ActiveLineFinder.activeIndex(in: lines, positionMs: positionMs)
    }
}
