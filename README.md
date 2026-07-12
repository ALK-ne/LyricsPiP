# LyricsPiP

Spotifyで再生中の曲に同期して、歌詞をPicture-in-Picture(PIP)でフロート表示するiPhone向け個人利用アプリ。

**App Storeでの配布は想定していません。** Spotify Premium未加入・Mac非所持という前提のもと、非公式な手段(後述)を組み合わせて成立させています。

開発の経緯・調査の詳細な記録は[CHANGELOG.md](CHANGELOG.md)を参照してください。このREADMEには恒久的な情報(セットアップ手順・現在の仕様・既知の制約)のみを記載します。

将来的な拡張の調査メモ: [YouTube Music対応の実現可能性](docs/youtube-music-feasibility.md)(WKWebView埋め込み方式なら可能、という結論と設計の引き継ぎ資料)。

## なぜ非公式な仕組みなのか

- **曲検知**: Spotify公式のApp Remote SDK/Web APIは、2026年2月の規約変更で「Development ModeのアプリはオーナーがPremium契約中であること」が必須になった。Premium未加入のため使えない。当初は`sp_dc`クッキー由来トークンで公開Web API(`api.spotify.com`)の`currently-playing`を叩いていたが、2025年12月のSpotify変更でこのトークン種別は公開APIの全エンドポイントで実質ブロックされた(下記)。現在はSpotify Web Player本体と同じ**内部経路(`dealer.spotify.com`のWebSocket + `spclient.spotify.com`のconnect-state)**でリアルタイムに再生状態を受け取っている。
- **歌詞取得**: Spotify自身の同期歌詞(内部`color-lyrics`エンドポイント、Spotifyアプリと同じMusixmatch/syncpower製)を第一候補にし、無い場合は[lrclib.net](https://lrclib.net)の無料公開APIにフォールバック。Spotifyの歌詞はtrack IDだけで引けるためアーティスト名の解決が不要で、カバレッジもユーザーのライブラリと一致する。
- **ビルド環境**: Mac非所持のため、GitHub ActionsのmacOSランナー上でビルドし、SideStoreで実機にサイドロードする。

## 開発者が一度だけ行う手動セットアップ

### 1. リポジトリ

このリポジトリはパブリックのまま運用してください。GitHub Actionsの macOS ランナーは、パブリックリポジトリだと無料枠が無制限(プライベートだと10倍消費のクレジット制)になるためです。コミットされる情報にSpotifyの認証情報は含まれません(`sp_dc`クッキーは端末のKeychainにのみ保存されます)。

### 2. SideStoreのセットアップ(初回のみPCが必要)

サイドロードには[SideStore](https://sidestore.io)を使用しています(Sideloadly→AltStore→SideStoreと変遷。SideloadlyはApple側の変更にv0.60.0が未追従でログイン404が解消せず、AltStoreはPC上のAltServer常駐が必要なため、初回セットアップ後はPC不要になるSideStoreに落ち着いた)。

1. PCに[iloader](https://github.com/nab138/iloader/releases)をインストール(MSI版推奨。iTunes/Apple Mobile Device Supportが必要)。
2. iPhoneをUSBで接続し、iloaderを起動 → Apple IDでサインイン → デバイスを選択 → 「**Install SideStore (Stable)**」。ペアリングファイルの生成・配置まで自動で行われる。
   - 「Maximum certificates reached」と出た場合、既存の開発証明書(過去のAltStore/Sideloadlyの署名)を失効させて作り直す確認なので「Continue」でよい。既存の証明書で入れたアプリは起動不能になる。
3. iPhone側: 設定 → 一般 → VPNとデバイス管理で開発者証明書を信頼し、設定 → プライバシーとセキュリティで「デベロッパモード」をON(要再起動)。
4. App Storeから「**LocalDevVPN**」をインストールして接続(SideStoreの動作にはこのオンデバイスVPNの接続が必要。操作時だけONでよい)。
5. SideStoreを開き、同じApple IDでサインイン → 「My Apps」でSideStore自身をリフレッシュできれば完了。

### 3. CIビルドの取得とインストール(PC不要)

CIは`.ipa`をローリングリリース(タグ`latest`)にも添付するため、iPhone単体でインストールできます。

1. LocalDevVPNを接続(ON)にする。
2. iPhoneのSafariで `https://github.com/ALK-ne/LyricsPiP/releases/download/latest/LyricsPiP-unsigned.ipa` をダウンロード(`/releases/latest/download/`というURLはプレリリースを対象にしないため404になる。必ずこのタグ直指定URLを使う)。
3. SideStoreの「My Apps」→ 左上の「+」→ ファイルブラウザで「ダウンロード」フォルダの`.ipa`を選択。
   - Safariの共有メニューからSideStoreに渡す方法は「The file doesn't exist」エラーになることがあるため、この「+」ボタン経由が確実。

### 4. 継続的な運用

- 無料Apple IDの証明書は7日で失効しますが、SideStoreなら**iPhone単体でリフレッシュできます**(「My Apps」の「7 DAYS」カウンターをタップ。LocalDevVPN接続中に行うこと)。PCの常駐は不要です。
- ペアリングファイルはiOSアップデートやデバイスリセット時に失効することがあり、その際はPCのiloaderで再設定が必要です。
- 無料Apple IDには同時3アプリ・週10 App IDの制限があります(SideStore自身が1枠消費)。
- 署名し直すとアプリのKeychainは引き継がれないため、署名元が変わった際はSpotifyへの再ログインが必要です。
- アプリ初回起動時、Spotifyへのログイン画面(WKWebView)が表示されるので通常通りログインしてください。`sp_dc`クッキーを取得しKeychainに保存します。
- アプリ内(ログイン後の画面)に `vX.X (build N)` の形式でCIのビルド番号が表示されます。どのビルドが実機に入っているか判別するために使ってください。

## 実装状況

中核機能(Spotifyで再生中の曲を検知 → 歌詞取得 → PIPに同期表示)は**実機でエンドツーエンド動作確認済み**です。曲の切り替え・一時停止への追従、画面上・PIPウィンドウ両方での同期表示を確認しています。

- 曲検知(sp_dc認証 → dealer WebSocket/connect-stateでリアルタイム受信): 実機で動作確認済み。曲切り替えも即座に検知。
- 歌詞取得・同期(Spotify color-lyrics → lrclibフォールバック → LyricsSyncEngine): 実機で動作確認済み。再生位置に合わせてハイライト行が同期。lrclibに無い曲もSpotify側にあれば取得できる。
- PIP表示: **完全自動**(手動ボタンなし)。アプリをバックグラウンドに回すと自動でPIPが開始し、フォアグラウンドに戻すと自動で終了する。実際の同期歌詞の表示・長い行の自動縮小・他アプリ/ホーム画面切り替え後のバックグラウンド維持、いずれも実機で確認済み。

## 既知のリスク・制約

- **`sp_dc`クッキー方式は非公式**です。Spotifyの内部認証フローに依存しており、予告なく無効化される可能性があります。無効化された場合はアプリ内から再ログインしてください(自動復旧はできません)。
- **TOTPによるアンチスクレイピング対策**: Spotifyはトークン取得エンドポイント(`/api/token`)にTOTP検証を追加しています。秘密鍵はコミュニティミラー([xyloflake/spot-secrets-go](https://github.com/xyloflake/spot-secrets-go))から実行時に取得しており、ハードコードしていません。Spotify側が秘密鍵をローテーションすると、ミラーが追従するまでの間は認証が失敗する可能性があります。
- **公開Web API(`api.spotify.com`)はこのトークンでは使えません**。2025年12月のSpotify変更で、`sp_dc`由来のweb-playerトークン(clientId `d8a5ed95...`)は`api.spotify.com`の全エンドポイントが実質ブロックされました(`profile`/`search`/`devices`まで429、`/me/player`は1回叩くだけで24時間ブロックが再発動)。アカウント単位でもIP単位でもなく、このトークン種別に対する制限です。そのため曲検知は公開APIを一切使わず、Web Player本体と同じ内部経路(`dealer.spotify.com`のWebSocket + `spclient.spotify.com`のconnect-state)を使います。こちらは別ホストで push 型のため、レート制限の問題は起きません(`PlaybackWatcher`)。**`/me/player`等の公開APIは絶対に叩かないこと**(24時間ブロックを誘発します)。
- **`CFBundleVersion`はXcode標準の`$(CURRENT_PROJECT_VERSION)`置換では反映されません**(原因不明・未解決)。CIビルド後に`PlistBuddy`で直接書き換える方式で対応しています(`.github/workflows/ios-build.yml`の`Set CFBundleVersion directly in the built Info.plist`ステップ)。
- **開発ループが遅い**です。Mac/シミュレータが手元にないため、全ての動作確認は「push → CI → iPhoneでダウンロード → SideStoreインストール → 実機確認」のサイクルになります(SideStore移行によりPC側でのダウンロード・転送工程は無くなりました)。

## プロジェクト構成

```
LyricsPiP/
  project.yml                 # XcodeGen定義。*.xcodeprojはコミットせずCIで都度生成
  CHANGELOG.md                 # 開発セッションの経緯・調査記録
  LyricsPiP/
    App/                       # エントリポイント・Info.plist・entitlements
    Models/                    # LyricLine / CurrentTrack
    Services/                  # sp_dc認証・再生ポーリング・歌詞取得・同期ロジック
    Login/                     # SpotifyログインWebView
    PiP/                       # カスタムPIPコントローラ・フレーム描画
    Views/                     # SwiftUI画面
    Resources/                 # Assets.xcassets, silence.m4a(PIP維持用の無音ループ)
  LyricsPiPCore/                # UIKit非依存ロジックのSwiftPMパッケージ(後述)
  tools/                       # ローカル動作確認用スクリプト(後述)
  .github/workflows/
    ios-build.yml              # macos-14ランナーでの未署名ビルド
    simulator-smoke-test.yml   # シミュレータでのUIスモークテスト
```

## ローカルでの動作確認について

Windows環境のためXcode/iOSシミュレータは利用できません。実際のUI/PIP/Spotify連携の確認は、CI→SideStoreサイドロードのサイクルを通じて実機でのみ行えます。ただし以下のツールで、この遅いループに頼らずに済む部分もあります。

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

シミュレータは常にKeychainが空の状態で起動する(＝未ログイン画面しか検証できない)ため、`LyricsPiP/App/**`・`LyricsPiP/Views/**`・`LyricsPiP/Login/**`・`LyricsPiP/Resources/**`・`project.yml`に変更があった時だけ実行されます(手動実行は`workflow_dispatch`で可能)。

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

### `LyricsPiPCore/` — UIKit非依存ロジックの分離パッケージ

UIKit/Spotify通信に依存しない純粋なロジックは、独立したSwiftPMパッケージ`LyricsPiPCore/`に切り出してあります。アプリ本体(`project.yml`経由でXcodeプロジェクトが依存)とテストの両方がここを参照します。現在Coreに含まれるもの:

- `LRCParser`・`ActiveLineFinder`(現在行の二分探索)・`LyricLine`/`CurrentTrack`モデル
- `SpotifyTOTPLogic`(TOTPコード導出。ネットワーク取得はアプリ側`SpotifyTOTPProvider`が担当)
- `SpotifyAccessToken`/`SpotifyCurrentlyPlaying`/`LrclibTrack`(各APIレスポンスのモデルとパース)
- `PlaybackPositionInterpolator`(ポーリング間の再生位置補間)
- `HTTPClient`/`LyricsPiPLogging`プロトコル(サービス層のテスト用シーム。本番実装はアプリ側の`URLSessionHTTPClient`と`DebugLog`)

- **CI**: `unit-tests`ジョブが`cd LyricsPiPCore && swift test`を実行し、実機・シミュレータ不要で数秒〜十数秒でロジックの正しさを検証します。
- **ローカル(Windows)での実行**: winget経由で`Swift.Toolchain`をインストールすれば`swift`コマンド自体は使えますが、`swift test`(パッケージのビルド)にはMSVC(`cl.exe`/`link.exe`)を含むVisual Studio Build Toolsが別途必要です(未検証)。
