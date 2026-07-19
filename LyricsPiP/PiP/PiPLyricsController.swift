import AVKit
import AVFoundation
import Combine
import CoreMedia
import UIKit
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

    private let logger: any LyricsPiPLogging

    private var pipController: AVPictureInPictureController?
    private var displayLayer: AVSampleBufferDisplayLayer?
    private var silencePlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()

    private let settings = LyricsDisplaySettings.shared
    private var latestDisplayLines: [DisplayLyricLine] = []
    private var latestFrameSize: CGSize = .zero
    private var latestLines: [LyricLine] = []
    private var latestActiveIndex: Int?
    // The display layer needs at least one enqueued frame before PiP can start;
    // otherwise startPictureInPicture fails with PGPegasusErrorDomain -1003.
    // Without this latch the very first frame is suppressed when there's no
    // active lyric line yet (currentText nil == the initial nil), which left
    // the layer empty if the user opened PiP before a line became active.
    private var hasEnqueuedFrame = false
    // Guards the one-time log line in prepareForAutoStart(); the underlying
    // steps it calls are all individually idempotent/self-guarded, so the
    // method itself is safe to call repeatedly (needed since it may run
    // before the display layer/pipController exist yet and has to retry).
    private var autoStartArmed = false
    // Intentionally never removed: this controller is owned as a @StateObject
    // for the app's entire lifetime (like `cancellables` below), so there's no
    // meaningful deinit to unregister from — and unregistering from a
    // MainActor-isolated deinit is its own concurrency-correctness headache.
    private var foregroundObserver: NSObjectProtocol?

    init(logger: (any LyricsPiPLogging)? = nil) {
        self.logger = logger ?? DebugLog.shared
        super.init()

        // canStartPictureInPictureAutomaticallyFromInline's documented
        // "stops automatically on foreground" behavior turned out, on device,
        // to only fire when the user taps PiP's own "return to app" button —
        // reopening the app directly (home screen icon / app switcher) never
        // calls stopPictureInPicture at all for this custom sample-buffer
        // content source, leaving PiP stuck open. Detecting foreground
        // ourselves and stopping explicitly covers that path too.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPiPActive else { return }
                self.logger.log("[PiP] フォアグラウンド復帰を検知、PiPを閉じます")
                self.pipController?.stopPictureInPicture()
            }
        }

        // Re-render the PiP frame whenever the user changes the display
        // settings (line count / previous-line toggle). objectWillChange fires
        // in willSet, before the new value is committed; hopping through a
        // MainActor Task defers the redraw until after the value has updated,
        // so we read the new setting, not the old one.
        settings.objectWillChange
            .sink { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.updateFrame(activeIndex: self.latestActiveIndex, lines: self.latestLines)
                }
            }
            .store(in: &cancellables)
    }

    func attach(syncEngine: LyricsSyncEngine) {
        syncEngine.$activeIndex
            .combineLatest(syncEngine.$lines)
            .sink { [weak self] activeIndex, lines in
                guard let self else { return }
                self.latestActiveIndex = activeIndex
                self.latestLines = lines
                self.updateFrame(activeIndex: activeIndex, lines: lines)
                // Once real lyrics exist, proactively get audio/PiP ready so
                // canStartPictureInPictureAutomaticallyFromInline can actually
                // fire the moment the user backgrounds the app -- doing this
                // lazily on backgrounding itself would be too late.
                if !lines.isEmpty {
                    self.prepareForAutoStart()
                }
            }
            .store(in: &cancellables)
    }

    /// Arms automatic PiP-on-background: activates the (mixed) audio session,
    /// ensures the PiP controller exists with content already flowing, and
    /// opts in to `canStartPictureInPictureAutomaticallyFromInline` so iOS
    /// starts PiP itself when the app backgrounds. This is the only way PiP
    /// starts now -- verified on device across several background/foreground
    /// patterns, so the manual start/stop button was removed.
    private func prepareForAutoStart() {
        // Once armed, this is a no-op — otherwise configureAudioSession's log
        // line (and the redundant setup work) would fire on every ~0.2s
        // position tick for as long as lyrics keep updating, flooding the log
        // exactly like the removed per-frame line did. Before arming, retrying
        // each tick is intentional: the display layer/pipController may not
        // exist yet the first few times this runs.
        guard !autoStartArmed else { return }

        configureAudioSession()
        setUpPiPControllerIfNeeded()
        playSilenceLoop()
        updateFrame(activeIndex: latestActiveIndex, lines: latestLines)

        guard let pipController else { return }
        pipController.canStartPictureInPictureAutomaticallyFromInline = true
        autoStartArmed = true
        logger.log("[PiP] 自動開始を有効化 (バックグラウンド移行時に自動でPiP開始)")
    }

    /// Called by `PiPHostView` once its backing layer exists. That layer must
    /// actually be part of the visible SwiftUI view hierarchy — a layer that
    /// only exists in memory never makes `isPictureInPicturePossible` become
    /// true. See PiPDisplayLayerView.swift.
    func attachDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        guard displayLayer !== layer else { return }
        if displayLayer != nil {
            logger.log("[PiP] 警告: displayLayerが別インスタンスに差し替わりました")
        }
        layer.videoGravity = .resizeAspect
        displayLayer = layer
        logger.log("[PiP] displayLayerを受け取りました")
        setUpPiPControllerIfNeeded()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // `.mixWithOthers` is essential here: without it, activating a
            // `.playback` session interrupts Spotify (pausing the music we're
            // showing lyrics for) and, when Spotify won't yield, setActive
            // fails — leaving no active audio session, which makes custom PiP
            // fail to start (PGPegasusErrorDomain -1003). Mixing lets our
            // (near-silent) keep-alive audio coexist with Spotify's playback.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            logger.log("[PiP] オーディオセッション有効化 (mixWithOthers)")
        } catch {
            logger.log("[PiP] オーディオセッション設定失敗: \(error.localizedDescription)")
        }
    }

    private func playSilenceLoop() {
        // Plays indefinitely once started — nothing stops it, since it needs
        // to keep the audio session alive persistently for PiP to be able to
        // auto-start on every future backgrounding, not just the first one.
        guard silencePlayer?.isPlaying != true else { return }
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
            logger.log("[PiP] displayLayer未着のためセットアップを待機")
            return
        }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            logger.log("[PiP] このデバイス/OSはPIP非対応です")
            return
        }

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        pipController = controller
        logger.log("[PiP] コントローラーのセットアップ完了")
    }

    private func updateFrame(activeIndex: Int?, lines: [LyricLine]) {
        let displayLines = LyricsLineWindow.build(
            activeIndex: activeIndex,
            lines: lines,
            showPreviousLine: settings.showPreviousLine,
            nextLinesCount: settings.nextLinesCount
        )
        let frameSize = LyricsFrameRenderer.frameSize(lineCount: displayLines.count)

        guard !hasEnqueuedFrame || displayLines != latestDisplayLines || frameSize != latestFrameSize else { return }
        latestDisplayLines = displayLines
        latestFrameSize = frameSize

        guard let displayLayer else {
            logger.log("[PiP] フレーム更新スキップ: displayLayerがまだ無い")
            return
        }
        guard let cgImage = LyricsFrameRenderer.renderImage(lines: displayLines, frameSize: frameSize) else {
            logger.log("[PiP] フレーム描画失敗")
            return
        }
        guard let sampleBuffer = LyricsFrameRenderer.makeSampleBuffer(
            from: cgImage,
            presentationTime: CMClockGetTime(CMClockGetHostTimeClock())
        ) else {
            logger.log("[PiP] サンプルバッファ作成失敗")
            return
        }

        if displayLayer.status == .failed {
            logger.log("[PiP] displayLayer.status=failed、flushします")
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
        hasEnqueuedFrame = true
        // Deliberately not logged: fires on every lyric line change (every
        // few seconds while a track plays) and quickly floods the log.
    }
}

extension PiPLyricsController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.logger.log("[PiP] 開始成功")
            self.isPiPActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.logger.log("[PiP] 停止")
            self.isPiPActive = false
        }
    }

    /// The system calls this when PiP is stopping (manual or automatic-on-
    /// foreground via canStartPictureInPictureAutomaticallyFromInline) and
    /// waits for the completion handler before finishing the transition. We
    /// have no inline player view to restore, so there's nothing to do except
    /// call it back immediately — without this method at all, the automatic
    /// stop-on-foreground appears to never actually complete, leaving PiP
    /// stuck open until the user manually taps "PIPを閉じる".
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            self.logger.log("[PiP] 開始失敗: \(error.localizedDescription)")
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
