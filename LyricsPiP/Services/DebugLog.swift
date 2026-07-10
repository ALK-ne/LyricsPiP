import Foundation

/// Minimal on-screen debug log. There is no way to attach an Xcode console
/// to this app during development (no Mac in this project's workflow — see
/// README), so this surfaces what's happening directly in the UI instead.
@MainActor
final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    @Published private(set) var lines: [String] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    func log(_ message: String) {
        let timestamp = formatter.string(from: Date())
        lines.append("[\(timestamp)] \(message)")
        if lines.count > 400 {
            lines.removeFirst(lines.count - 400)
        }
    }

    var fullText: String {
        lines.joined(separator: "\n")
    }

    func clear() {
        lines.removeAll()
    }
}
