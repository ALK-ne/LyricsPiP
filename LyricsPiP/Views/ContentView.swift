import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionClient: SpotifyWebSessionClient
    @EnvironmentObject private var watcher: PlaybackWatcher
    @EnvironmentObject private var syncEngine: LyricsSyncEngine
    @StateObject private var pipController = PiPLyricsController()

    @State private var showingLogin = false

    /// CFBundleVersion is set to the GitHub Actions run number at build time
    /// (see .github/workflows/ios-build.yml), so this identifies exactly
    /// which CI build is currently installed.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(shortVersion) (build \(build))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if !sessionClient.isLoggedIn {
                    loggedOutView
                } else {
                    loggedInView
                }

                DebugLogView()
            }
            .padding()
            .navigationTitle("LyricsPiP")
            .sheet(isPresented: $showingLogin) {
                SpotifyLoginSheet { cookie in
                    sessionClient.saveSpDcCookie(cookie)
                }
            }
            .onAppear {
                pipController.attach(syncEngine: syncEngine)
                pipController.prepare()
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

            Button(pipController.isPiPActive ? "PIPを閉じる" : "PIPで表示") {
                if pipController.isPiPActive {
                    pipController.stop()
                } else {
                    pipController.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(syncEngine.lines.isEmpty || !pipController.isPiPPossible)
            // The display layer must stay in the rendered view hierarchy for
            // AVPictureInPictureController.isPictureInPicturePossible to become
            // true, but the user doesn't want a visible preview. Keep it as a
            // tiny, near-invisible layer tucked behind the (opaque) button — it
            // takes no layout space and the PiP window's size comes from the
            // rendered frame, not this host view.
            .background(
                PiPHostView(controller: pipController)
                    .frame(width: 48, height: 16)
                    .opacity(0.02)
                    .allowsHitTesting(false)
            )

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
