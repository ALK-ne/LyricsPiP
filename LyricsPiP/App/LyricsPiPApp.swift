import SwiftUI

@main
struct LyricsPiPApp: App {
    @StateObject private var sessionClient = SpotifyWebSessionClient()
    @StateObject private var watcher: PlaybackWatcher
    @StateObject private var syncEngine: LyricsSyncEngine

    init() {
        let session = SpotifyWebSessionClient()
        let watcher = PlaybackWatcher(sessionClient: session)
        _sessionClient = StateObject(wrappedValue: session)
        _watcher = StateObject(wrappedValue: watcher)
        _syncEngine = StateObject(wrappedValue: LyricsSyncEngine(watcher: watcher))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionClient)
                .environmentObject(watcher)
                .environmentObject(syncEngine)
        }
    }
}
