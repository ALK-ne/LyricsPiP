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

            // Must actually be part of the rendered view hierarchy for
            // AVPictureInPictureController.isPictureInPicturePossible to ever
            // become true — see PiPDisplayLayerView.swift. A prior 4x4/near-
            // invisible size may itself have been the cause of the PIP window
            // rendering solid black, so this is now a real, visible mini
            // preview at a reasonable size (also useful as a UX bonus).
            PiPHostView(controller: pipController)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(width: 160)
                .background(Color.black)
                .overlay(alignment: .topLeading) {
                    Text("PIPプレビュー").font(.caption2).foregroundStyle(.secondary).padding(2)
                }

            Button(pipController.isPiPActive ? "PIPを閉じる" : "PIPで表示") {
                if pipController.isPiPActive {
                    pipController.stop()
                } else {
                    pipController.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(syncEngine.lines.isEmpty || !pipController.isPiPPossible)

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
