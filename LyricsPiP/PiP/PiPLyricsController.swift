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
    private var pendingStartWaitTask: Task<Void, Never>?

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

    /// Called by `PiPHostView` once its backing layer exists. That layer must
    /// actually be part of the visible SwiftUI view hierarchy — a layer that
    /// only exists in memory never makes `isPictureInPicturePossible` become
    /// true. See PiPDisplayLayerView.swift.
    func attachDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        guard displayLayer !== layer else { return }
        layer.videoGravity = .resizeAspect
        displayLayer = layer
        DebugLog.shared.log("[PiP] displayLayerを受け取りました")
        setUpPiPControllerIfNeeded()
    }

    /// Kept as a no-op call site for ContentView's onAppear — actual setup
    /// now happens once `attachDisplayLayer` provides a real, view-hosted layer.
    func prepare() {}

    func start() {
        DebugLog.shared.log("[PiP] start() 呼び出し")
        configureAudioSession()
        setUpPiPControllerIfNeeded()
        playSilenceLoop()

        guard let pipController else {
            DebugLog.shared.log("[PiP] pipControllerがnil。開始できません(デバイス非対応?)")
            return
        }

        // `AVPictureInPictureController.isPictureInPicturePossible` becomes
        // true asynchronously once the content source has real content
        // flowing — calling startPictureInPicture() before that is true
        // fails *silently* (no error, no delegate call), which is exactly
        // what looked like "the button does nothing".
        if pipController.isPictureInPicturePossible {
            DebugLog.shared.log("[PiP] isPictureInPicturePossible=true、即座に開始")
            pipController.startPictureInPicture()
        } else {
            DebugLog.shared.log("[PiP] isPictureInPicturePossible=false。準備が整うのを待ちます")
            waitForPossibleThenStart()
        }
    }

    private func waitForPossibleThenStart() {
        pendingStartWaitTask?.cancel()
        pendingStartWaitTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<50 { // poll for up to ~5 seconds
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                if let pc = self.pipController, pc.isPictureInPicturePossible {
                    DebugLog.shared.log("[PiP] isPictureInPicturePossibleがtrueになったので開始")
                    pc.startPictureInPicture()
                    return
                }
            }
            DebugLog.shared.log("[PiP] 5秒待ってもisPictureInPicturePossibleがfalseのまま。開始を諦めます")
        }
    }

    func stop() {
        pendingStartWaitTask?.cancel()
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
        guard let displayLayer else {
            DebugLog.shared.log("[PiP] displayLayer未着のためセットアップを待機")
            return
        }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            DebugLog.shared.log("[PiP] このデバイス/OSはPIP非対応です")
            return
        }

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        pipController = controller
        isPiPPossible = true
        DebugLog.shared.log("[PiP] コントローラーのセットアップ完了")
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
        Task { @MainActor in
            DebugLog.shared.log("[PiP] 開始成功")
            self.isPiPActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            DebugLog.shared.log("[PiP] 停止")
            self.isPiPActive = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            DebugLog.shared.log("[PiP] 開始失敗: \(error.localizedDescription)")
        }
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
