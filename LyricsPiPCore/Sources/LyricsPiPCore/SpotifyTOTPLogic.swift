import Foundation
import CryptoKit

public struct SpotifyTOTPCode: Equatable, Sendable {
    public let value: String
    public let version: Int

    public init(value: String, version: Int) {
        self.value = value
        self.version = version
    }
}

/// The pure half of Spotify's TOTP anti-scraping check: turning the cipher
/// bytes published by the community mirror into a 6-digit code. Fetching
/// the bytes over the network stays app-side (SpotifyTOTP.swift); keeping
/// the derivation here means it runs under `swift test` on CI, with
/// tools/spotify-auth-repro.mjs as the cross-checked reference.
public enum SpotifyTOTPLogic {
    public struct Secret: Equatable, Sendable {
        public let version: Int
        public let cipherBytes: [Int]

        public init(version: Int, cipherBytes: [Int]) {
            self.version = version
            self.cipherBytes = cipherBytes
        }
    }

    /// Convenience: mirror JSON (`{"<version>": [bytes...]}`) straight to a code.
    public static func code(fromSecretsJSON data: Data, unixTime: Int) throws -> SpotifyTOTPCode {
        let secret = try latestSecret(fromSecretsJSON: data)
        let keyData = secretKeyData(fromCipherBytes: secret.cipherBytes)
        return SpotifyTOTPCode(value: code(keyData: keyData, unixTime: unixTime), version: secret.version)
    }

    public static func latestSecret(fromSecretsJSON data: Data) throws -> Secret {
        let decoded = try JSONDecoder().decode([String: [Int]].self, from: data)
        guard let highest = decoded.max(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }),
              let version = Int(highest.key) else {
            throw URLError(.cannotParseResponse)
        }
        return Secret(version: version, cipherBytes: highest.value)
    }

    /// Reproduces Spotify web player's obfuscation: XOR each cipher byte with
    /// a position-derived value, then use the decimal-digit concatenation of
    /// the result as the raw HMAC key (equivalent to base32-encoding it and
    /// letting a TOTP library immediately decode it back — so that round
    /// trip is skipped here).
    public static func secretKeyData(fromCipherBytes cipherBytes: [Int]) -> Data {
        let transformed = cipherBytes.enumerated().map { index, value in value ^ ((index % 33) + 9) }
        let joined = transformed.map(String.init).joined()
        return Data(joined.utf8)
    }

    /// Standard RFC 6238 TOTP (HMAC-SHA1, 6 digits, 30s period).
    public static func code(keyData: Data, unixTime: Int, digits: Int = 6, period: Int = 30) -> String {
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
