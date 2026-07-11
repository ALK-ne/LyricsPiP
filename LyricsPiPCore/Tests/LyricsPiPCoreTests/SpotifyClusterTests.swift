import XCTest
@testable import LyricsPiPCore

final class SpotifyClusterTests: XCTestCase {
    // Trimmed from a real connect-state cluster response captured via the
    // dealer WebSocket (Mrs. GREEN APPLE - 藍(あお)). Field names/types match
    // Spotify's actual payload: int64s are JSON strings, booleans are bare.
    private let clusterJSON = """
    {
      "timestamp": "1783749990601",
      "player_state": {
        "timestamp": "1783749129687",
        "position_as_of_timestamp": "121347",
        "duration": "238114",
        "is_playing": true,
        "is_paused": true,
        "track": {
          "uri": "spotify:track:5PbDuVKV2IFXxNNkjWbGB4",
          "metadata": {
            "title": "藍(あお)",
            "artist_name": "Mrs. GREEN APPLE",
            "album_title": "TWELVE",
            "duration": "238066"
          }
        }
      }
    }
    """

    func testParsesRealCluster() throws {
        let snapshot = try XCTUnwrap(SpotifyClusterParser.parse(Data(clusterJSON.utf8)))
        let track = try XCTUnwrap(snapshot.track)

        XCTAssertEqual(track.id, "5PbDuVKV2IFXxNNkjWbGB4")
        XCTAssertEqual(track.name, "藍(あお)")
        XCTAssertEqual(track.artist, "Mrs. GREEN APPLE")
        XCTAssertEqual(track.album, "TWELVE")
        XCTAssertEqual(track.durationMs, 238066)

        XCTAssertEqual(snapshot.positionMs, 121347)
        XCTAssertEqual(snapshot.timestampMs, 1783749129687)
        XCTAssertTrue(snapshot.isPaused)
    }

    func testFallsBackToPlayerStateDurationWhenMetadataMissingIt() throws {
        let json = """
        {"player_state":{"timestamp":"1000","position_as_of_timestamp":"500","duration":"200000","is_paused":false,
          "track":{"uri":"spotify:track:abc","metadata":{"title":"T","artist_name":"A","album_title":"Al"}}}}
        """
        let snapshot = try XCTUnwrap(SpotifyClusterParser.parse(Data(json.utf8)))
        XCTAssertEqual(snapshot.track?.durationMs, 200000)
        XCTAssertFalse(snapshot.isPaused)
    }

    func testNoPlayerStateReturnsNil() {
        let json = """
        {"timestamp":"123","devices":{},"need_full_player_state":false}
        """
        XCTAssertNil(SpotifyClusterParser.parse(Data(json.utf8)))
    }

    func testPlayerStateWithoutTrackHasNilTrackButKeepsPosition() throws {
        let json = """
        {"player_state":{"timestamp":"9","position_as_of_timestamp":"3","is_paused":true}}
        """
        let snapshot = try XCTUnwrap(SpotifyClusterParser.parse(Data(json.utf8)))
        XCTAssertNil(snapshot.track)
        XCTAssertEqual(snapshot.positionMs, 3)
        XCTAssertTrue(snapshot.isPaused)
    }

    // MARK: - TrackMetadataMerge

    private func track(_ id: String, name: String = "N", artist: String = "A") -> CurrentTrack {
        CurrentTrack(id: id, name: name, artist: artist, album: "Al", durationMs: 1000)
    }

    func testMergeKeepsExistingWhenSameTrackLosesArtist() {
        let existing = track("x", artist: "Mrs. GREEN APPLE")
        let blip = track("x", artist: "")
        XCTAssertEqual(TrackMetadataMerge.resolve(existing: existing, incoming: blip), existing)
    }

    func testMergeAcceptsRicherUpdateThatFillsArtistBackIn() {
        let existing = track("x", artist: "")
        let filled = track("x", artist: "Chevon")
        XCTAssertEqual(TrackMetadataMerge.resolve(existing: existing, incoming: filled), filled)
    }

    func testMergeAcceptsGenuinelyDifferentTrackEvenWithEmptyArtist() {
        let existing = track("x", artist: "Someone")
        let newTrack = track("y", artist: "")
        XCTAssertEqual(TrackMetadataMerge.resolve(existing: existing, incoming: newTrack), newTrack)
    }

    func testMergePassesThroughNilAndFirstTrack() {
        XCTAssertNil(TrackMetadataMerge.resolve(existing: track("x"), incoming: nil))
        let first = track("x")
        XCTAssertEqual(TrackMetadataMerge.resolve(existing: nil, incoming: first), first)
    }
}
