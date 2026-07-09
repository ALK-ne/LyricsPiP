import SwiftUI
import WebKit

/// Presents Spotify's normal web login page in a WKWebView and extracts the
/// `sp_dc` session cookie once login succeeds. This cookie is what
/// `SpotifyWebSessionClient` exchanges for short-lived Bearer tokens — no
/// Spotify Developer Dashboard registration or Premium subscription involved.
struct SpotifyLoginSheet: View {
    let onLoggedIn: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SpotifyLoginWebView { cookie in
                onLoggedIn(cookie)
                dismiss()
            }
            .navigationTitle("Spotifyにログイン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}

private struct SpotifyLoginWebView: UIViewControllerRepresentable {
    let onLoggedIn: (String) -> Void

    func makeUIViewController(context: Context) -> SpotifyLoginViewController {
        SpotifyLoginViewController(onLoggedIn: onLoggedIn)
    }

    func updateUIViewController(_ uiViewController: SpotifyLoginViewController, context: Context) {}
}

final class SpotifyLoginViewController: UIViewController {
    private let onLoggedIn: (String) -> Void
    private var webView: WKWebView!
    private var pollTimer: Timer?

    init(onLoggedIn: @escaping (String) -> Void) {
        self.onLoggedIn = onLoggedIn
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        webView = WKWebView(frame: view.bounds, configuration: WKWebViewConfiguration())
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)

        webView.load(URLRequest(url: URL(string: "https://accounts.spotify.com/login")!))

        // Login completion happens via JS redirects rather than a single clean
        // navigation event, so poll the cookie store instead of relying on
        // WKNavigationDelegate callbacks.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkForSessionCookie()
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func checkForSessionCookie() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            guard let spDc = cookies.first(where: { $0.name == "sp_dc" && $0.domain.hasSuffix("spotify.com") }) else {
                return
            }
            self.pollTimer?.invalidate()
            self.pollTimer = nil
            let value = spDc.value
            DispatchQueue.main.async {
                self.onLoggedIn(value)
            }
        }
    }
}
