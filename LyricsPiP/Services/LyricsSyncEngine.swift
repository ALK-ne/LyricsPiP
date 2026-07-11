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

        currentTrackId = track.id
        lines = []
        activeIndex = nil
        noLyricsFound = false

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
