import XCTest
@testable import LyricsPiPCore

final class PlaybackPositionInterpolatorTests: XCTestCase {
    func testPositionAdvancesWithElapsedTime() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let interpolator = PlaybackPositionInterpolator(positionMs: 10_000, at: base)
        XCTAssertEqual(interpolator.position(at: base), 10_000)
        XCTAssertEqual(interpolator.position(at: base.addingTimeInterval(2.5)), 12_500)
    }

    func testRebaseReanchorsPosition() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var interpolator = PlaybackPositionInterpolator(positionMs: 10_000, at: base)

        // A new poll result mid-song (e.g. after the user seeked backwards)
        // must fully replace the extrapolated position.
        let pollDate = base.addingTimeInterval(40)
        interpolator.rebase(positionMs: 5_000, at: pollDate)
        XCTAssertEqual(interpolator.position(at: pollDate), 5_000)
        XCTAssertEqual(interpolator.position(at: pollDate.addingTimeInterval(1)), 6_000)
    }

    func testDefaultStartsAtZero() {
        let now = Date()
        let interpolator = PlaybackPositionInterpolator(at: now)
        XCTAssertEqual(interpolator.position(at: now), 0)
    }
}
