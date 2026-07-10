import Foundation
import CryptoKit

/// Spotify's web player now requires a TOTP code alongside the sp_dc cookie
/// when requesting an access token (added as an anti-scraping measure).
/// The secret used to derive it is obfuscated inside Spotify's web player JS
/// bundle and rotates periodically, so rather than hardcode a value that will
/// go stale, the current cipher bytes are fetched at runtime from a
/// community-maintained mirror (the same approach used by open-source
/// clients like spotube). See project README for the full rationale.
enum SpotifyTOTP {
    private static let secretsURL = URL(
        string: "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true"
    )!

    struct Code {
        let value: String
        let version: Int
    }

    static func currentCode(at unixTime: Int) async throws -> Code {
        let (version, cipherBytes) = try await fetchLatestSecret()
        let keyData = secretKeyData(fromCipherBytes: cipherBytes)
        let code = totp(keyData: keyData, unixTime: unixTime)
        return Code(value: code, version: version)
    }

    private static func fetchLatestSecret() async throws -> (version: Int, cipherBytes: [Int]) {
        let (data, _) = try await URLSession.shared.data(from: secretsURL)
        let decoded = try JSONDecoder().decode([String: [Int]].self, from: data)
        guard let highest = decoded.max(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }),
              let version = Int(highest.key) else {
            throw URLError(.cannotParseResponse)
        }
        return (version, highest.value)
    }

    /// Reproduces Spotify web player's obfuscation: XOR each cipher byte with
    /// a position-derived value, then use the decimal-digit concatenation of
    /// the result as the raw HMAC key (equivalent to base32-encoding it and
    /// letting a TOTP library immediately decode it back — so that round
    /// trip is skipped here).
    private static func secretKeyData(fromCipherBytes cipherBytes: [Int]) -> Data {
        let transformed = cipherBytes.enumerated().map { index, value in value ^ ((index % 33) + 9) }
        let joined = transformed.map(String.init).joined()
        return Data(joined.utf8)
    }

    private static func totp(keyData: Data, unixTime: Int, digits: Int = 6, period: Int = 30) -> String {
        var counter = UInt64(unixTime / period).bigEndian
        let counterData = withUnsafeBytes(of: &counter) { Data($0) }
        let key = SymmetricKey(data: keyData)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hmacBytes = Array(hmac)
        let offset = Int(hmacBytes[hmacBytes.count - 1] & 0x0f)
        let truncated =
            (UInt32(hmacBytes[offset] & 0x7f) << 24) |
            (UInt32(hmacBytes[offset + 1]) << 16) |
            (UInt32(hmacBytes[offset + 2]) << 8) |
            UInt32(hmacBytes[offset + 3])
        let modulus = UInt32(pow(10.0, Double(digits)))
        let code = truncated % modulus
        return String(format: "%0\(digits)d", code)
    }
}
