import Foundation
import Combine
import LyricsPiPCore

/// Combines the currently-playing track/position from `PlaybackWatcher` with
/// lyrics fetched from `LyricsService` to expose "which line is active right now".
@MainActor
final class LyricsSyncEngine: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var activeIndex: Int?
    @Published private(set) var noLyricsFound: Bool = false

    private let lyricsService: LyricsService
    private let logger: any LyricsPiPLogging
    private var cancellables = Set<AnyCancellable>()
    private var currentTrackId: String?
    private var fetchTask: Task<Void, Never>?

    init(
        watcher: PlaybackWatcher,
        lyricsService: LyricsService? = nil,
        logger: (any LyricsPiPLogging)? = nil
    ) {
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
            currentTrackId = nil
            lines = []
            activeIndex = nil
            noLyricsFound = false
            return
        }
        guard track.id != currentTrackId else { return }

        // Moving to a different track — drop the previous lyrics right away.
        lines = []
        activeIndex = nil
        noLyricsFound = false

        // lrclib needs a real artist + title. Rapid skips (and reconnect churn)
        // can surface a track before its artist_name hydrates into the cluster;
        // fetching then would 400 and lock in a "no lyrics" result. Defer until
        // a fuller update arrives — leaving currentTrackId uncommitted so that
        // update (or a return to this track) still triggers the fetch.
        guard !track.artist.isEmpty else {
            currentTrackId = nil
            return
        }

        currentTrackId = track.id
        logger.log("[Lyrics] 取得開始: \(track.name) / \(track.artist)")
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await self.lyricsService.fetchSyncedLyrics(
                    artist: track.artist,
                    track: track.name,
                    album: track.album,
                    durationMs: track.durationMs
                )
                guard !Task.isCancelled, track.id == self.currentTrackId else { return }
                if let fetched, !fetched.isEmpty {
                    self.logger.log("[Lyrics] 取得成功: \(fetched.count)行")
                    self.lines = fetched
                } else {
                    self.logger.log("[Lyrics] 同期歌詞なし")
                    self.noLyricsFound = true
                }
            } catch {
                guard !Task.isCancelled, track.id == self.currentTrackId else { return }
                self.logger.log("[Lyrics] 取得失敗: \(error.localizedDescription)")
                self.noLyricsFound = true
            }
        }
    }

    private func updateActiveIndex(positionMs: Int) {
        activeIndex = ActiveLineFinder.activeIndex(in: lines, positionMs: positionMs)
    }
}
