import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionClient: SpotifyWebSessionClient
    @EnvironmentObject private var watcher: PlaybackWatcher
    @EnvironmentObject private var syncEngine: LyricsSyncEngine
    @StateObject private var pipController = PiPLyricsController()

    @State private var showingLogin = false
    @State private var showingSettings = false

    /// Marketing version only (CFBundleShortVersionString), e.g. "v1.0".
    /// The CI build number (CFBundleVersion) is intentionally not shown.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(shortVersion)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if !sessionClient.isLoggedIn {
                    loggedOutView
                } else {
                    loggedInView
                }
            }
            .padding()
            .navigationTitle("LyricsPiP")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("設定")
                }
            }
            .sheet(isPresented: $showingLogin) {
                SpotifyLoginSheet { cookie in
                    sessionClient.saveSpDcCookie(cookie)
                }
            }
            .sheet(isPresented: $showingSettings) {
                LyricsSettingsView(settings: .shared)
            }
            .onAppear {
                pipController.attach(syncEngine: syncEngine)
            }
            // The display layer must stay in the rendered view hierarchy for
            // AVPictureInPictureController.isPictureInPicturePossible to become
            // true, but there's no visible PiP control anymore -- PiP starts/
            // stops automatically as the app backgrounds/foregrounds. Keep it
            // as a tiny, near-invisible layer with no layout footprint.
            .background(
                PiPHostView(controller: pipController)
                    .frame(width: 48, height: 16)
                    .opacity(0.02)
                    .allowsHitTesting(false)
            )
        }
    }

    private var loggedOutView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Spotifyにログインすると、再生中の曲を検知できます")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Spotifyにログイン") { showingLogin = true }
                .buttonStyle(.borderedProminent)
            if let error = sessionClient.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        }
    }

    private var loggedInView: some View {
        VStack(spacing: 16) {
            Text(Self.versionString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            trackHeader

            LyricsPreviewView(
                hasTrack: watcher.currentTrack != nil,
                lines: syncEngine.lines,
                activeIndex: syncEngine.activeIndex,
                noLyricsFound: syncEngine.noLyricsFound
            )
            .frame(maxHeight: .infinity)

            if let error = sessionClient.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button("ログアウト") { sessionClient.logout() }
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trackHeader: some View {
        if let track = watcher.currentTrack {
            VStack(spacing: 4) {
                Text(track.name).font(.headline)
                Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
            }
        } else {
            Text("再生中の曲が見つかりません")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SpotifyWebSessionClient())
        .environmentObject(PlaybackWatcher(sessionClient: SpotifyWebSessionClient()))
        .environmentObject(LyricsSyncEngine(
            watcher: PlaybackWatcher(sessionClient: SpotifyWebSessionClient()),
            spotifyLyrics: SpotifyLyricsService(sessionClient: SpotifyWebSessionClient())
        ))
}
