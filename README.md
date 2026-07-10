# LyricsPiP

Spotifyで再生中の曲に同期して、歌詞をPicture-in-Picture(PIP)でフロート表示するiPhone向け個人利用アプリ。

**App Storeでの配布は想定していません。** Spotify Premium未加入・Mac非所持という前提のもと、非公式な手段(後述)を組み合わせて成立させています。詳しい設計判断の背景は `docs`（このリポジトリでは省略、開発時のプラン参照）を参照してください。

## なぜ非公式な仕組みなのか

- **曲検知**: Spotify公式のApp Remote SDK/Web APIは、2026年2月の規約変更で「Development ModeのアプリはオーナーがPremium契約中であること」が必須になった。Premium未加入のため使えず、代わりにSpotifyの内部Webセッション認証(`sp_dc`クッキー)を使って公式Web APIと同じ`/me/player/currently-playing`エンドポイントを叩く。
- **歌詞取得**: [lrclib.net](https://lrclib.net) の無料公開APIを利用(認証不要・同期歌詞対応)。
- **ビルド環境**: Mac非所持のため、GitHub ActionsのmacOSランナー上でビルドし、Windows版Sideloadlyで実機にサイドロードする。

## 開発者が一度だけ行う手動セットアップ

### 1. リポジトリ

このリポジトリはパブリックのまま運用してください。GitHub Actionsの macOS ランナーは、パブリックリポジトリだと無料枠が無制限(プライベートだと10倍消費のクレジット制)になるためです。コミットされる情報にSpotifyの認証情報は含まれません(`sp_dc`クッキーは端末のKeychainにのみ保存されます)。

### 2. Sideloadlyのセットアップ(Windows)

サイドロードには[Sideloadly](https://sideloadly.io)を使用しています(AltServerから移行済み)。

1. [sideloadly.io](https://sideloadly.io) からWindows版をインストール。
2. Apple Mobile Device Support(iTunesに同梱)がインストールされていることを確認。
3. iPhoneをUSBで接続し、"このコンピュータを信頼"を許可。
4. Sideloadlyを起動し、iPhoneが認識されることを確認。

**既知の落とし穴**: 「Local Anisette」関連の致命的エラー(`iTunesCore.dll`が見つからない/壊れている)や、ログイン時の404エラーが発生することがある。この場合はSideloadlyを**完全にアンインストールしてから再インストール**し、`%LOCALAPPDATA%\Sideloadly`のキャッシュ状態を消してから再構成すると解消することを確認済み。エラーが出てもAltServerへ戻さず、Sideloadly自体を直す方針で対応する。

### 3. CIビルドの取得とインストール

1. GitHub Actionsの `iOS unsigned build` ワークフローを実行(`main`へのpush、または手動 `workflow_dispatch`)。
2. 完了後、Actionsの実行結果から `LyricsPiP-unsigned-ipa` アーティファクトをダウンロード。
3. ダウンロードした `.ipa` をSideloadlyにドラッグ&ドロップし、無料のApple IDでサインインして「Start」を押す(Sideloadlyが無料Apple IDで再署名して転送)。

### 4. 継続的な運用

- 無料Apple IDの証明書は7日で失効します。**Sideloadlyには証明書を自動更新し続けるバックグラウンド常駐機能はない**ため(AltServerの「PCを起動しっぱなしにしておけば自動リフレッシュ」という運用とは違う)、7日ごとに手順3を再実行してインストールし直す必要があります。
- アプリ初回起動時、Spotifyへのログイン画面(WKWebView)が表示されるので通常通りログインしてください。`sp_dc`クッキーを取得しKeychainに保存します。
- アプリ内(ログイン後の画面)に `vX.X (build N)` の形式でCIのビルド番号が表示されます。どのビルドが実機に入っているか判別するために使ってください。

## 既知のリスク・制約

- **`sp_dc`クッキー方式は非公式**です。Spotifyの内部認証フローに依存しており、予告なく無効化される可能性があります。無効化された場合はアプリ内から再ログインしてください(自動復旧はできません)。
- **TOTPによるアンチスクレイピング対策**: Spotifyはトークン取得エンドポイント(`/api/token`)にTOTP(Time-based One-Time Password)検証を追加しています。秘密鍵はコミュニティが継続的に追跡しているミラー([xyloflake/spot-secrets-go](https://github.com/xyloflake/spot-secrets-go))から実行時に取得しており(`SpotifyTOTP.swift`)、ハードコードしていません。Spotify側が秘密鍵をローテーションすると、このミラーが追従するまでの間は認証が失敗する可能性があります。
- **`currently-playing`ポーリングのレート制限は「常時」かかっています**。実測(`tools/spotify-auth-repro.mjs`によるローカル再現で確認)では、このトークン種別に対して約30〜35秒に1回という恒常的な制限があり、長時間待っても解除される一時的なペナルティではありません(以前「24時間ブロック」と誤診断した`Retry-After: 86400`は、実際には別の一時的な事象で、数十分〜1時間程度で自然に解消しました)。`PlaybackPoller`はこれを踏まえて40秒間隔でポーリングし、レート制限中はアプリ内にオレンジ色の警告バナーを表示します。
- **PIPの黒画面バグは解消済み**です。当初は「PIPは起動するが真っ黒」という状態でしたが、原因は3つありました: (1) `AVSampleBufferDisplayLayer`が実際のSwiftUIビュー階層に存在しないと`isPictureInPicturePossible`が真にならない、(2) 静止画(動画クロックが進まないコンテンツ)には`kCMSampleAttachmentKey_DisplayImmediately`が無いとフレームが永久に描画待ちのまま、(3) `CVPixelBufferCreate`に`kCVPixelBufferIOSurfacePropertiesKey`を渡さないと、PIPのようなプロセス外合成が必要な用途ではエラー無しに何も表示されない。いずれも`LyricsFrameRenderer.swift`/`PiPLyricsController.swift`で対応済みで、実機のダミー歌詞テストで表示を確認済みです。あわせて、長い歌詞行が固定フォントサイズで表示範囲からはみ出て欠ける問題も、フォントサイズを自動縮小するよう修正済みです。
- **PIPのバックグラウンド維持そのものは実機検証が必要**です(黒画面は解消済みですが、他アプリ切り替え後も安定してPIPウィンドウが維持され続けるかの継続検証は必要です)。
- **開発ループが遅い**です。Mac/シミュレータが手元にないため、全ての動作確認は「push → CI → ダウンロード → Sideloadlyインストール → 実機確認」のサイクルになります。
- **`CFBundleVersion`のXcode標準の置換(`$(CURRENT_PROJECT_VERSION)`)は原因不明でこのプロジェクトでは効きません**。xcodebuildへのコマンドライン引数、`project.yml`、生成後の`.pbxproj`、`xcodebuild -showBuildSettings`、ビルド直後にCIランナー上で直接読んだInfo.plist — すべてで正しい値が確認できるにもかかわらず、最終的にコンパイルされたInfo.plistだけは常に`CFBundleVersion=1`になるという現象が再現し、根本原因は特定できませんでした。回避策として、ビルド後に`PlistBuddy`で`CFBundleVersion`を直接書き換えるようにしています(`.github/workflows/ios-build.yml`の`Set CFBundleVersion directly in the built Info.plist`ステップ)。

## プロジェクト構成

```
LyricsPiP/
  project.yml                 # XcodeGen定義。*.xcodeprojはコミットせずCIで都度生成
  LyricsPiP/
    App/                       # エントリポイント・Info.plist・entitlements
    Models/                    # LyricLine / CurrentTrack
    Services/                  # sp_dc認証・再生ポーリング・歌詞取得・同期ロジック
    Login/                     # SpotifyログインWebView
    PiP/                       # カスタムPIPコントローラ・フレーム描画
    Views/                     # SwiftUI画面
    Resources/                 # Assets.xcassets, silence.m4a(PIP維持用の無音ループ)
  .github/workflows/
    ios-build.yml              # macos-14ランナーでの未署名ビルド + シミュレータ単体テスト
```

## ローカルでの動作確認について

Windows環境のためXcode/iOSシミュレータは利用できません。実際のUI/PIP/Spotify連携の確認は、CI→Sideloadlyサイドロードのサイクルを通じて実機でのみ行えます。ただし以下のツールで、この遅いループに頼らずに済む部分もあります。

### `tools/spotify-auth-repro.mjs` — 認証フローのローカル再現

`sp_dc`クッキー → TOTP付きトークン取得 → `currently-playing`という一連の認証フローは純粋なHTTP通信なので、iPhone無しでNode.js(18+)で再現できます。

```
node tools/spotify-auth-repro.mjs <sp_dcクッキーの値>
```

リクエストの形やヘッダーを試行錯誤する際、CIビルドを待たずに数秒で結果が見られます。`Services/SpotifyTOTP.swift` / `Services/SpotifyWebSessionClient.swift`のSwift実装と同じロジックです。

### `tools/log-server.mjs` — リモートログ受信サーバー

PIPでバックグラウンドに回った後などオンスクリーンのデバッグログが見えない場面向けに、同一WiFi上のPCへログをPOSTで送る簡易サーバーです。

```
node tools/log-server.mjs 8787
```

起動後に表示されるURL(例: `http://192.168.1.5:8787/log`)を、アプリ内デバッグログパネルの「リモートログサーバー」欄に入力してください。

### CIのシミュレータスモークテスト

`simulator-smoke-test.yml`(独立したワークフロー)が、iOSシミュレータでアプリを起動してスクリーンショットをartifactとして保存します。起動直後のクラッシュや画面崩れをCI上で検知できますが、PiP/Keychainなど実機依存の挙動はこれでは確認できません。

シミュレータは常にKeychainが空の状態で起動する(＝未ログイン画面しか検証できない)ため、`LyricsPiP/App/**`・`LyricsPiP/Views/**`・`LyricsPiP/Login/**`・`LyricsPiP/Resources/**`・`project.yml`に変更があった時だけ実行されます。Spotify連携やPIP内部ロジックのみの変更では走りません(手動実行は`workflow_dispatch`で可能)。

### `tools/libimobiledevice-win/` — 実機のリアルタイムシステムログ

[jrjr/libimobiledevice-windows](https://github.com/jrjr/libimobiledevice-windows) のプリコンパイル済みバイナリ(`idevicesyslog.exe`等)を使うと、USB接続したiPhoneのシステムログをWindowsから直接ストリーミングできます。オンスクリーンのデバッグログより詳細な情報(クラッシュ・OSレベルのエラー等)が必要な時に使ってください。バイナリ自体はリポジトリにコミットせず(`.gitignore`済み)、各自ダウンロードして配置します。

```
cd tools/libimobiledevice-win
./idevicesyslog.exe -p LyricsPiP
```

`-p LyricsPiP`でアプリ名によるフィルタが効き、ノイズの多いシステムログ全体から関係する行だけ抽出できます。クラッシュログが必要な場合は同梱の`idevicecrashreport.exe`が使えます。

### lrclib.net連携の単体検証(実機不要)

`LyricsService.swift`が叩く[lrclib.net](https://lrclib.net) `/api/get`は認証不要のREST APIなので、`curl`でリクエスト形式・レスポンス形式を実機無しで検証できます。

```
curl -s "https://lrclib.net/api/get?artist_name=<アーティスト>&track_name=<曲名>&album_name=<アルバム>&duration=<秒>" \
  -H "User-Agent: LyricsPiP (personal use)"
```

洋楽(Queen "Bohemian Rhapsody")・邦楽(YOASOBI「夜に駆ける」)の両方で動作確認済み: レスポンスのキー(`syncedLyrics`/`plainLyrics`)は`LyricsService.swift`の`Decodable`構造体とキー変換無しで一致し、`LRCParser`の正規表現も実際の`[mm:ss.xx]`形式(空行・日本語含む)を問題なくパースできることを確認しています。該当曲が無い場合は404が返り、既存の`nil`フォールバックと一致します。曲名の表記揺れなど実際のSpotify連携特有の精度は、Spotify側が動くようになってからでないと検証できません。

### `LyricsPiPCore/` — UIKit非依存ロジックの分離パッケージ

`LRCParser`・`ActiveLineFinder`(現在行の二分探索)・`LyricLine`/`CurrentTrack`モデルは、UIKit/Spotify通信に依存しない純粋なロジックなので、独立したSwiftPMパッケージ`LyricsPiPCore/`に切り出してあります。アプリ本体(`project.yml`経由でXcodeプロジェクトが依存)とテストの両方がここを参照します。

- **CI**: `unit-tests`ジョブが`cd LyricsPiPCore && swift test`を実行し、実機・シミュレータ不要で数秒〜十数秒でロジックの正しさを検証します。
- **ローカル(Windows)での実行**: winget経由で`Swift.Toolchain`をインストールすれば`swift`コマンド自体は使えますが、`swift test`(パッケージのビルド)にはMSVC(`cl.exe`/`link.exe`)を含むVisual Studio Build Toolsが別途必要です(未検証・重いインストールになるため今回は見送り)。ネイティブWindowsでの完全ローカル実行を試す場合はこの点に注意してください。
