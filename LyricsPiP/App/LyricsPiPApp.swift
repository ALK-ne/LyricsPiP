import SwiftUI

@main
struct LyricsPiPApp: App {
    @StateObject private var sessionClient = SpotifyWebSessionClient()
    @StateObject private var poller: PlaybackPoller
    @StateObject private var syncEngine: LyricsSyncEngine

    init() {
        let session = SpotifyWebSessionClient()
        let poller = PlaybackPoller(sessionClient: session)
        _sessionClient = StateObject(wrappedValue: session)
        _poller = StateObject(wrappedValue: poller)
        _syncEngine = StateObject(wrappedValue: LyricsSyncEngine(poller: poller))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionClient)
                .environmentObject(poller)
                .environmentObject(syncEngine)
        }
    }
}
