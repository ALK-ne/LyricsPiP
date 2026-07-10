import Foundation

/// Minimal on-screen debug log. There is no way to attach an Xcode console
/// to this app during development (no Mac in this project's workflow — see
/// README), so this surfaces what's happening directly in the UI instead.
///
/// Optionally also POSTs each line to a local server on the same WiFi
/// network (see tools/log-server.mjs) — useful once the app is in PIP mode
/// or backgrounded, where the on-screen panel can't be read directly.
@MainActor
final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    @Published private(set) var lines: [String] = []
    @Published var remoteServerURLString: String {
        didSet {
            UserDefaults.standard.set(remoteServerURLString, forKey: Self.remoteURLKey)
        }
    }

    private static let remoteURLKey = "debug_log_remote_url"

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
        sendToRemoteServerIfConfigured(line)
    }

    var fullText: String {
        lines.joined(separator: "\n")
    }

    func clear() {
        lines.removeAll()
    }

    private func sendToRemoteServerIfConfigured(_ line: String) {
        guard !remoteServerURLString.isEmpty, let url = URL(string: remoteServerURLString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(line.utf8)
        // Best-effort, fire-and-forget — a failed log upload must never
        // affect app behavior, so no error handling here.
        URLSession.shared.dataTask(with: request).resume()
    }
}
