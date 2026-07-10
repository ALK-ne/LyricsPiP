import XCTest
@testable import LyricsPiPCore

final class ActiveLineFinderTests: XCTestCase {
    private let lines = [
        LyricLine(time: 0.0, text: "line0"),
        LyricLine(time: 10.0, text: "line1"),
        LyricLine(time: 20.0, text: "line2"),
        LyricLine(time: 30.0, text: "line3")
    ]

    func testReturnsNilForEmptyLines() {
        XCTAssertNil(ActiveLineFinder.activeIndex(in: [], positionMs: 5000))
    }

    func testReturnsNilBeforeFirstLine() {
        XCTAssertNil(ActiveLineFinder.activeIndex(in: lines, positionMs: -1000))
    }

    func testReturnsFirstLineAtExactStart() {
        XCTAssertEqual(ActiveLineFinder.activeIndex(in: lines, positionMs: 0), 0)
    }

    func testReturnsLineForPositionBetweenTimestamps() {
        XCTAssertEqual(ActiveLineFinder.activeIndex(in: lines, positionMs: 15_000), 1)
    }

    func testReturnsExactMatchAtLineBoundary() {
        XCTAssertEqual(ActiveLineFinder.activeIndex(in: lines, positionMs: 20_000), 2)
    }

    func testReturnsLastLineWhenPastEnd() {
        XCTAssertEqual(ActiveLineFinder.activeIndex(in: lines, positionMs: 999_000), 3)
    }
}
