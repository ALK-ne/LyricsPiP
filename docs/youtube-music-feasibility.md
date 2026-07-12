# YouTube Music 対応 — 実現可能性の調査と設計メモ

> このドキュメントは、将来 YouTube Music 対応を別セッションで実装する際の引き継ぎ資料です。
> 2026-07 時点の調査に基づきます。現行アプリは Spotify 専用として完成済み(README / CHANGELOG 参照)。
> Spotify 版のアーキテクチャ・実装を前提知識として書いています。

## 0. 結論(要約)

- **ネイティブ YouTube Music アプリの再生を「外から観測」する方式は不可能。** YouTube Music には Spotify Connect 相当の「別デバイスの再生状態をリアルタイムに配信する仕組み」が存在しない。iOS の MediaRemote(他アプリの Now Playing 読み取り)も iOS 16+ で封鎖済み(ユーザーは iOS 26)。
- **代わりに、アプリ内に WKWebView で YouTube Music web プレーヤーを埋め込み、その中で再生してもらう方式なら実現可能。** 我々自身が再生プレーヤーになるため、再生中の曲・再生位置・一時停止状態を JavaScript で直接読める。これは Spotify の「間接観測」よりむしろ素直。
- ただしこれは **「小さな YouTube Music クライアントを自作する」** ことに等しく、Spotify 版(受動的な観測者)とは設計思想が変わる、それなりの規模の新規開発になる。
- 最大の技術的ハードルは **WKWebView 内での Google ログイン**(Google が組み込み WebView でのログインをブロックする)。回避策は Spotify の `sp_dc` と同じ「正規ブラウザでログイン → 認証クッキーを WKWebView に注入」パターン。

## 1. なぜネイティブ観測方式は不可能か

Spotify 版が成立した肝は **Spotify Connect(`dealer.spotify.com` WebSocket + `connect-state`)** だった。これは「別デバイスで再生中の曲・位置・一時停止状態がサーバー経由でリアルタイム配信される」仕組みで、我々は隠しデバイスとして登録し傍受していた(`PlaybackWatcher.swift` 参照)。

YouTube Music にはこの同等物が無い:

| 手段 | 不可の理由 |
|---|---|
| ytmusicapi(非公式API) | ライブラリ・プレイリスト・検索用。リアルタイム now-playing 取得機能なし |
| クロスデバイスのキュー同期(2025頃追加) | 「キューの再開」機能。リアルタイム再生位置は取れず、クエリ可能な公開APIもなし |
| YouTube Music Remote 等 | サードパーティの **デスクトップ版** YT Music(Electron)+プラグイン前提。iPhone 純正アプリの検知には使えない |
| iOS MediaRemote / Now Playing | 全音楽アプリ共通で使える唯一の抽象化だが iOS 16+ で他アプリ情報取得が封鎖。脱獄なしでは不可 |

→ **「再生を外から観測する」路線は全滅。** 唯一残るのが「我々が再生プレーヤーになる」= WKWebView 埋め込み。

## 2. 採用すべきアーキテクチャ(WKWebView 埋め込み方式)

### 全体像

```
[我々のアプリ]
  ├─ WKWebView (music.youtube.com を表示・その中でユーザーが再生)
  │     ↑ Google 認証クッキーを注入してログイン済み状態にする
  │     ↓ JavaScript で再生状態をポーリング/監視
  ├─ YouTubeMusicWatcher (新規) ← WKWebView から読んだ状態を @Published で公開
  │     currentTrack / isPlaying / estimatedPositionMs
  ├─ LyricsSyncEngine (既存を流用)
  ├─ PiPLyricsController (既存を流用)
  └─ 歌詞ソース: lrclib (既存)、YT Music 自身の歌詞(後述)
```

### 最重要の設計方針: 既存の `@Published` インターフェースに合わせる

現行の `LyricsSyncEngine` と `PiPLyricsController` は、`PlaybackWatcher` の以下 3 つの `@Published` プロパティだけに依存している:

```swift
@Published private(set) var currentTrack: CurrentTrack?      // 曲名・アーティスト・アルバム・長さ・id
@Published private(set) var isPlaying: Bool
@Published private(set) var estimatedPositionMs: Int
```

**新規の `YouTubeMusicWatcher` を、この 3 つを同じ形で公開するよう作れば、`LyricsSyncEngine`・`PiPLyricsController`・`LyricsFrameRenderer`・PiP 周りは丸ごと流用できる。** 曲情報の取得元だけ差し替える形になり、Spotify 版で `PlaybackPoller` → `PlaybackWatcher` に差し替えたのと同じ構図。

