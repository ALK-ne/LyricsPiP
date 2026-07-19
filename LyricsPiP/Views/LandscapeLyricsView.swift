import SwiftUI
import LyricsPiPCore

/// Full-screen lyrics shown while the app itself is in landscape. This is a
/// normal in-app view (not PiP), so it fills the whole screen with no OS size
/// or position constraints — the large counterpart to the small PiP window.
/// It mirrors the PiP content and honors the same display settings.
struct LandscapeLyricsView: View {
    let hasTrack: Bool
    let lines: [LyricLine]
    let activeIndex: Int?
    let noLyricsFound: Bool
    @ObservedObject var settings: LyricsDisplaySettings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
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

    @ViewBuilder
    private var content: some View {
        if !hasTrack {
            placeholder("再生中の曲が見つかりません")
        } else if noLyricsFound {
            placeholder("歌詞が見つかりません")
        } else {
            let display = LyricsLineWindow.build(
                activeIndex: activeIndex,
                lines: lines,
                showPreviousLine: settings.showPreviousLine,
                nextLinesCount: settings.nextLinesCount
            )
            VStack(spacing: 8) {
                ForEach(Array(display.enumerated()), id: \.offset) { _, line in
                    Text(displayText(for: line))
                        .font(.system(size: line.isCurrent ? 60 : 38,
                                      weight: line.isCurrent ? .bold : .regular))
                        .foregroundStyle(line.isCurrent ? Color.white : Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func displayText(for line: DisplayLyricLine) -> String {
        if line.text.isEmpty {
            // Keep an empty (non-current) slot occupying space so the current
            // line stays vertically centered when there's no previous/next line.
            return line.isCurrent ? "♪" : " "
        }
        return line.text
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.title)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
