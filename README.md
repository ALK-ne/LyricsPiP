# LyricsPiP

Spotifyで再生中の曲に同期して、歌詞をPicture-in-Picture(PIP)でフロート表示するiPhone向け個人利用アプリ。

**App Storeでの配布は想定していません。** Spotify Premium未加入・Mac非所持という前提のもと、非公式な手段(後述)を組み合わせて成立させています。詳しい設計判断の背景は `docs`（このリポジトリでは省略、開発時のプラン参照）を参照してください。

## なぜ非公式な仕組みなのか

- **曲検知**: Spotify公式のApp Remote SDK/Web APIは、2026年2月の規約変更で「Development ModeのアプリはオーナーがPremium契約中であること」が必須になった。Premium未加入のため使えず、代わりにSpotifyの内部Webセッション認証(`sp_dc`クッキー)を使って公式Web APIと同じ`/me/player/currently-playing`エンドポイントを叩く。
- **歌詞取得**: [lrclib.net](https://lrclib.net) の無料公開APIを利用(認証不要・同期歌詞対応)。
- **ビルド環境**: Mac非所持のため、GitHub ActionsのmacOSランナー上でビルドし、Windows版AltServerで実機にサイドロードする。

## 開発者が一度だけ行う手動セットアップ

### 1. リポジトリ

このリポジトリはパブリックのまま運用してください。GitHub Actionsの macOS ランナーは、パブリックリポジトリだと無料枠が無制限(プライベートだと10倍消費のクレジット制)になるためです。コミットされる情報にSpotifyの認証情報は含まれません(`sp_dc`クッキーは端末のKeychainにのみ保存されます)。

### 2. AltServerのセットアップ(Windows)

1. [altstore.io](https://altstore.io) からWindows版AltServerをインストール。
2. Apple Mobile Device Support(iTunesに同梱)がインストールされていることを確認。
3. iPhoneをUSBで接続し、"このコンピュータを信頼"を許可。
4. AltServerのトレイアイコンから「Install AltStore」を選択し、無料のApple IDでサインイン(AltServerが証明書発行・プロビジョニングを自動処理)。
5. iPhone側で 設定 → 一般 → VPNとデバイス管理 から開発者証明書を信頼。

### 3. CIビルドの取得とインストール

1. GitHub Actionsの `iOS unsigned build` ワークフローを実行(`main`へのpush、または手動 `workflow_dispatch`)。
2. 完了後、Actionsの実行結果から `LyricsPiP-unsigned-ipa` アーティファクトをダウンロード。
3. ダウンロードした `.ipa` をAltServerのトレイアイコンにドラッグ&ドロップしてインストール(AltServerが無料Apple IDで再署名して転送)。

### 4. 継続的な運用

- 無料Apple IDの証明書は7日で失効します。AltServerをWindows PC上で起動し続け、iPhoneが定期的に同じWiFiに参加していれば自動でリフレッシュされます。
- PCがスリープ/オフラインだと失効し、アプリが起動しなくなります。その場合は手順3を再実行してください。
- アプリ初回起動時、Spotifyへのログイン画面(WKWebView)が表示されるので通常通りログインしてください。`sp_dc`クッキーを取得しKeychainに保存します。

## 既知のリスク・制約

- **`sp_dc`クッキー方式は非公式**です。Spotifyの内部認証フローに依存しており、予告なく無効化される可能性があります。無効化された場合はアプリ内から再ログインしてください(自動復旧はできません)。
- **PIPのバックグラウンド維持は実機検証が必要**です。非動画コンテンツのPIPを他アプリ切り替え後も維持するための正確なオーディオセッション要件は、Appleのドキュメントだけでは確定できない部分があります(`PiPLyricsController.swift`のコメント参照)。
- **開発ループが遅い**です。Mac/シミュレータが手元にないため、全ての動作確認は「push → CI → ダウンロード → AltServerインストール → 実機確認」のサイクルになります。

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

Windows環境のためXcode/iOSシミュレータは利用できません。実際のUI/PIP/Spotify連携の確認は、CI→AltServerサイドロードのサイクルを通じて実機でのみ行えます。ただし以下のツールで、この遅いループに頼らずに済む部分もあります。

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

`ios-build.yml`の`simulator-smoke-test`ジョブが、iOSシミュレータでアプリを起動してスクリーンショットをartifactとして保存します。起動直後のクラッシュや画面崩れをCI上で検知できますが、PiP/Keychainなど実機依存の挙動はこれでは確認できません。

### `tools/libimobiledevice-win/` — 実機のリアルタイムシステムログ

[jrjr/libimobiledevice-windows](https://github.com/jrjr/libimobiledevice-windows) のプリコンパイル済みバイナリ(`idevicesyslog.exe`等)を使うと、USB接続したiPhoneのシステムログをWindowsから直接ストリーミングできます。オンスクリーンのデバッグログより詳細な情報(クラッシュ・OSレベルのエラー等)が必要な時に使ってください。バイナリ自体はリポジトリにコミットせず(`.gitignore`済み)、各自ダウンロードして配置します。

```
cd tools/libimobiledevice-win
./idevicesyslog.exe -p LyricsPiP
```

`-p LyricsPiP`でアプリ名によるフィルタが効き、ノイズの多いシステムログ全体から関係する行だけ抽出できます。クラッシュログが必要な場合は同梱の`idevicecrashreport.exe`が使えます。
