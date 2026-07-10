import Foundation
import LyricsPiPCore

/// Minimal on-screen debug log. There is no way to attach an Xcode console
/// to this app during development (no Mac in this project's workflow — see
/// README), so this surfaces what's happening directly in the UI instead.
///
/// Conforms to `LyricsPiPLogging` so services receive it as an injected
/// dependency (swappable in tests) rather than reaching for the singleton.
/// The singleton itself remains as the production default and for the
/// on-screen `DebugLogView`.
@MainActor
final class DebugLog: ObservableObject, LyricsPiPLogging {
    static let shared = DebugLog()

    @Published private(set) var lines: [String] = []
    @Published var remoteServerURLString: String {
        didSet {
            UserDefaults.standard.set(remoteServerURLString, forKey: Self.remoteURLKey)
        }
    }

    private static let remoteURLKey = "debug_log_remote_url"

    private let remoteSender = RemoteLogSender()

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        remoteServerURLString = UserDefaults.standard.string(forKey: Self.remoteURLKey) ?? ""
    }

    func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        lines.append(line)
        if lines.count > 400 {
            lines.removeFirst(lines.count - 400)
        }
        remoteSender.send(line, to: remoteServerURLString)
    }

    var fullText: String {
        lines.joined(separator: "\n")
    }

    func clear() {
        lines.removeAll()
    }
}

/// POSTs log lines to a PC on the same WiFi network (see tools/log-server.mjs)
/// — useful once the app is in PIP mode or backgrounded, where the on-screen
/// panel can't be read directly.
struct RemoteLogSender {
    /// Best-effort, fire-and-forget — a failed log upload must never affect
    /// app behavior, so no error handling here.
    func send(_ line: String, to urlString: String) {
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(line.utf8)
        URLSession.shared.dataTask(with: request).resume()
    }
}
