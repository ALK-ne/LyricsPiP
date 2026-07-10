import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionClient: SpotifyWebSessionClient
    @EnvironmentObject private var poller: PlaybackPoller
    @EnvironmentObject private var syncEngine: LyricsSyncEngine
    @StateObject private var pipController = PiPLyricsController()

    @State private var showingLogin = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

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
            .safeAreaInset(edge: .top) {
                Text(Self.versionString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
            }
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
            if let until = poller.rateLimitedUntil, until > Date() {
                Text("Spotifyのレート制限中です。\(Self.timeFormatter.string(from: until))頃まで自動では再試行しません。アプリを閉じずにお待ちください。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            trackHeader

            Button("テスト用ダミー歌詞を読み込む(PIP確認用)") {
                syncEngine.loadDebugLyrics()
            }
            .font(.footnote)

            LyricsPreviewView(
                hasTrack: poller.currentTrack != nil || !syncEngine.lines.isEmpty,
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
        if let track = poller.currentTrack {
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
        .environmentObject(PlaybackPoller(sessionClient: SpotifyWebSessionClient()))
        .environmentObject(LyricsSyncEngine(poller: PlaybackPoller(sessionClient: SpotifyWebSessionClient())))
}
