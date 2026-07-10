import XCTest
@testable import LyricsPiPCore

final class SpotifyTOTPLogicTests: XCTestCase {
    // Expected values generated with the same logic as
    // tools/spotify-auth-repro.mjs (the Node reference implementation that
    // has been verified against real Spotify responses).
    private let cipherBytes = [12, 34, 56, 78, 90, 11, 22, 33]

    func testSecretKeyDataMatchesReferenceImplementation() {
        let keyData = SpotifyTOTPLogic.secretKeyData(fromCipherBytes: cipherBytes)
        XCTAssertEqual(String(data: keyData, encoding: .utf8), "54051668752549")
    }

    func testCodeMatchesReferenceImplementation() {
        let keyData = SpotifyTOTPLogic.secretKeyData(fromCipherBytes: cipherBytes)
        XCTAssertEqual(SpotifyTOTPLogic.code(keyData: keyData, unixTime: 1_700_000_000), "398989")
        // Same 30s window as 1_700_000_000...
        XCTAssertEqual(SpotifyTOTPLogic.code(keyData: keyData, unixTime: 1_700_000_009), "398989")
        // ...and the next window rolls over to a different code.
        XCTAssertEqual(SpotifyTOTPLogic.code(keyData: keyData, unixTime: 1_700_000_010), "253553")
    }

    func testCodeMatchesRFC6238AppendixBVectors() {
        // Independent cross-check: official RFC 6238 SHA-1 test vectors
        // (key = ASCII "12345678901234567890", 8 digits).
        let keyData = Data("12345678901234567890".utf8)
        XCTAssertEqual(SpotifyTOTPLogic.code(keyData: keyData, unixTime: 59, digits: 8), "94287082")
        XCTAssertEqual(SpotifyTOTPLogic.code(keyData: keyData, unixTime: 1_111_111_109, digits: 8), "07081804")
    }

    func testLatestSecretPicksHighestNumericVersion() throws {
        let json = Data(#"{"3": [7, 7, 7], "12": [12, 34, 56, 78, 90, 11, 22, 33], "9": [1, 2, 3]}"#.utf8)
        let secret = try SpotifyTOTPLogic.latestSecret(fromSecretsJSON: json)
        XCTAssertEqual(secret.version, 12)
        XCTAssertEqual(secret.cipherBytes, cipherBytes)
    }

    func testCodeFromSecretsJSONEndToEnd() throws {
        let json = Data(#"{"3": [7, 7, 7], "12": [12, 34, 56, 78, 90, 11, 22, 33]}"#.utf8)
        let code = try SpotifyTOTPLogic.code(fromSecretsJSON: json, unixTime: 1_700_000_000)
        XCTAssertEqual(code, SpotifyTOTPCode(value: "398989", version: 12))
    }

    func testLatestSecretThrowsOnMalformedJSON() {
        XCTAssertThrowsError(try SpotifyTOTPLogic.latestSecret(fromSecretsJSON: Data("not json".utf8)))
        XCTAssertThrowsError(try SpotifyTOTPLogic.latestSecret(fromSecretsJSON: Data("{}".utf8)))
    }
}
