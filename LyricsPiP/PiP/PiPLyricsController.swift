import AVKit
import AVFoundation
import Combine
import CoreMedia
import LyricsPiPCore

/// Owns the custom-content `AVPictureInPictureController` that floats the
/// lyrics over other apps (including Spotify itself) and the home screen.
///
/// NOTE: this is the highest-risk file in the whole project (see plan doc).
/// The exact `AVPictureInPictureSampleBufferPlaybackDelegate` method
/// signatures below are written from Apple's public documentation but have
/// not been compiled against a real Xcode toolchain (no Mac available in
/// this dev environment) — verify against the SDK on the first CI build and
/// adjust signatures if the compiler disagrees.
@MainActor
final class PiPLyricsController: NSObject, ObservableObject {
    @Published private(set) var isPiPActive = false
    @Published private(set) var isPiPPossible = false

    private var pipController: AVPictureInPictureController?
    private var displayLayer: AVSampleBufferDisplayLayer?
    private var silencePlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()

    private var latestCurrentText: String?
    private var latestNextText: String?

    func attach(syncEngine: LyricsSyncEngine) {
        syncEngine.$activeIndex
            .combineLatest(syncEngine.$lines)
            .sink { [weak self] activeIndex, lines in
                self?.updateFrame(activeIndex: activeIndex, lines: lines)
            }
            .store(in: &cancellables)
    }

    /// Sets up the PIP controller ahead of time (so `isPiPPossible` reflects
    /// device support before the user taps "start"). Safe to call repeatedly.
    func prepare() {
        setUpPiPControllerIfNeeded()
    }

    func start() {
        configureAudioSession()
        setUpPiPControllerIfNeeded()
        playSilenceLoop()
        pipController?.startPictureInPicture()
    }

    func stop() {
        pipController?.stopPictureInPicture()
        silencePlayer?.stop()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func playSilenceLoop() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "m4a") else { return }
        silencePlayer = try? AVAudioPlayer(contentsOf: url)
        silencePlayer?.numberOfLoops = -1
        // Near-silent rather than fully digital-silence: some background
        // audio session validations treat true 0-amplitude as "not really
        // playing" — verify empirically whether this matters in practice.
        silencePlayer?.volume = 0.01
        silencePlayer?.play()
    }

    private func setUpPiPControllerIfNeeded() {
        guard pipController == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        displayLayer = layer

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        pipController = controller
        isPiPPossible = true
    }

    private func updateFrame(activeIndex: Int?, lines: [LyricLine]) {
        let currentText = activeIndex.flatMap { lines.indices.contains($0) ? lines[$0].text : nil }
        let nextIndex = activeIndex.map { $0 + 1 }
        let nextText = nextIndex.flatMap { lines.indices.contains($0) ? lines[$0].text : nil }

        guard currentText != latestCurrentText || nextText != latestNextText else { return }
        latestCurrentText = currentText
        latestNextText = nextText

        guard let displayLayer,
              let cgImage = LyricsFrameRenderer.renderImage(currentLine: currentText, nextLine: nextText),
              let sampleBuffer = LyricsFrameRenderer.makeSampleBuffer(
                from: cgImage,
                presentationTime: CMClockGetTime(CMClockGetHostTimeClock())
              ) else { return }

        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }
}

extension PiPLyricsController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = false }
    }
}

extension PiPLyricsController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }
}
