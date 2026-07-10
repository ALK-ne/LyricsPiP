import Foundation

public struct LyricLine: Equatable {
    public let time: TimeInterval
    public let text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public struct CurrentTrack: Equatable {
    public let id: String
    public let name: String
    public let artist: String
    public let album: String
    public let durationMs: Int

    public init(id: String, name: String, artist: String, album: String, durationMs: Int) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
    }
}
