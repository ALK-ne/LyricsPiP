import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Always-visible, copyable debug log panel. There's no way to attach an
/// Xcode console to this app during development (no Mac in this project's
/// workflow), so this is the only window into what's happening at runtime.
struct DebugLogView: View {
    @ObservedObject private var log = DebugLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("デバッグログ")
                    .font(.caption)
                    .bold()
                Spacer()
                Button("コピー") {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = log.fullText
                    #endif
                }
                .font(.caption)
                Button("消去") {
                    log.clear()
                }
                .font(.caption)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.fullText.isEmpty ? "(まだログはありません)" : log.fullText)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logBottom")
                }
                .onChange(of: log.lines.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
            .frame(height: 200)
            .background(Color.black.opacity(0.25))
            .cornerRadius(6)
        }
    }
}
