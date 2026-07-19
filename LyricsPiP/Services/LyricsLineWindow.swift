import Foundation
import LyricsPiPCore

/// One line to display, plus whether it's the current (highlighted) line.
/// Shared by the PiP frame renderer and the in-app landscape lyrics view so
/// both show exactly the same window of lines for a given set of settings.
struct DisplayLyricLine: Equatable {
    let text: String
    let isCurrent: Bool
}

/// Computes the ordered window of lines to display around `activeIndex`,
/// honoring the user's display settings: an optional previous line (③), the
/// current line, then `nextLinesCount` upcoming lines (②). Positions that fall
/// outside the lyrics (song start/end) become empty slots so the layout stays
/// stable instead of jumping as the window hits an edge.
enum LyricsLineWindow {
    static func build(
        activeIndex: Int?,
        lines: [LyricLine],
        showPreviousLine: Bool,
        nextLinesCount: Int
    ) -> [DisplayLyricLine] {
        func text(at index: Int?) -> String {
            guard let index, lines.indices.contains(index) else { return "" }
            return lines[index].text
        }

        var result: [DisplayLyricLine] = []
        if showPreviousLine {
            result.append(.init(text: text(at: activeIndex.map { $0 - 1 }), isCurrent: false))
        }
        result.append(.init(text: text(at: activeIndex), isCurrent: true))
        let nextCount = min(LyricsDisplaySettings.maxNextLines, max(0, nextLinesCount))
        if nextCount >= 1 {
            for offset in 1...nextCount {
                result.append(.init(text: text(at: activeIndex.map { $0 + offset }), isCurrent: false))
            }
        }
        return result
    }
}
