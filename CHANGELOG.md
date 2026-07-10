# CHANGELOG

このプロジェクトの開発セッションごとの作業内容をまとめる。技術的な詳細・恒久的な注意点は`README.md`側に反映し、ここには「そのセッションで何をしたか」の記録を残す。

## 2026-07-10

### ビルド番号(`CFBundleVersion`)がずっと`1`のまま更新されない不具合の調査・修正

- `CURRENT_PROJECT_VERSION`をxcodebuildへのコマンドライン引数で渡す方式で試したが、コンパイル後のInfo.plistの`CFBundleVersion`が常に`1`のまま変わらない不具合が発覚。
- `project.yml`への事前埋め込み、生成後の`.pbxproj`の直接確認、`xcodebuild -showBuildSettings`、ビルド直後にCIランナー上で直接Info.plistを読む、と段階的に検証したが、すべての段階で正しい値(実行番号)が確認できるにもかかわらず、最終成果物だけ常に`1`になるという再現性のある不可解な挙動を確認。根本原因の特定は断念。
- 回避策として、ビルド後に`PlistBuddy`で`CFBundleVersion`を直接上書きする方式に変更し、確実に反映されることを確認(build 34で`v1.0 (build 34)`表示を確認)。
- 調査用の診断ステップ・`project.yml`の事前置換処理は最終的に削除し、`PlistBuddy`によるパッチのみを残してワークフローを整理。
- 整理中に誤って`Install XcodeGen`ステップを削除してしまいビルド失敗 → 即座に復元して解消。

### PIPの黒画面バグの修正・確認

- ダミー歌詞データでのPIP動作テストで、PIP自体は起動するもののウィンドウ内が真っ黒になる不具合を確認。
- 3つの原因を特定・修正:
  1. `AVSampleBufferDisplayLayer`が実際のSwiftUIビュー階層に存在しないと`isPictureInPicturePossible`が真にならない → `PiPDisplayLayerView.swift`を新設し、アプリ内プレビューとして実際に描画されるようにした。
  2. 静止画コンテンツ(動画クロックが進まない)には`kCMSampleAttachmentKey_DisplayImmediately`が無いと、フレームが永久に描画待ちのまま → サンプルバッファ生成時に付与するよう修正。
  3. `CVPixelBufferCreate`に`kCVPixelBufferIOSurfacePropertiesKey`が無いと、PIPのようなプロセス外合成が必要な用途ではエラー無しに何も表示されない → 生成時のattributesに追加。
- 実機での確認により、PIPウィンドウ内にダミー歌詞のテキストが正しく表示されることを確認。

### 長い歌詞行がPIP内で途切れる不具合の修正

- PIP動作確認中、文字数の多い行が矩形からはみ出て末尾が欠けて表示される不具合が発覚。
- `LyricsFrameRenderer`に、指定した幅に収まるまでフォントサイズを自動的に縮小してから描画するロジックを追加(縦方向も中央寄せに変更)。
- 実機で長短さまざまな行が正しく1行に収まって表示されることを確認。

### lrclib.net連携の単体検証(実機を使わずに)

- `curl`で実際のAPIレスポンスを取得し、`LyricsService.swift`が期待するJSON構造(`syncedLyrics`/`plainLyrics`)と一致することを確認。
- `LRCParser`の正規表現が実際のレスポンス形式(空行・複数行・日本語含む)を問題なくパースできることを確認。
- 洋楽(Queen "Bohemian Rhapsody")・邦楽(YOASOBI「夜に駆ける」)の両方でテスト。該当曲が無い場合の404 → `nil`フォールバックも確認。

### READMEの更新

- サイドロードツールがAltServerからSideloadlyに移行済みであることを反映(セットアップ手順・既知の落とし穴・継続運用の説明を全面更新)。
- 上記で判明したTOTP要件、実際のレート制限挙動(常時約30〜35秒に1回)、PIP修正内容、`CFBundleVersion`の謎の挙動、lrclib.net検証結果を「既知のリスク・制約」および新規セクションとして追記。

### 現状

- Issue #1(Macなし開発のデバッグループ改善策)のうち、項目1・2a・2b・4・5は実装済み、項目3(SideStore)・6(Sentry)は対象外。
- ダミー歌詞を使ったPIP表示の主要な不具合(黒画面・長い行の途切れ)は解消済み。
- 残タスク: 実際のSpotify再生を使った本番パイプライン(ログイン→曲検知→歌詞取得→PIP表示)の通し確認。
