import SwiftUI
import LyricsPiPCore

struct LyricsPreviewView: View {
    let hasTrack: Bool
    let lines: [LyricLine]
    let activeIndex: Int?
    let noLyricsFound: Bool

    var body: some View {
        if !hasTrack {
            ContentUnavailableView("再生を待っています", systemImage: "music.note")
        } else if noLyricsFound {
            ContentUnavailableView("同期歌詞が見つかりませんでした", systemImage: "text.badge.xmark")
        } else if lines.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("歌詞を取得中…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(index == activeIndex ? .title3.bold() : .body)
                                .foregroundStyle(index == activeIndex ? .primary : .secondary)
                                .animation(.easeInOut(duration: 0.2), value: activeIndex)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .onChange(of: activeIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }
}
