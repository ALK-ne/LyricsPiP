import SwiftUI

struct LyricsPreviewView: View {
    let hasTrack: Bool
    let lines: [LyricLine]
    let activeIndex: Int?
    let noLyricsFound: Bool

    var body: some View {
        if !hasTrack {
            EmptyView()
        } else if noLyricsFound {
            Text("同期歌詞が見つかりませんでした")
                .foregroundStyle(.secondary)
                .padding()
        } else if lines.isEmpty {
            ProgressView("歌詞を取得中…")
                .padding()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(index == activeIndex ? .title3.bold() : .body)
                                .foregroundStyle(index == activeIndex ? .primary : .secondary)
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