理想的には `PlaybackSource` のようなプロトコルを切って、Spotify/YT Music を選択式にできると綺麗(将来的なリファクタ)。

### JavaScript による再生状態の読み取り

WKWebView 内の YT Music web プレーヤーから、`WKWebView.evaluateJavaScript` で以下を定期取得(または `WKScriptMessageHandler` で push):

```javascript
// 再生位置・一時停止(HTML5 media 要素から)
const v = document.querySelector('video');   // YT Music は video 要素で音声再生
v.currentTime;   // 秒。* 1000 で ms
v.paused;
v.duration;

// 曲情報(navigator.mediaSession が最も安定)
navigator.mediaSession.metadata.title;
navigator.mediaSession.metadata.artist;
navigator.mediaSession.metadata.album;
// フォールバックで DOM: ytmusic-player-bar の .title / .byline
```

- `video.currentTime` はミリ秒精度で正確な再生位置が取れる → **Spotify のような補間(`PlaybackPositionInterpolator`)は不要になるか、より正確にできる。**
- 曲の一意 id は YT Music の videoId(URL や `ytmusic` 内部状態から取得)。歌詞ソースのキャッシュキーに使える。
- ポーリングは 0.2〜0.5 秒間隔で十分軽い(同一プロセス内の JS 評価なのでネットワーク不要)。

## 3. 技術リスクと対策

### リスク A: Google ログイン(最大の壁)

Google は **組み込み WebView 内での直接ログインを「安全でないブラウザ」としてブロック**する(OAuth 2.0 authorization endpoint のポリシー。keylogger 等の懸念のため)。WKWebView で `accounts.google.com` に直接ログインしようとすると弾かれる。

**対策(Spotify の `sp_dc` と同じ発想):**
1. ログイン自体は `SFSafariViewController` または外部 Safari(= Google が認める正規ブラウザ)で行わせる
2. ログイン後、Google の認証クッキー(`__Secure-1PSID` / `__Secure-3PSID` / `SID` / `HSID` / `SSID` / `APISID` / `SAPISID` 等)を取得
3. それらを我々の WKWebView の `WKHTTPCookieStore` に注入 → 埋め込みプレーヤーがログイン済みになる

- Spotify は `sp_dc` 1 個で済んだが、Google は複数クッキーが絡み、Google 側の対策も積極的なので **より脆く不安定** な想定。
- クッキーの取得を SFSafariViewController から我々のアプリへ渡す部分が技術的に厄介(SFSafariViewController のクッキーは直接読めない。ASWebAuthenticationSession や、ユーザーに手動でコピーさせる等の工夫が要る可能性)。ここは要 PoC。
- 既存 `SpotifyLoginView.swift` が「WKWebView でログイン → クッキー抽出」の実装例。ただし今回は WKWebView 内ログインが弾かれるため、そのままは使えない。

**ログイン不要で済むか?**: YT Music web は未ログインだと機能が大幅に制限される(自分のライブラリ・プレイリスト不可、再生も制限的)。実用にはログインがほぼ必須。

### リスク B: バックグラウンド音声

WKWebView の音声をアプリのバックグラウンド/画面ロック中も継続させる必要がある。

- **対策の目処あり**: `UIBackgroundModes: audio`(既に Info.plist にある)+ `.playback` の AVAudioSession(`PiPLyricsController.configureAudioSession` で既に設定)で、WKWebView の音声もバックグラウンド継続できるとされる。
- ただし WKWebView のバックグラウンド音声は歴史的に不安定な面があり **要実機検証**。土台(background mode + audio session)は Spotify 版で既に持っている。

### リスク C: PiP の共存

- YT Music web プレーヤーは動画要素で再生するため、iOS が **Web 側のネイティブ PiP(動画の PiP)** を出そうとする可能性がある。我々が出したいのは **カスタムの歌詞 PiP**。
- Web 側の PiP を抑制する必要がある(`playsinline` 属性の強制、`video` 要素の `disablePictureInPicture` 設定を JS で注入する等)。
- 我々の歌詞 PiP(`PiPLyricsController`)自体は流用可能。オーディオセッションの取り合いに注意。

### リスク D: 規約・広告

