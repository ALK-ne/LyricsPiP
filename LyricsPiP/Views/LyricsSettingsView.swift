import SwiftUI

/// Lets the user tune how many lyric lines the floating PiP window shows.
/// Presented as a sheet from `ContentView`.
struct LyricsSettingsView: View {
    @ObservedObject var settings: LyricsDisplaySettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("PiPの歌詞表示") {
                    Stepper(
                        value: $settings.nextLinesCount,
                        in: LyricsDisplaySettings.minNextLines...LyricsDisplaySettings.maxNextLines
                    ) {
                        Text("次の行数: \(settings.nextLinesCount)")
                    }
                    Toggle("1行前も表示", isOn: $settings.showPreviousLine)
                }

                Section {
                    Text("表示する行を増やすほど、PiPウィンドウは縦に大きくなります。「1行前も表示」をオンにすると、現在の行が中央に表示されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    LyricsSettingsView(settings: LyricsDisplaySettings())
}
