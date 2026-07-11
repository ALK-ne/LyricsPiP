import XCTest
@testable import LyricsPiPCore

final class SpotifyIDTests: XCTestCase {
    func testGidHexMatchesKnownTrack() {
        // Cross-checked against the live metadata/4/track endpoint:
        // spotify:track:2Pqkxb3UEDdnBBFXQVxNKK -> this gid.
        XCTAssertEqual(
            SpotifyID.gidHex(fromBase62: "2Pqkxb3UEDdnBBFXQVxNKK"),
            "5cf758672af54832a108b0c83f258b5e"
        )
    }

    func testGidHexRejectsInvalidCharacters() {
        XCTAssertNil(SpotifyID.gidHex(fromBase62: "not a valid id !!"))
        XCTAssertNil(SpotifyID.gidHex(fromBase62: ""))
    }

    func testBareIdFromURI() {
        XCTAssertEqual(SpotifyID.bareId(fromURI: "spotify:track:2Pqkxb3UEDdnBBFXQVxNKK"), "2Pqkxb3UEDdnBBFXQVxNKK")
        XCTAssertEqual(SpotifyID.bareId(fromURI: "2Pqkxb3UEDdnBBFXQVxNKK"), "2Pqkxb3UEDdnBBFXQVxNKK")
    }

    func testTrackMetadataExtractsArtistName() throws {
        let json = """
        {"name":"soFt-dRink","artist":[{"name":"Mrs. GREEN APPLE"}],"album":{"name":"Mrs. GREEN APPLE"}}
        """
        let meta = try JSONDecoder().decode(SpotifyTrackMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(meta.artistName, "Mrs. GREEN APPLE")
        XCTAssertEqual(meta.albumName, "Mrs. GREEN APPLE")
    }

    func testTrackMetadataArtistNameNilWhenEmpty() throws {
        let json = #"{"name":"x","artist":[{"name":""}],"album":{"name":"a"}}"#
        let meta = try JSONDecoder().decode(SpotifyTrackMetadata.self, from: Data(json.utf8))
        XCTAssertNil(meta.artistName)
    }
}
