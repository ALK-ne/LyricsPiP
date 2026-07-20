import SwiftUI
import LyricsPiPCore

/// Full-screen lyrics shown while the app itself is in landscape. This is a
/// normal in-app view (not PiP), so it fills the whole screen with no OS size
/// or position constraints.
///
/// Unlike PiP (which shows a small fixed window of lines), landscape shows the
/// whole lyric sheet as a scrolling list that flows upward as the song
/// progresses. The ②③ settings drive the on-screen line count directly:
/// - visible lines = current + ② upcoming (+ 1 previous when ③ on).
/// - line pitch = height / visible lines, so fewer lines = wider gaps (the font
///   is capped for width, so the extra space becomes spacing, not a huge font).
/// - ③ off places the current line at the top (previous scrolled off); ③ on
///   places it second (one previous line visible above).
/// (PiP still applies ②③ literally as a fixed window.)
struct LandscapeLyricsView: View {
    let hasTrack: Bool
    let trackName: String?
    let trackArtist: String?
    let lines: [LyricLine]
    let activeIndex: Int?
    let noLyricsFound: Bool
    @ObservedObject var settings: LyricsDisplaySettings

    // Font is capped well below the point where it would overflow the landscape
    // width and wrap a single lyric onto two rows. When few lines are requested
    // the leftover vertical space becomes a large line gap instead of a bigger
    // font. Longer lines shrink to one row (lineLimit(1) + minimumScaleFactor).
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
    /// flowing upward as the song advances. See `visibleLineCount` for ②③.
    private var scrollingLyrics: some View {
        GeometryReader { geo in
            let vis = visibleLineCount
            let pitch = geo.size.height / CGFloat(vis)
            let font = min(maxFontSize, pitch * 0.7)
            let spacing = max(2, pitch - font * 1.2)
            // ③ OFF → current sits near the top; ③ ON → lower, with previous
            // lines dimmed above it. Continuous smooth scroll; the top/bottom
            // edges fade to black (edgeFadeMask) so lines entering/leaving the
            // screen dissolve instead of hard-clipping.
            let anchor = UnitPoint(x: 0.5, y: (settings.showPreviousLine ? 1.5 : 0.5) / CGFloat(vis))
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: spacing) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: index == activeIndex ? font * 1.08 : font,
                                              weight: index == activeIndex ? .bold : .regular))
                                .foregroundStyle(index == activeIndex ? Color.white : Color.white.opacity(0.4))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.35)
                                .frame(maxWidth: .infinity)
                                .animation(.easeInOut(duration: 0.25), value: activeIndex)
                                .id(index)
                        }
                    }
                    .padding(.vertical, geo.size.height)
                }
                .mask(edgeFadeMask)
                .onChange(of: activeIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(newValue, anchor: anchor)
                    }
                }
                .onChange(of: pitch) { _, _ in
                    guard let activeIndex else { return }
                    proxy.scrollTo(activeIndex, anchor: anchor)
                }
                .onAppear {
                    guard let activeIndex else { return }
                    proxy.scrollTo(activeIndex, anchor: anchor)
                }
            }
        }
    }

    /// Fades the very top and bottom edges to transparent so lines scrolling in
    /// and out dissolve smoothly. The clear top stop stays above where the
    /// current line ever sits (③ OFF puts it highest, at 0.5/vis) so the active
    /// line itself is never faded.
    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.85),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// How many lyric lines to fit on screen, straight from ②③:
    /// current + ② upcoming lines, plus one previous line when ③ is on.
    /// This directly drives the line pitch (height / count), so ② controls the
    /// on-screen line count and ③ controls whether a previous line is included.
    private var visibleLineCount: Int {
        (settings.showPreviousLine ? 2 : 1) + settings.nextLinesCount
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.title)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
