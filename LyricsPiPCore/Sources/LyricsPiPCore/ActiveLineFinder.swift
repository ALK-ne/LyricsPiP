import Foundation

public enum ActiveLineFinder {
    /// Binary search for the last line whose timestamp is <= the current
    /// playback position (in milliseconds). Returns nil if `lines` is empty
    /// or the position is before the first line.
    public static func activeIndex(in lines: [LyricLine], positionMs: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        let positionSeconds = TimeInterval(positionMs) / 1000

        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= positionSeconds {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
