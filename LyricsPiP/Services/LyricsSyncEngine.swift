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
    private var debugTimerTask: Task<Void, Never>?

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

    // MARK: - Debug/test-only helper

    /// Loads canned lyric lines and advances the active line on a local timer,
    /// bypassing Spotify/lrclib entirely. Exists only to verify the PIP surface
    /// (the highest-risk, least-verified part of the app) independently of
    /// Spotify's current-playing rate limit. Remove once PIP is confirmed
    /// working end-to-end with real data.
    func loadDebugLyrics() {
        fetchTask?.cancel()
        currentTrackId = "debug-track"
        noLyricsFound = false
        lines = [
            LyricLine(time: 0, text: "♪ デバッグ用ダミー歌詞 ♪"),
            LyricLine(time: 3, text: "1行目のテスト歌詞です"),
            LyricLine(time: 6, text: "2行目のテスト歌詞です"),
            LyricLine(time: 9, text: "PIPが正しく表示されていますか？"),
            LyricLine(time: 12, text: "Spotifyやホーム画面に切り替えてみてください"),
            LyricLine(time: 15, text: "戻ってきても表示され続けていますか？"),
            LyricLine(time: 18, text: "ここまで来たら成功です ♪")
        ]
        activeIndex = 0

        debugTimerTask?.cancel()
        debugTimerTask = Task { [weak self] in
            var positionMs = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                positionMs += 1000
                guard let self else { return }
                self.activeIndex = ActiveLineFinder.activeIndex(in: self.lines, positionMs: positionMs)
                if positionMs > 20_000 {
                    positionMs = 0 // loop back to the start
                }
            }
        }
    }
}
