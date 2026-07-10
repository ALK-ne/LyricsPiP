import XCTest
@testable import LyricsPiPCore

final class LrclibModelsTests: XCTestCase {
    func testSyncedLinesParsesLRCPayload() throws {
        let json = Data("""
        {
            "syncedLyrics": "[00:01.50]first line\\n[00:03.00]second line",
            "plainLyrics": "first line\\nsecond line"
        }
        """.utf8)
        let track = try JSONDecoder().decode(LrclibTrack.self, from: json)
        XCTAssertEqual(track.syncedLines, [
            LyricLine(time: 1.5, text: "first line"),
            LyricLine(time: 3.0, text: "second line")
        ])
    }

    func testSyncedLinesIsNilWhenOnlyPlainLyricsExist() throws {
        let json = Data(#"{"syncedLyrics": null, "plainLyrics": "just text"}"#.utf8)
        let track = try JSONDecoder().decode(LrclibTrack.self, from: json)
        XCTAssertNil(track.syncedLines)
    }

    func testSyncedLinesIsNilWhenSyncedLyricsIsEmpty() {
        let track = LrclibTrack(syncedLyrics: "", plainLyrics: nil)
        XCTAssertNil(track.syncedLines)
    }
}
