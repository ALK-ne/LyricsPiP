import Foundation
import LyricsPiPCore

/// Spotify's web player now requires a TOTP code alongside the sp_dc cookie
/// when requesting an access token (added as an anti-scraping measure).
/// The secret used to derive it is obfuscated inside Spotify's web player JS
/// bundle and rotates periodically, so rather than hardcode a value that will
/// go stale, the current cipher bytes are fetched at runtime from a
/// community-maintained mirror (the same approach used by open-source
/// clients like spotube). See project README for the full rationale.
///
/// This type only does the network fetch; the actual code derivation lives
/// in `SpotifyTOTPLogic` (LyricsPiPCore) where it is unit-tested on CI.
struct SpotifyTOTPProvider {
    private static let secretsURL = URL(
        string: "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true"
    )!

    let httpClient: any HTTPClient

    func currentCode(at unixTime: Int) async throws -> SpotifyTOTPCode {
        let (data, _) = try await httpClient.data(for: URLRequest(url: Self.secretsURL))
        return try SpotifyTOTPLogic.code(fromSecretsJSON: data, unixTime: unixTime)
    }
}
