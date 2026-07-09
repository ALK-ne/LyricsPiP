import Foundation

enum LRCParser {
    /// Parses standard `[mm:ss.xx]lyric text` LRC lines into a sorted array.
    /// Lines without a valid timestamp (metadata tags like `[ar:Artist]`) are skipped.
    static func parse(_ lrcText: String) -> [LyricLine] {
        let pattern = #"^\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\](.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var lines: [LyricLine] = []
        for rawLine in lrcText.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }

            guard let minutes = intValue(match, group: 1, in: line),
                  let seconds = intValue(match, group: 2, in: line) else { continue }

            let fraction = fractionValue(match, group: 3, in: line)
            let text = textValue(match, group: 4, in: line).trimmingCharacters(in: .whitespaces)

            let time = TimeInterval(minutes * 60 + seconds) + fraction
            lines.append(LyricLine(time: time, text: text))
        }

        return lines.sorted { $0.time < $1.time }
    }

    private static func intValue(_ match: NSTextCheckingResult, group: Int, in line: String) -> Int? {
        guard let range = Range(match.range(at: group), in: line) else { return nil }
        return Int(line[range])
    }

    private static func fractionValue(_ match: NSTextCheckingResult, group: Int, in line: String) -> TimeInterval {
        guard let range = Range(match.range(at: group), in: line) else { return 0 }
        let digits = String(line[range])
        guard let value = Int(digits), !digits.isEmpty else { return 0 }
        let divisor = pow(10.0, Double(digits.count))
        return TimeInterval(value) / divisor
    }

    private static func textValue(_ match: NSTextCheckingResult, group: Int, in line: String) -> String {
        guard let range = Range(match.range(at: group), in: line) else { return "" }
        return String(line[range])
    }
}
