import XCTest
@testable import LyricsPiPCore

final class SpotifyAPIModelsTests: XCTestCase {
    func testAccessTokenDecodingAndExpiration() throws {
        let json = Data("""
        {
            "clientId": "abc123",
            "accessToken": "token-value",
            "accessTokenExpirationTimestampMs": 1700000000000,
            "isAnonymous": false
        }
        """.utf8)
        let token = try JSONDecoder().decode(SpotifyAccessToken.self, from: json)
        XCTAssertEqual(token.accessToken, "token-value")
        XCTAssertFalse(token.isAnonymous)
        XCTAssertEqual(token.expirationDate, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testCurrentlyPlayingDecodesSnakeCaseAndMapsToCurrentTrack() throws {
        let json = Data("""
        {
            "progress_ms": 12345,
            "is_playing": true,
            "item": {
                "id": "track-id",
                "name": "夜に駆ける",
                "duration_ms": 262000,
                "artists": [{"name": "YOASOBI"}, {"name": "someone else"}],
                "album": {"name": "THE BOOK"}
            }
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: json)
        XCTAssertEqual(decoded.progressMs, 12345)
        XCTAssertTrue(decoded.isPlaying)

        let track = try XCTUnwrap(decoded.currentTrack)
        XCTAssertEqual(
            track,
            CurrentTrack(id: "track-id", name: "夜に駆ける", artist: "YOASOBI", album: "THE BOOK", durationMs: 262000)
        )
    }

    func testCurrentlyPlayingWithNullItemHasNoTrack() throws {
        let json = Data(#"{"progress_ms": null, "is_playing": false, "item": null}"#.utf8)
        let decoded = try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: json)
        XCTAssertNil(decoded.progressMs)
        XCTAssertFalse(decoded.isPlaying)
        XCTAssertNil(decoded.currentTrack)
    }

    func testCurrentlyPlayingWithEmptyArtistsFallsBackToEmptyName() throws {
        let json = Data("""
        {
            "is_playing": true,
            "item": {
                "id": "x",
                "name": "instrumental",
                "duration_ms": 1000,
                "artists": [],
                "album": {"name": "a"}
            }
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: json)
        XCTAssertEqual(decoded.currentTrack?.artist, "")
    }
}
