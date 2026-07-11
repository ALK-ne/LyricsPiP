import Foundation

/// Response of `open.spotify.com/api/token` (web-player session token).
public struct SpotifyAccessToken: Decodable, Equatable, Sendable {
    public let clientId: String
    public let accessToken: String
    public let accessTokenExpirationTimestampMs: Int
    /// `true` is the only reliable signal that the sp_dc cookie itself is
    /// invalid — every other failure mode (429/WAF/outage) must be treated
    /// as transient. See SpotifyWebSessionClient.
    public let isAnonymous: Bool

    public var expirationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(accessTokenExpirationTimestampMs) / 1000)
    }
}
