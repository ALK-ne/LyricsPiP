import Foundation

public enum SpotifyID {
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// Converts a 22-char base62 Spotify id (the part after `spotify:track:`)
    /// into its 32-char hex GID, as required by the internal
    /// `spclient.spotify.com/metadata/4/track/<gid>` endpoint. Returns nil for
    /// malformed input or values that overflow 128 bits.
    public static func gidHex(fromBase62 id: String) -> String? {
        guard !id.isEmpty else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16)
        for ch in id {
            guard let digit = alphabet.firstIndex(of: ch) else { return nil }
            // bytes = bytes * 62 + digit (big-endian base-256 accumulation)
            var carry = digit
            var i = bytes.count - 1
            while i >= 0 {
                let v = Int(bytes[i]) * 62 + carry
                bytes[i] = UInt8(v & 0xff)
                carry = v >> 8
                i -= 1
            }
            if carry != 0 { return nil } // doesn't fit in 128 bits — invalid id
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Extracts the id from a `spotify:track:<id>` / `spotify:artist:<id>` URI
    /// (or returns the input unchanged if it's already a bare id).
    public static func bareId(fromURI uri: String) -> String {
        uri.components(separatedBy: ":").last ?? uri
    }
}

/// Subset of the internal `metadata/4/track` response used to recover an
/// authoritative artist name when the connect-state cluster omits `artist_name`
/// (which happens for playlist-context playback — only `artist_uri` is given).
public struct SpotifyTrackMetadata: Decodable, Equatable, Sendable {
    public let name: String?
    public let artist: [Artist]?
    public let album: Album?

    public struct Artist: Decodable, Equatable, Sendable {
        public let name: String?
    }
    public struct Album: Decodable, Equatable, Sendable {
        public let name: String?
    }

    public var artistName: String? {
        artist?.compactMap { $0.name }.first { !$0.isEmpty }
    }
    public var albumName: String? {
        album?.name
    }
}
