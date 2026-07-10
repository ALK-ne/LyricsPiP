import Foundation

enum SpotifyWebConstants {
    /// Browser-like User-Agent required by Spotify's web endpoints — a plain
    /// URLSession UA gets 403s from /api/token (see CHANGELOG section 3).
    /// Shared by the token flow and the currently-playing poller so both
    /// present the same client identity.
    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
