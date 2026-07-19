import Foundation
import Combine

/// User-configurable options for how many lyric lines the PiP window shows.
/// Backed by `UserDefaults` and exposed as a shared singleton so the settings
/// UI and `PiPLyricsController` observe (and mutate) the very same instance.
///
/// - `nextLinesCount`: how many upcoming lines to render below the current
///   line (② — default 1, range 1...5).
/// - `showPreviousLine`: whether to also render the one line before the
///   current line, above it (③ — default off). When on, the current line
///   ends up in the middle (previous above, next below).
final class LyricsDisplaySettings: ObservableObject {
    static let shared = LyricsDisplaySettings()

    static let minNextLines = 1
    static let maxNextLines = 5

    @Published var nextLinesCount: Int {
        didSet { defaults.set(nextLinesCount, forKey: Keys.nextLinesCount) }
    }

    @Published var showPreviousLine: Bool {
        didSet { defaults.set(showPreviousLine, forKey: Keys.showPreviousLine) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let nextLinesCount = "lyrics.display.nextLinesCount"
        static let showPreviousLine = "lyrics.display.showPreviousLine"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default to 1 next line when nothing is stored yet; clamp any stored
        // value into the supported range so a corrupted/old value can't make
        // the PiP window absurdly tall.
        if let stored = defaults.object(forKey: Keys.nextLinesCount) as? Int {
            self.nextLinesCount = min(Self.maxNextLines, max(Self.minNextLines, stored))
        } else {
            self.nextLinesCount = 1
        }
        // `bool(forKey:)` returns false when unset — exactly the desired
        // default (previous line off).
        self.showPreviousLine = defaults.bool(forKey: Keys.showPreviousLine)
    }
}
