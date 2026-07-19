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
                    trackName: watcher.currentTrack?.name,
                    trackArtist: watcher.currentTrack?.artist,
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
            Group {
                if !sessionClient.isLoggedIn {
                    loggedOutView
                } else {
                    loggedInView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("LyricsPiP")
            .toolbar {
                if sessionClient.isLoggedIn {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            OrientationManager.shared.enterLandscape()
                        } label: {
                            Image(systemName: "rectangle.landscape.rotate")
                        }
                        .accessibilityLabel("横画面で歌詞表示")
                    }
                }
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
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("LyricsPiP")
                    .font(.title2.weight(.bold))
                Text("Spotifyにログインすると、再生中の曲を検知して歌詞を表示します")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showingLogin = true
            } label: {
                Text("Spotifyにログイン")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let error = sessionClient.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(24)
    }

    private var loggedInView: some View {
        VStack(spacing: 16) {
            trackHeader

            LyricsPreviewView(
                hasTrack: watcher.currentTrack != nil,
                lines: syncEngine.lines,
                activeIndex: syncEngine.activeIndex,
                noLyricsFound: syncEngine.noLyricsFound
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            if let error = sessionClient.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            footer
        }
        .padding()
    }

    @ViewBuilder
    private var trackHeader: some View {
        Group {
            if let track = watcher.currentTrack {
                VStack(spacing: 4) {
                    Text(track.name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("再生中の曲が見つかりません", systemImage: "music.note")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
        HStack {
            Text(Self.versionString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("ログアウト", role: .destructive) { sessionClient.logout() }
                .font(.footnote)
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
