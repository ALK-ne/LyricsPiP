import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionClient: SpotifyWebSessionClient
    @EnvironmentObject private var watcher: PlaybackWatcher
    @EnvironmentObject private var syncEngine: LyricsSyncEngine
    @StateObject private var pipController = PiPLyricsController()

    @State private var showingLogin = false
    @State private var showingSettings = false

    // On iPhone this is .compact in landscape and .regular in portrait, so it
    // doubles as a reliable "is the app in landscape?" signal (foreground only,
    // which is exactly when this in-app view is shown).
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Marketing version only (CFBundleShortVersionString), e.g. "v1.0".
    /// The CI build number (CFBundleVersion) is intentionally not shown.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(shortVersion)"
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                // Landscape: full-screen in-app lyrics, mirroring the PiP
                // content and the same display settings.
                LandscapeLyricsView(
                    hasTrack: watcher.currentTrack != nil,
                    lines: syncEngine.lines,
                    activeIndex: syncEngine.activeIndex,
                    noLyricsFound: syncEngine.noLyricsFound,
                    settings: .shared
                )
            } else {
                portraitBody
            }
        }
        .onAppear {
            pipController.attach(syncEngine: syncEngine)
        }
        // The display layer must stay in the rendered view hierarchy for
        // AVPictureInPictureController.isPictureInPicturePossible to become
        // true. Attached at this outer level (not inside portraitBody) so it
        // stays mounted across portrait/landscape switches -- PiP is a
        // background feature and must survive the in-app landscape view.
        .background(
            PiPHostView(controller: pipController)
                .frame(width: 48, height: 16)
                .opacity(0.02)
                .allowsHitTesting(false)
        )
    }

    private var portraitBody: some View {
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
