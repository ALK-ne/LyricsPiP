import SwiftUI
import LyricsPiPCore

/// Full-screen lyrics shown while the app itself is in landscape. This is a
/// normal in-app view (not PiP), so it fills the whole screen with no OS size
/// or position constraints.
///
/// Unlike PiP (which shows a small fixed window of lines), landscape shows the
/// whole lyric sheet as a scrolling list that flows upward as the song
/// progresses. The ②③ settings are reproduced here as:
/// - ② (next-line count) → font size + line spacing: ②=1 is largest with the
///   fewest lines on screen, ②=5 is smallest with the most.
/// - ③ (show previous) → scroll anchor: on = current line centered (previous
///   line visible above); off = current line near the top (previous scrolled
///   off, focus on upcoming lines).
/// (PiP still applies ②③ literally as a fixed window.)
struct LandscapeLyricsView: View {
    let hasTrack: Bool
    let trackName: String?
    let trackArtist: String?
    let lines: [LyricLine]
    let activeIndex: Int?
    let noLyricsFound: Bool
    @ObservedObject var settings: LyricsDisplaySettings

    private let minFontSize: CGFloat = 22
    // Capped well below the point where a big font would overflow the landscape
    // width and wrap a single lyric line onto two rows. Longer lines shrink to
    // fit one row (lineLimit(1) + minimumScaleFactor) rather than wrapping.
    private let maxFontSize: CGFloat = 54

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if hasTrack {
                    header
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .overlay(alignment: .topLeading) {
            Button {
                OrientationManager.shared.enterPortrait()
            } label: {
                // No explicit color: use the default accent (blue), so it
                // matches the landscape button on the portrait screen.
                Image(systemName: "rectangle.portrait.rotate")
                    .font(.title2)
                    .padding(16)
            }
            .accessibilityLabel("縦画面に戻る")
        }
    }

    /// Song title + artist at the top, matching the portrait screen's header
    /// but styled for the black full-screen background.
    private var header: some View {
        VStack(spacing: 2) {
            Text(trackName ?? "")
                .font(.headline)
                .foregroundStyle(.white)
            Text(trackArtist ?? "")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        // Keep clear of the top-leading back button.
        .padding(.horizontal, 44)
    }

    @ViewBuilder
    private var content: some View {
        if !hasTrack {
            placeholder("再生中の曲が見つかりません")
        } else if noLyricsFound {
            placeholder("歌詞が見つかりません")
        } else if lines.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            scrollingLyrics
        }
    }

    /// The whole lyric sheet as a vertical scroll list, current line centered,
    /// flowing upward as the song advances. Font size is derived from ②③.
    private var scrollingLyrics: some View {
        GeometryReader { geo in
            let base = fontSize(forHeight: geo.size.height)
            // Wider line gaps at ②=1 (fewer lines on screen), tight at ②=5
            // (more lines) — strengthens ②'s visible effect beyond font size.
            let spacing = base * (0.9 - 0.5 * sizeT)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: spacing) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: index == activeIndex ? base * 1.12 : base,
                                              weight: index == activeIndex ? .bold : .regular))
                                .foregroundStyle(index == activeIndex ? Color.white : Color.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                                // One row per lyric line: a long line shrinks to
                                // fit the width instead of wrapping onto 2 rows.
                                .lineLimit(1)
                                .minimumScaleFactor(0.35)
                                .frame(maxWidth: .infinity)
                                .animation(.easeInOut(duration: 0.25), value: activeIndex)
                                .id(index)
                        }
                    }
                    // Top/bottom room so the first and last lines can also
                    // reach the vertical center.
                    .padding(.vertical, geo.size.height * 0.45)
                }
                .onChange(of: activeIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newValue, anchor: scrollAnchor)
                    }
                }
                .onChange(of: base) { _, _ in
                    // Font size (hence layout) changed via ② / rotation.
                    guard let activeIndex else { return }
                    proxy.scrollTo(activeIndex, anchor: scrollAnchor)
                }
                .onChange(of: settings.showPreviousLine) { _, _ in
                    // ③ toggles the anchor (center vs top): re-place current line.
                    guard let activeIndex else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(activeIndex, anchor: scrollAnchor)
                    }
                }
                .onAppear {
                    guard let activeIndex else { return }
                    proxy.scrollTo(activeIndex, anchor: scrollAnchor)
                }
            }
        }
    }

    /// ② → font size, spread linearly (largest at ②=1, smallest at ②=5) so every
    /// step visibly changes size, instead of clamping flat at the top as the old
    /// height/lines formula did. Kept below the width-overflow point so single
    /// lines shrink to one row rather than wrapping.
    private func fontSize(forHeight height: CGFloat) -> CGFloat {
        let big = min(maxFontSize, height * 0.15)
        let small = max(minFontSize, height * 0.072)
        return big - (big - small) * sizeT
    }

    /// 0 at ②=1 (biggest / fewest lines) … 1 at ②=5 (smallest / most lines).
    private var sizeT: CGFloat {
        let span = CGFloat(max(1, LyricsDisplaySettings.maxNextLines - LyricsDisplaySettings.minNextLines))
        return CGFloat(settings.nextLinesCount - LyricsDisplaySettings.minNextLines) / span
    }

    /// ③ → where the current line sits. On: centered, so the previous line shows
    /// above it. Off: near the top, so the previous line scrolls off and the
    /// focus is on the upcoming lines — this is how "show previous line" stays
    /// meaningful in a full scroll list.
    private var scrollAnchor: UnitPoint {
        settings.showPreviousLine ? .center : UnitPoint(x: 0.5, y: 0.16)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.title)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
