import Foundation

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

struct CurrentTrack: Equatable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let durationMs: Int
}