- YT Music を WKWebView に埋め込むこと自体の ToS リスク(Spotify の `sp_dc` 同様、非公式利用の範疇)。
- YT Music Free は広告が入る。埋め込みプレーヤーでの広告挙動は要確認(Spotify 版でも広告は「曲」として検知され無害だった前例あり)。

## 4. 歌詞ソース

- **lrclib**: 既存の `LyricsService.swift` をそのまま流用可能(曲名・アーティストで検索)。
- **YT Music 自身の歌詞**: ytmusicapi の `get_lyrics(browseId)` 相当で、videoId から歌詞取得が可能。ただし **多くが time-synced ではない(プレーンテキスト)** ので、同期表示には向かない場合が多い。Spotify の color-lyrics ほど当てにはできない。
- 実質は lrclib が主軸になる想定。Spotify 版の「Spotify歌詞優先 → lrclib フォールバック」に対し、YT Music 版は「lrclib 主」+ 可能なら YT Music 歌詞、という構成が現実的。

## 5. 流用できる既存資産

| 既存ファイル | 流用可否 |
|---|---|
| `LyricsSyncEngine.swift` | ○ ほぼそのまま(`YouTubeMusicWatcher` の `@Published` を購読する形にする) |
| `PiPLyricsController.swift` / `PiPDisplayLayerView.swift` / `LyricsFrameRenderer.swift` | ○ そのまま流用(自動 PiP 開始/終了、横長フレーム等すべて) |
| `LyricsService.swift`(lrclib) | ○ そのまま |
| `LyricsPiPCore`(`LyricLine`/`LRCParser`/`ActiveLineFinder`/`PlaybackPositionInterpolator`) | ○ そのまま |
| `SpotifyLoginView.swift`(WKWebView ログイン+クッキー抽出) | △ 構造は参考になるが、Google はログインをブロックするため手法変更が必要 |
| `SpotifyWebSessionClient` / `SpotifyLyricsService` / `SpotifyCluster` / `SpotifyID` / `SpotifyTOTP` 等 | × Spotify 固有。不要 |
| `DebugLog` + `tools/log-server.mjs`(リモートログ) | ○ 開発時のデバッグに必須級。流用 |
| CI(`ios-build.yml`)/ SideStore 配布フロー | ○ そのまま |

## 6. 推奨する de-risk の順序(PoC 優先度)

実装前に、最も不確実な部分から小さく検証すること(Spotify 版で有効だった進め方):

1. **【最優先】Google ログインのクッキー移植**: SFSafari/外部ブラウザでログイン → Google 認証クッキーを取得 → WKWebView に注入して `music.youtube.com` がログイン済みで開けるか。ここが無理なら全体が成立しない。
   - 可能なら PC の Node で「Google 認証クッキーを使って YT Music web の内部エンドポイントを叩けるか」を先に確認すると速い(Spotify で `tools/spotify-auth-repro.mjs` を使ったのと同じ手法)。
2. **JS での再生状態読み取り**: ログイン済み WKWebView で `video.currentTime` / `mediaSession.metadata` が正しく取れるか。
3. **バックグラウンド音声**: 埋め込み再生が画面ロック・アプリ切り替え後も継続するか。
4. **Web 側 PiP の抑制 + カスタム歌詞 PiP の共存**。
5. 歌詞取得(lrclib)を既存流用で接続。

各段階を実機(SideStore 配布)+リモートログで確認する、Spotify 版と同じループで進める。

## 7. 未解決/要調査の論点

- SFSafariViewController から Google 認証クッキーを我々のアプリ側へ渡す具体的手段(直接は読めない。ASWebAuthenticationSession の可否、あるいは別方式)。
- Google 認証クッキーの有効期限・失効時の再ログイン UX(Spotify の `sp_dc` 失効と同種の問題)。
- WKWebView バックグラウンド音声の実機での安定性。
- YT Music web の DOM/内部 API は予告なく変わり得る(Spotify の TOTP 変更と同種の脆さ)。
- 「アプリ内で再生する」UX をユーザーが許容するか(純正アプリの再生は検知不可という前提の再確認)。

---

**総括**: 技術的には実現可能。核心の曲検知はむしろ Spotify より素直に解ける。ただし Google ログインのクッキー移植が成立するかが分水嶺で、そこを最初に PoC で潰すべき。全体としては「受動観測アプリ」から「YT Music 内蔵クライアント」への性質変化を伴う新規開発規模の作業になる。
