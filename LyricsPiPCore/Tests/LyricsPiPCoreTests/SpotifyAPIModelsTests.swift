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
}
