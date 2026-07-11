import Foundation
import LyricsPiPCore

/// Watches Spotify playback in realtime over the internal dealer WebSocket +
/// connect-state path (the same mechanism open.spotify.com's web player uses),
/// and interpolates position between updates for smooth lyric sync.
///
/// This replaces the old `api.spotify.com/me/player/currently-playing` polling:
/// as of Spotify's December 2025 change, the sp_dc/web-player token is
/// rate-limited to uselessness on every public Web API endpoint, while this
/// internal path stays fully functional and is push-based (track changes arrive
/// instantly instead of after a poll interval). See README.
///
/// Exposes the same `@Published` surface as the old poller so `LyricsSyncEngine`
/// and the UI are unaffected.
@MainActor
final class PlaybackWatcher: ObservableObject {
    @Published private(set) var currentTrack: CurrentTrack?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var estimatedPositionMs: Int = 0

    private let sessionClient: SpotifyWebSessionClient
    private let httpClient: any HTTPClient
    private let logger: any LyricsPiPLogging

    private var runTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var safetyTask: Task<Void, Never>?

    private var webSocket: URLSessionWebSocketTask?
    private var connectionId: String?
    private var quickRefreshTask: Task<Void, Never>?
    // Bounds the fast follow-up refreshes used to catch not-yet-hydrated
    // artist metadata, so a track that genuinely has no artist can't spin.
    private var partialRefreshCount = 0
    private let maxPartialRefreshes = 3
    private var spclientHost = "gae2-spclient.spotify.com:443"
    // A stable per-process device id so repeated connect-state PUTs update the
    // same hidden "device" instead of registering a new one each time.
    private let deviceId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

    private var interpolator = PlaybackPositionInterpolator()
    private var isPaused = true

    private let tickInterval: TimeInterval = 0.2
    private let safetyRefreshInterval: TimeInterval = 25.0
    private let pingInterval: TimeInterval = 30.0
    private let reconnectDelay: TimeInterval = 5.0

    init(
        sessionClient: SpotifyWebSessionClient,
        httpClient: any HTTPClient = URLSessionHTTPClient.shared,
        logger: (any LyricsPiPLogging)? = nil
    ) {
        self.sessionClient = sessionClient
        self.httpClient = httpClient
        self.logger = logger ?? DebugLog.shared
        start()
    }

