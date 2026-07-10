import XCTest
@testable import LyricsPiPCore

final class LRCParserTests: XCTestCase {
    func testParsesBasicTimestampedLines() {
        let lrc = """
        [00:12.34]First line
        [00:15.00]Second line
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].time, 12.34, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "First line")
        XCTAssertEqual(lines[1].time, 15.0, accuracy: 0.001)
        XCTAssertEqual(lines[1].text, "Second line")
    }

    func testSortsOutOfOrderLines() {
        let lrc = """
        [01:00.00]Later line
        [00:05.00]Earlier line
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.map(\.text), ["Earlier line", "Later line"])
    }

    func testSkipsMetadataTags() {
        let lrc = """
        [ar:Some Artist]
        [ti:Some Title]
        [00:01.00]Actual lyric
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "Actual lyric")
    }

    func testHandlesTwoAndThreeDigitFractions() {
        let lrc = """
        [00:01.5]Two-tenths style
        [00:02.500]Three-digit style
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines[0].time, 1.5, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 2.5, accuracy: 0.001)
    }

    func testHandlesMinutesOverAnHour() {
        let lrc = "[75:30.00]Long track line"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines[0].time, 75 * 60 + 30, accuracy: 0.001)
    }

    func testEmptyInputReturnsEmptyArray() {
        XCTAssertEqual(LRCParser.parse(""), [])
    }

    func testTrimsWhitespaceAroundLyricText() {
        let lrc = "[00:01.00]   padded text   "
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines[0].text, "padded text")
    }
}
