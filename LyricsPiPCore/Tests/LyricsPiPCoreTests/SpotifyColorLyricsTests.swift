import XCTest
@testable import LyricsPiPCore

final class SpotifyColorLyricsTests: XCTestCase {
    func testParsesLineSyncedLyrics() throws {
        let json = """
        {"lyrics":{"syncType":"LINE_SYNCED","provider":"syncpower","lines":[
          {"startTimeMs":"16323","words":"どこもおかしくはないよ"},
          {"startTimeMs":"20054","words":"午前5時には日は昇り"},
          {"startTimeMs":"24058","words":""}
        ]}}
        """
        let decoded = try JSONDecoder().decode(SpotifyColorLyrics.self, from: Data(json.utf8))
        let lines = try XCTUnwrap(decoded.syncedLines)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], LyricLine(time: 16.323, text: "どこもおかしくはないよ"))
        XCTAssertEqual(lines[1].time, 20.054, accuracy: 0.0001)
        XCTAssertEqual(lines[2].text, "") // instrumental/blank line kept
    }

    func testUnsyncedReturnsNil() throws {
        let json = """
        {"lyrics":{"syncType":"UNSYNCED","lines":[{"startTimeMs":"0","words":"plain line"}]}}
        """
        let decoded = try JSONDecoder().decode(SpotifyColorLyrics.self, from: Data(json.utf8))
        XCTAssertNil(decoded.syncedLines)
    }

    func testMissingLyricsReturnsNil() throws {
        let decoded = try JSONDecoder().decode(SpotifyColorLyrics.self, from: Data("{}".utf8))
        XCTAssertNil(decoded.syncedLines)
    }
}
