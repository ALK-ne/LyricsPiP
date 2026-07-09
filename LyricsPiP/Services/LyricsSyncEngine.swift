import Foundation
import Combine

/// Combines the currently-playing track/position from `PlaybackPoller` with
/// lyrics fetched from `LyricsService` to expose "which line is active right now".
@MainActor
final class LyricsSyncEngine: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var activeIndex: Int?
    @Published private(set) var noLyricsFound: Bool = false

    private let lyricsService = LyricsService()
    private var cancellables = Set<AnyCancellable>()
    private var currentTrackId: String?
    private var fetchTask: Task<Void, Never>?

    init(poller: PlaybackPoller) {
        poller.$currentTrack
            .removeDuplicates()
            .sink { [weak self] track in
                self?.handleTrackChange(track)
            }
            .store(in: &cancellables)

        poller.$estimatedPositionMs
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
                    self.lines = fetched
                } else {
                    self.noLyricsFound = true
                }
            } catch {
                guard !Task.isCancelled, track.id == self.currentTrackId else { return }
                self.noLyricsFound = true
            }
        }
    }

    private func updateActiveIndex(positionMs: Int) {
        guard !lines.isEmpty else {
            activeIndex = nil
            return
        }
        let positionSeconds = TimeInterval(positionMs) / 1000

        // Find the last line whose timestamp is <= the current position.
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= positionSeconds {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        activeIndex = result
    }
}