    func start() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if !self.sessionClient.isLoggedIn {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                await self.runConnection()
                // Connection ended (error, close, or logout) — back off, retry.
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: UInt64(self.reconnectDelay * 1_000_000_000))
            }
        }
        tickTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.tickInterval * 1_000_000_000))
                self.tick()
            }
        }
    }

    func stop() {
        runTask?.cancel(); runTask = nil
        tickTask?.cancel(); tickTask = nil
        teardownConnection()
    }

    private func tick() {
        guard !isPaused else { return }
        estimatedPositionMs = interpolator.position(at: Date())
    }

    // MARK: - Connection lifecycle

    private func runConnection() async {
        do {
            let token = try await sessionClient.validAccessToken()
            await resolveSpclientHost(token: token)

            guard let url = URL(string: "wss://dealer.spotify.com/?access_token=\(token)") else { return }
            let ws = URLSession.shared.webSocketTask(with: url)
            webSocket = ws
            connectionId = nil
            ws.resume()
            logger.log("[Watch] dealer WebSocket接続")

            startPing()
            startSafetyRefresh()

            // Receive loop: runs until the socket errors or closes.
            while !Task.isCancelled {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { await handleMessage(text) }
                @unknown default:
                    break
                }
            }
        } catch {
            logger.log("[Watch] 接続エラー: \(error.localizedDescription)")
        }
        teardownConnection()
    }

    private func teardownConnection() {
        pingTask?.cancel(); pingTask = nil
        safetyTask?.cancel(); safetyTask = nil
        quickRefreshTask?.cancel(); quickRefreshTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        connectionId = nil
    }

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.pingInterval * 1_000_000_000))
                guard let ws = self.webSocket else { return }
                // Dealer keeps the connection alive on an app-level ping frame.
                try? await ws.send(.string(#"{"type":"ping"}"#))
            }
        }
    }

    /// A low-frequency re-subscribe that catches pause/seek and any missed push,
    /// hitting the (non-rate-limited) connect-state host rather than the public API.
    private func startSafetyRefresh() {
        safetyTask?.cancel()
        safetyTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.webSocket != nil {
                try? await Task.sleep(nanoseconds: UInt64(self.safetyRefreshInterval * 1_000_000_000))
                guard self.connectionId != nil else { continue }
                await self.refreshClusterState()
            }
        }
    }

    // MARK: - Message handling

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // The first message carries the connection id we need for connect-state.
        if let headers = obj["headers"] as? [String: Any],
           let connId = headers["Spotify-Connection-Id"] as? String {
            connectionId = connId
            logger.log("[Watch] connection_id取得、購読します")
            await refreshClusterState()
            return
        }

        // Any subsequent connect-state message is a signal that playback changed.
        // Rather than parse the (possibly gzipped) push payload, re-fetch the
        // clean full cluster via connect-state.
        if let uri = obj["uri"] as? String, uri.contains("connect-state") {
            await refreshClusterState()
        }
    }

    // MARK: - connect-state

    private func refreshClusterState() async {
        guard let connectionId else { return }
        do {
            let token = try await sessionClient.validAccessToken()
            guard let url = URL(string: "https://\(spclientHost)/connect-state/v1/devices/hobs_\(deviceId)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(connectionId, forHTTPHeaderField: "X-Spotify-Connection-Id")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(SpotifyWebConstants.browserUserAgent, forHTTPHeaderField: "User-Agent")
            request.httpBody = Self.subscribeBody

            let (data, http) = try await httpClient.data(for: request)
            guard http.statusCode == 200 else {
                logger.log("[Watch] connect-state応答: HTTP \(http.statusCode)")
                return
            }
            guard let snapshot = SpotifyClusterParser.parse(data) else { return }
            apply(snapshot)
        } catch {
            logger.log("[Watch] connect-state例外: \(error.localizedDescription)")
        }
    }

    private func apply(_ snapshot: PlaybackSnapshot) {
        isPaused = snapshot.isPaused
        isPlaying = !snapshot.isPaused

        // Guard against transient partial cluster updates dropping artist/title
        // for the track that's already playing (see TrackMetadataMerge).
        let resolved = TrackMetadataMerge.resolve(existing: currentTrack, incoming: snapshot.track)
        let isNewTrack = resolved?.id != currentTrack?.id
        if isNewTrack {
            if let t = resolved {
                logger.log("[Watch] 曲検知: \(t.name) / \(t.artist)")
            }
            currentTrack = resolved
            partialRefreshCount = 0
        } else if resolved != currentTrack {
            // Same track, richer metadata (e.g. artist filled back in) — update
            // quietly without re-logging a "song detected" line.
            currentTrack = resolved
        }

        // If the artist hasn't hydrated yet (common right after a rapid skip),
        // pull a fresh cluster shortly after — hydration doesn't always emit its
        // own push. Bounded so a track with genuinely no artist can't loop.
        if let t = currentTrack, !t.name.isEmpty, t.artist.isEmpty, partialRefreshCount < maxPartialRefreshes {
            partialRefreshCount += 1
            scheduleQuickRefresh()
        }

        // position_as_of_timestamp was measured at snapshot.timestampMs (Spotify
        // server epoch-ms). Advance it by the transit delay so the anchor is
        // "position right now", then let the local tick extrapolate from there.
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let transit = snapshot.isPaused ? 0 : max(0, Int(nowMs - snapshot.timestampMs))
        let anchored = snapshot.positionMs + transit
        interpolator.rebase(positionMs: anchored, at: Date())
        estimatedPositionMs = anchored
    }

    private func scheduleQuickRefresh() {
        quickRefreshTask?.cancel()
        quickRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled, self.connectionId != nil else { return }
            await self.refreshClusterState()
        }
    }

    private func resolveSpclientHost(token: String) async {
        guard let url = URL(string: "https://apresolve.spotify.com/?type=spclient") else { return }
        var request = URLRequest(url: url)
        request.setValue(SpotifyWebConstants.browserUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, http) = try? await httpClient.data(for: request), http.statusCode == 200 else { return }
        struct Resolve: Decodable { let spclient: [String]? }
        if let resolved = try? JSONDecoder().decode(Resolve.self, from: data),
           let host = resolved.spclient?.first {
            spclientHost = host
        }
    }

    private static let subscribeBody: Data = {
        let body: [String: Any] = [
            "member_type": "CONNECT_STATE",
            "device": [
                "device_info": [
                    "capabilities": [
                        "can_be_player": false,
                        "hidden": true,
                        "needs_full_player_state": true
                    ]
                ]
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }()
}
