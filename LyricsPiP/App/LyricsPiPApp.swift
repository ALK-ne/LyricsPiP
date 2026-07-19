import SwiftUI
import UIKit

/// Supplies the app's supported interface orientations dynamically so the
/// rotate buttons can temporarily lock orientation. Called on the main thread
/// by UIKit; `assumeIsolated` is safe here.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationManager.shared.supportedMask }
    }
}

@main
struct LyricsPiPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var sessionClient = SpotifyWebSessionClient()
    @StateObject private var watcher: PlaybackWatcher
    @StateObject private var syncEngine: LyricsSyncEngine

    init() {
        let session = SpotifyWebSessionClient()
        let watcher = PlaybackWatcher(sessionClient: session)
        let spotifyLyrics = SpotifyLyricsService(sessionClient: session)
        _sessionClient = StateObject(wrappedValue: session)
        _watcher = StateObject(wrappedValue: watcher)
        _syncEngine = StateObject(wrappedValue: LyricsSyncEngine(watcher: watcher, spotifyLyrics: spotifyLyrics))
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
