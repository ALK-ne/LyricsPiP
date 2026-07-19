import SwiftUI
import LyricsPiPCore

/// Full-screen lyrics shown while the app itself is in landscape. This is a
/// normal in-app view (not PiP), so it fills the whole screen with no OS size
/// or position constraints.
///
/// Unlike PiP (which shows a small fixed window of lines), landscape shows the
/// whole lyric sheet as a scrolling list that keeps the current line centered
/// and flows upward as the song progresses. The ②③ settings (next-line count /
/// show-previous) are reproduced here via *font size*: the target number of
/// visible lines sets how large the text is — fewer lines = bigger/immersive,
/// more lines = smaller/more context. (PiP still applies ②③ literally.)
struct LandscapeLyricsView: View {
    let hasTrack: Bool
    let trackName: String?
    let trackArtist: String?
    let lines: [LyricLine]
    let activeIndex: Int?
    let noLyricsFound: Bool
    @ObservedObject var settings: LyricsDisplaySettings

    private let minFontSize: CGFloat = 22
    private let maxFontSize: CGFloat = 80

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
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: base * 0.5) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: index == activeIndex ? base * 1.12 : base,
                                              weight: index == activeIndex ? .bold : .regular))
                                .foregroundStyle(index == activeIndex ? Color.white : Color.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.4)
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
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onChange(of: base) { _, _ in
                    // Font size (hence layout) changed via settings/rotation;
                    // re-center the current line without animation.
                    guard let activeIndex else { return }
                    proxy.scrollTo(activeIndex, anchor: .center)
                }
                .onAppear {
                    guard let activeIndex else { return }
                    proxy.scrollTo(activeIndex, anchor: .center)
                }
            }
        }
    }

    /// Maps ②③ to a font size: target visible lines = (prev? 1 : 0) + current +
    /// nextLinesCount, then size the text so roughly that many lines fill the
    /// height. Clamped so it never gets unreadably small or absurdly large.
    private func fontSize(forHeight height: CGFloat) -> CGFloat {
        let targetLines = (settings.showPreviousLine ? 1 : 0) + 1 + settings.nextLinesCount
        let raw = (height / CGFloat(max(1, targetLines))) * 0.58
        return min(maxFontSize, max(minFontSize, raw))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.title)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
