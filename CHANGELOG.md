# CHANGELOG

このプロジェクトの開発セッションごとの作業内容をまとめる。技術的な詳細・恒久的な注意点は`README.md`側に反映し、ここにはセッションの経緯そのものを記録する。

## 2026-07-10 (プロジェクト開始〜現在)

### 1. 企画・実現可能性の検討

- 要望: Spotifyで再生中の曲に同期して歌詞をPIP(Picture in Picture)でフロート表示するiPhoneアプリ。App Store配布はせず個人利用に限定(非公式な手段の使用も許容)。
- 制約の洗い出し:
  - Spotify Premium未加入 → 2026年2月の規約変更で、公式App Remote SDK/Web API(Developer Dashboard経由)はオーナーがPremium契約中であることが必須になっており使用不可。
  - 追加の金銭コストは不可 → ShazamKit(有料Apple Developer Program必須)、AudD等のクラウド音声認識API(リクエスト課金)を却下。
  - マイクでの周囲音認識は不可 → イヤホン使用時はそもそも音を拾えないため却下(ShazamKit/AudDを却下した本質的な理由)。
  - Control Center表示の読み取りも実用性の面で却下。
  - Macを所持していない → ビルドはGitHub ActionsのmacOSランナーで行い、実機インストールはWindows上のツールでサイドロードする方針に決定。
- 最終的に採用した技術構成:
  - 曲検知: Spotifyの内部Webセッション認証(`sp_dc`クッキー)を使い、公式Web APIと同じ`/me/player/currently-playing`を叩く非公式な方法。
  - 歌詞取得: [lrclib.net](https://lrclib.net)の無料公開API(認証不要・同期歌詞対応)。
  - PIP表示: iOS 15+の`AVPictureInPictureController`カスタムContentSource(非動画コンテンツ向け)。
  - プロジェクト管理: XcodeGen(`project.yml`から`.xcodeproj`を都度生成、リポジトリにはコミットしない)。
  - ビルド: GitHub Actions `macos-14`ランナー。パブリックリポジトリとして運用しmacOSランナーの無料枠を無制限にする。
  - 実機インストール: 当初はAltServer(後にSideloadlyへ移行、後述)。

### 2. リポジトリ初期構築とCIの立ち上げ

- 新規パブリックリポジトリ(`ALK-ne/LyricsPiP`)としてプッシュ。
- XcodeGenの`project.yml`、SwiftUIのアプリ骨格(ログイン画面・再生中トラック表示・歌詞プレビュー・PIPコントローラ)を一括で初期実装。
- CIの初期不具合を順番に修正:
  - デフォルトブランチが`master`だったためワークフローのトリガー設定を修正。
  - 誤って`working-directory: LyricsPiP`を指定していたが、リポジトリ直下がアプリのルートだったため削除。
  - XcodeGen生成物と噛み合うXcodeバージョンをランナー上で明示的に選択するよう修正。
  - アプリアイコンが無いとサイドロードの署名パイプラインが壊れることが判明し、プレースホルダーアイコンを追加。

### 3. Spotify認証フローの実装とトラブルシューティング

- `sp_dc`クッキーをWKWebViewでのログイン後に取得しKeychainに保存、そこからBearerトークンを取得する`SpotifyWebSessionClient`を実装。
- トークン取得エンドポイントから403が返る問題 → ブラウザに近いHTTPヘッダー(User-Agent, Referer等)を付与して解消。
- 続けて、Spotifyがトークン取得エンドポイントにTOTP(Time-based One-Time Password)検証を追加していることが判明。秘密鍵はハードコードせず、コミュニティが継続的に追跡しているミラー(`xyloflake/spot-secrets-go`)から実行時に取得する方式(`SpotifyTOTP.swift`)で対応。
- 一時的なネットワークエラーやレート制限で毎回ログイン状態が失われてしまうバグ(「ログインしてもすぐログイン画面に戻る」症状の原因)を修正: Spotifyが明示的に`isAnonymous: true`を返した場合のみログアウト扱いにするよう変更。
- `/me/player/currently-playing`への429エラー対応:
  - 最初は`Retry-After`ヘッダーに従ってバックオフする実装、アプリ再起動時にもブロック状態を引き継ぐ`UserDefaults`永続化を実装。
  - 一度`Retry-After: 86400`(24時間ブロック)が返り誤診断しかけたが、後にNode.jsでのローカル再現スクリプト(`tools/spotify-auth-repro.mjs`)で検証した結果、実際にはこのトークン種別に対する**常時約30〜35秒に1回という恒常的なレート制限**であることが判明(24時間ブロックは別の一時的事象で数十分〜1時間程度で自然解消)。ポーリング間隔を最終的に40秒に調整し、レート制限中はアプリ内にオレンジの警告バナーを表示するようにした。

### 4. サイドロード環境: AltServer → Sideloadly

- 当初はAltServerでのサイドロードを想定していたが、運用中に繰り返しエラーが発生。
- Sideloadlyへの切り替えを実施。以後も「Local Anisette」関連の致命的エラー(`iTunesCore.dll`欠落/破損)やログイン時404エラーが発生したが、**AltServerに戻すのではなくSideloadly自体を直す方針**を明確に決定(完全アンインストール→再インストール、`%LOCALAPPDATA%\Sideloadly`のキャッシュ削除で解消)。この方針は今後同様のエラーが出ても踏襲する取り決めとして確定。

### 5. Macなし開発ループの改善(GitHub Issue #1)

Mac/シミュレータが無いため「push→CI→ダウンロード→サイドロード→実機確認」という遅いループしか無い課題に対し、Issue #1「Macなし開発のデバッグループ改善策まとめ」を作成し、6項目のうち以下を実装(3のSideStore、6のSentryは対象外):

1. **認証フローのローカル再現**: `tools/spotify-auth-repro.mjs`(Node.js)で、sp_dc→TOTP→トークン取得→currently-playingの一連の流れをiPhone無しで数秒単位で試行錯誤できるようにした。レート制限の実態解明にも活用。
2. **実機のリアルタイムログ取得**:
   - 2a: アプリ内のオンスクリーンデバッグログに加え、同一WiFi上のPCへログをPOSTする`tools/log-server.mjs`を追加。PIPでバックグラウンドに回った後も確認できる。
   - 2b: `libimobiledevice`のWindowsビルド(`idevicesyslog.exe`等)をセットアップし、USB接続でのリアルタイムシステムログ取得を確認。
4. **コアロジックの切り出し**: `LRCParser`・`ActiveLineFinder`・`LyricLine`/`CurrentTrack`をUIKit非依存の`LyricsPiPCore`SwiftPMパッケージに分離し、`swift test`で実機・シミュレータ不要のユニットテスト(13件)をCIで実行するようにした。
5. **CIシミュレータスモークテスト**: 独立したワークフロー`simulator-smoke-test.yml`を追加し、起動直後のクラッシュや画面崩れをCI上で検知できるようにした(ログイン状態依存の変更のみで走るようパス指定)。

### 6. PIP表示の実装・デバッグ

- 実際のSpotify連携が曲検知のレート制限で頻繁に止まってしまうため、Spotify通信を経由せずにPIP自体の動作確認ができるよう、ダミー歌詞を読み込むデバッグボタンを追加(`LyricsSyncEngine.loadDebugLyrics()`)。
- ここから、PIPが「起動はするが画面が真っ黒」という不具合の原因を段階的に特定・修正:
  1. `AVSampleBufferDisplayLayer`が実際のSwiftUIビュー階層に存在しないと`isPictureInPicturePossible`が真にならない → プレビュー用ビュー(`PiPDisplayLayerView.swift`)を新設し、実際に描画される場所にレイヤーを配置。
  2. 診断のため背景色を一時的に黒→明るい緑に変更し、「何らかの色が画面に届いているか」を切り分け(結果: 届いていなかった)。
  3. 静止画コンテンツには`kCMSampleAttachmentKey_DisplayImmediately`が無いとフレームが永久に描画待ちのまま → サンプルバッファ生成時に付与。
  4. `CVPixelBufferCreate`に`kCVPixelBufferIOSurfacePropertiesKey`が無いと、PIPのようなプロセス外合成が必要な用途ではエラー無しに何も表示されない → 生成時のattributesに追加、背景色も黒に戻す。
- 実機での確認により、PIPウィンドウ内にダミー歌詞のテキストが実際に表示されることを確認(黒画面バグの解消)。
- 続けて、文字数の多い歌詞行が矩形からはみ出て末尾が欠けて表示される不具合が発覚 → `LyricsFrameRenderer`にフォントサイズ自動縮小ロジックを追加し、実機で解消を確認。

### 7. ビルド番号(バージョン表示)の実装とバグ調査

- どのCIビルドが実機に入っているか判別できるよう、`CFBundleVersion`をGitHub Actionsの実行番号に連動させてアプリ内(ログイン後の画面のみ)に表示する機能を追加。
- 当初`CURRENT_PROJECT_VERSION`をxcodebuildへのコマンドライン引数で渡す方式にしたが、コンパイル後のInfo.plistの`CFBundleVersion`が常に`1`のまま変わらない不具合が発覚。
- `project.yml`への事前埋め込み、生成後の`.pbxproj`の直接確認、`xcodebuild -showBuildSettings`、ビルド直後にCIランナー上で直接Info.plistを読む、と段階的に検証したが、すべての段階で正しい値(実行番号)が確認できるにもかかわらず、最終成果物だけ常に`1`になるという再現性のある不可解な挙動を確認。根本原因の特定は断念。
- 回避策として、ビルド後に`PlistBuddy`で`CFBundleVersion`を直接上書きする方式に変更し、確実に反映されることを確認(build 34で`v1.0 (build 34)`表示を確認)。調査用の診断ステップは最終的に削除して整理。
- 整理中に誤って`Install XcodeGen`ステップを削除してしまいビルド失敗 → 即座に復元して解消。

### 8. lrclib.net連携の単体検証

- `curl`で実際のAPIレスポンスを取得し、`LyricsService.swift`が期待するJSON構造(`syncedLyrics`/`plainLyrics`)と一致することを確認。
- `LRCParser`の正規表現が実際のレスポンス形式(空行・複数行・日本語含む)を問題なくパースできることを確認。
- 洋楽(Queen "Bohemian Rhapsody")・邦楽(YOASOBI「夜に駆ける」)の両方でテスト。該当曲が無い場合の404 → `nil`フォールバックも確認。

### 9. READMEの更新

- サイドロードツールがAltServerからSideloadlyに移行済みであることを反映(セットアップ手順・既知の落とし穴・継続運用の説明を全面更新)。
- TOTP要件、実際のレート制限挙動、PIP修正内容、`CFBundleVersion`の謎の挙動、lrclib.net検証結果を「既知のリスク・制約」および新規セクションとして追記。

### 10. レート制限が別アカウントでも解除されないことの確認

- 実際のSpotify連携の確認を進める前に、レート制限(24時間待ちが必要か)を回避できないか検証。「別アカウントなら制限を回避できるのでは」という仮説を、別アカウントの`sp_dc`クッキーを使い`tools/spotify-auth-repro.mjs`で同じPCから即座にテスト。
- 結果: トークン取得(200)は成功したものの、`currently-playing`は別アカウントでも同様に429(`Retry-After: 36`)が返った。
- これにより、このレート制限は**Spotifyアカウント単位ではなく、IPアドレス/ネットワーク単位、またはTOTPベースのクライアント種別単位でかかっている**ことが判明。別アカウントに切り替えても待ち時間の解消にはならない。

### 11. PIPのバックグラウンド維持を実機で確認

- ダミー歌詞を表示した状態でPIPを開始し、Spotifyアプリやホーム画面に切り替えた後もPIPウィンドウが表示され続けることを実機で確認。当初「実機検証が必要」としていた最大の技術的不確実性の一つが解消。
- `silence.m4a`の無音ループ再生によるオーディオセッション維持のアプローチが機能していることを裏付ける結果。

### 12. 24時間ブロックの発生時刻の特定と、再インストールによる再発リスクの発見

- ユーザーが保存していた過去のデバッグログから、最初に86400秒(24時間)ブロックを受けた正確な瞬間が**10:25:19.241**(それまでは5〜55秒程度の短い429が繰り返されていた)であることを特定。
- 一方、`tools/log-server.mjs`が受信したログ(`/tmp/log-server-output.txt`)を精査すると、12:42時点以降の「あと○○秒」というカウントダウンはすべて**12:19:18頃**を起点として一貫しており、10:25の発生時刻とは一致しない。つまり10:25〜12:19の間に**もう一度**86400秒ブロックが再発生していたことが判明。
- コミット履歴で確認したところ、レート制限を`UserDefaults`へ永続化する機能(`Persist Spotify rate-limit backoff across app relaunches`)が実装されたのは**10:48:34**、つまり最初の10:25:19のブロックより**後**だった。10:25時点のビルドにはまだ永続化機能が無く、そのブロック情報はメモリ上にしか無かったため、次にアプリが再起動(≒永続化機能を含む新しいビルドに置き換わった)時点で当然消えていた。その後の起動時に自動で本物のポーリングが再開し、まだサーバー側の制限が生きていたため、今度は永続化機能ありの状態で再度86400秒ペナルティを受け、12:19頃から正しく保存されるようになった。
- 12:19以降は6時間以上リセットなく一貫してカウントダウンが進んでいる。この間もPIP修正やビルド番号修正で何度もSideloadlyでの再インストール(同一Bundle IDへの上書き、通常のiOSの挙動としてはアプリの「更新」に近い)を行っているが、`UserDefaults`の内容は消えておらず、安全装置は正しく機能し続けている。
- **教訓**: 「再インストールで安全装置が消える」わけではなく、単に**安全装置を実装する前のビルドでは保存しようがなかった**というだけだった。永続化機能を含むビルドが実機に入って以降は、再インストールを挟んでも正しく保護され続けている。

### 13. リポジトリが誤ってプライベートのままだったことによるGitHub課金の発覚

- GitHubの請求画面を確認したところ、`$8.74`分の従量課金(Current metered usage)が発生していることが発覚。
- 当初の計画では「GitHub ActionsのmacOSランナーを無料・無制限で使うため、リポジトリはパブリックで運用する」としていた(README・CHANGELOG項目2参照)が、`gh repo view`で確認したところ実際には**プライベートのまま**になっていたことが判明。
- プライベートリポジトリのGitHub Free枠は月2,000分のみで、macOSランナーは**10倍**の消費レートのため、今日一日で20回以上行ったビルドがあっという間に無料枠を超え、従量課金が発生していたと考えられる。
- リポジトリを`gh repo edit --visibility public`でパブリックに切り替え、今後のビルド分は無料・無制限になるよう修正。ただし既に発生した`$8.74`は遡って無料になるわけではない。
- 一回限りの好意的な免除(courtesy refund)をGitHubサポートに依頼するチケットを提出。「最初からパブリックで運用する予定だったが、開発初期に誤ってプライベートのままにしてしまった」という経緯を説明。返答待ち。

### このセッション中に確立した作業ルール

- PowerShell/Bash/Monitorツールの使用に毎回許可申請させず、一連の操作後に要約を提示する。
- Sideloadlyでエラーが出てもAltStore/AltServerへの切り替えを提案せず、Sideloadly自体を直す。
- 応答は敬語で統一する。
- 作業がひと段落するたびに(セッション終わりにまとめて、ではなく)、この`CHANGELOG.md`に番号付きセクションを追記していく。

## 2026-07-11 (リファクタリング)

### 14. サービス層リファクタリング(ロガー注入・Core移設・HTTPクライアント分離)

本体リポジトリ(`D:\ClaudeTable\LyricsPiP`)には手を付けず、コピーした`D:\ClaudeTable\LyricsPiP-refactor`で実施。E2E通し確認が未完のため、実機で動作確認済みのPIP周り(`LyricsFrameRenderer`・PIP開始/フレーム描画ロジック)は構造を変えず、機械的なロガー置換のみに留めた。

- **ロガー注入**: `LyricsPiPLogging`プロトコル(`@MainActor`)をCoreに新設し、`DebugLog`を準拠させた。各サービス(`SpotifyWebSessionClient`・`PlaybackPoller`・`LyricsSyncEngine`・`PiPLyricsController`)は`DebugLog.shared`直接参照をやめ、initで注入(デフォルトは従来どおり`DebugLog.shared`のためアプリの組み立てコードは無変更)。`DebugLog`からリモートPOST機能を`RemoteLogSender`に分離。UI層(`DebugLogView`・`SpotifyLoginView`)のシングルトン利用は意図的に残置。
- **純粋ロジックのCore移設**(すべて`swift test`対象になった):
  - `SpotifyTOTPLogic`: TOTP導出(XOR変換・HMAC-SHA1・最新シークレット選択)をCoreへ。テスト期待値は`tools/spotify-auth-repro.mjs`と同一ロジックのNodeスクリプトで生成し、RFC 6238公式ベクタでも相互検証。アプリ側はネットワーク取得のみの`SpotifyTOTPProvider`に縮小。
  - APIレスポンスモデル: `SpotifyAccessToken`・`SpotifyCurrentlyPlaying`・`LrclibTrack`を各ファイルのprivate structからCoreの公開型へ移動し、デコードのテストを追加。
  - `PlaybackPositionInterpolator`: `PlaybackPoller`内の再生位置補間(basePositionMs+経過時間)を切り出してテスト追加。
- **HTTPクライアント分離**: `HTTPClient`プロトコルをCoreに新設し、本番実装`URLSessionHTTPClient`をアプリ側に追加。全サービスの`URLSession.shared`直叩きを注入されたクライアント経由に変更し、重複していた`HTTPURLResponse`チェックを一元化。2箇所に重複していたブラウザ偽装User-Agentも`SpotifyWebConstants`に一元化。
- **エラー型の分割**: `SpotifySessionError.cookieRejected`が「クッキー無効」と「一時エラー」を兼ねていたのを、`cookieInvalidated`(唯一ログアウトする)・`serverError(statusCode:)`・`malformedResponse`に分割。挙動は従来と同一(`isAnonymous: true`のときのみログアウト)。
- Coreのユニットテストは13件→29件に増加。Windows環境ではコンパイル検証ができないため、CIの`unit-tests`ジョブ(および`ios-build`ワークフロー)での検証が必要。
- 検証結果: CI一発グリーン(unit-tests 29件パス・ビルド成功、run 29105036096 / build 46)。実機スモークテストも全項目パス — ①build 46表示 ②Spotify再ログイン成功(=リファクタ後の認証フローが実機で動作) ③レート制限バナー表示(=ポーリング→429検知→永続化→バナーの一連が動作) ④ダミー歌詞でのPIP表示・バックグラウンド維持正常。リグレッションなしと判断し`main`へマージ。
- 補足: 実機インストールはSideloadlyのApple IDログインが404で失敗し続けたため(Apple側変更にv0.60.0が未追従の可能性、詳細はメモリ参照)、ユーザー判断でAltStoreに切り替えてインストールした。署名元が変わったためKeychain(sp_dc)は引き継がれず再ログインが必要だった(正常な挙動)。

### 15. SideStore移行(Issue #1 項目3) — 初回以降PC不要のインストール/リフレッシュを確立

AltStoreでのインストールが成功した(=このPC/ネットワーク/Apple IDでAltStore系が動くと確認できた)ことを受け、派生のSideStoreへ移行。

- **セットアップ**: PC側は[iloader](https://github.com/nab138/iloader) v2.2.6(MSI)を使用。以前の煩雑な手順(AltServer経由インストール+jitterbugpairで手動ペアリングファイル生成+WireGuard)は不要になっており、iloaderがダウンロード・署名インストール・ペアリングファイル配置まで自動で実施。iPhone側はLocalDevVPN(App Store)+デベロッパモードON+SideStoreサインインで完了。
  - 途中「Maximum certificates reached」の確認が出た(無料Apple IDの証明書上限)。Continueで既存証明書を失効させて続行 — AltStore経由で入れた既存アプリは起動不能になるが、SideStoreで入れ直すため実害なし。
  - MSIX仮想化の罠を避けるため、iloaderのインストール・起動はユーザー自身がエクスプローラー/スタートメニューから実施。
- **CIワークフロー改良**: GitHub Actionsのartifactはダウンロードにログインが必要でiPhone単体の運用に不向きなため、`ios-build.yml`にローリングリリース(タグ`latest`のプレリリース)への`.ipa`添付を追加。iPhoneのSafariから`releases/download/latest/LyricsPiP-unsigned.ipa`の固定URLで直接ダウンロードできる。
  - 落とし穴: `/releases/latest/download/`というエイリアスURLは「プレリリース以外の最新」を指すため404になる。タグ直指定の`/releases/download/latest/`を使う必要がある。
- **実機での確認**: Safari共有メニュー→SideStoreの経路は「The file doesn't exist」エラーになったが、SideStoreの「My Apps」→「+」→ファイルブラウザ経由なら成功。LyricsPiPのインストールと、SideStore単体でのリフレッシュ(PC不要)の両方を確認。
- これでIssue #1の項目3も完了。開発ループは「push → CI → iPhoneのSafariでダウンロード → SideStoreでインストール」となり、PCでのダウンロード・転送工程が消えた。7日ごとのリフレッシュもiPhone単体で回せる。

### 16. 曲検知をREST ポーリングから dealer WebSocket / connect-state へ全面刷新(最重要)

24時間ブロック解除後に本番パイプラインを試したが、`currently-playing`が依然として429。ローカル(`spotify-auth-repro.mjs`)で徹底検証した結果、根本原因が判明した。

- **診断**: `sp_dc`由来のweb-playerトークン(clientId `d8a5ed95...`)は、2025年12月のSpotify変更で`api.spotify.com`の**全エンドポイントが実質ブロック**されていた。検証で`profile`・`search`・`devices`まで全部429、`/me/player`に至っては1回叩くだけで24時間ブロックが再発動することを確認(切り分け中に実際に再発させてしまった)。`Retry-After`が28→59→1→58と無意味に乱高下するのも、通常のレート制限ではなくこのトークン種別を締め出すための挙動と考えると符合する。別アカウント・別IP(モバイル回線)でも429で、このプロジェクトを通じて**一度も200が返ったことがなかった**ことから、この経路は完全に死んでいると結論。
- **突破口**: Spotify Web Player本体(open.spotify.com)は今も動く。その内部機構である**dealer WebSocket + connect-state**(`wss://dealer.spotify.com` + `spclient.spotify.com`)は同じ`sp_dc`認証で生きており、`api.spotify.com`とは別ホスト。Nodeスパイクで実証し、歌詞同期に必要な情報(曲名・アーティスト・アルバム・長さ・再生位置・基準タイムスタンプ・一時停止状態)が**すべて取得できる**ことを実データで確認(Mrs. GREEN APPLE「藍(あお)」で検証)。
- **実装**: 
  - `PlaybackWatcher`(新規、`PlaybackPoller`を置換): dealer WebSocketに接続 → `Spotify-Connection-Id`取得 → connect-stateへPUTして購読 → 返ってきたclusterをパース。pushメッセージは「変化があった」トリガーとして使い(gzip圧縮されうるpushペイロードを解析せず)clean stateを再取得、pause/seek/取りこぼしは25秒のセーフティ更新で拾う。**push型なので曲変更は即座に反映**され、レート制限の対象にもならない。`@Published`インターフェース(`currentTrack`/`isPlaying`/`estimatedPositionMs`)は据え置きで、`LyricsSyncEngine`・PIP・UIはリネーム以外変更なし。
  - `LyricsPiPCore`: `SpotifyClusterParser`+`PlaybackSnapshot`(純粋・実キャプチャしたclusterでテスト)。死んだ`SpotifyCurrentlyPlaying`モデルとテストを削除、`SpotifyAccessToken`は継続使用。
  - レート制限警告バナー・`blockedUntil`永続化を撤去(不要になった)。
- **メリット**: Premium不要・追加コストなし・マイク不要という当初条件を全て満たしたまま問題を根本解決。しかも旧方式(40秒間隔ポーリング、最大40秒の曲切替遅延)より即応性が高い。
- 検証: CI一発グリーン(Coreテスト30件パス=新規SpotifyClusterTests 4件含む、iOSビルド成功)。実機E2Eは次のタスク。

### 17. 本番パイプラインの実機E2E成功 — プロジェクトの中核目標を達成 🎉

build 53を実機にインストールし、`tools/log-server.mjs`でリアルタイムログを確認しながら通し確認。**全パイプラインがエンドツーエンドで動作した。**

- ログで確認できた一連の流れ:
  ```
  [Session] トークン取得成功 (/api/token HTTP 200)
  [Watch] dealer WebSocket接続 → connection_id取得、購読します
  [Watch] 曲検知: 藍(あお) / Mrs. GREEN APPLE
  [Lyrics] 取得開始 → 取得成功: 27行
  [PiP] フレーム表示: "もうひと寝入りしたって 何も変わらないさ"
  ```
- **曲の切り替えを即座に検知**: 藍(あお) → ですとらくしょん!!/Chevon への切り替えを一瞬で検知し、新しい歌詞(53行)を取得。push型WebSocketの即応性を実機で実証(旧方式は最大40秒遅延)。
- **画面・PIP両方で確認**(ユーザー目視): 曲名・歌詞が表示され、再生に合わせてハイライト行が同期して動く。一時停止すると止まり、次の曲を流すと切り替わる。
- これにより、プロジェクト当初からの最大目標「Spotifyで再生中の曲に同期して歌詞をPIP表示する」が実機で完全動作。最大の技術的不確実性(非動画PIPのバックグラウンド維持、sp_dc方式の曲検知)はいずれも解消。
- 軽微な観察: cluster部分更新で一瞬`artist_name`が空になることがあるが、`LyricsSyncEngine`が曲IDで重複判定するため歌詞の再取得は走らず実害なし。

### 現状・残タスク

- Issue #1の対応項目(1・2a・2b・3・4・5)は実装済み、README/CHANGELOGにも反映済み。
- **中核機能(Spotify曲検知→歌詞取得→PIP同期表示)は実機でエンドツーエンド動作確認済み**。
- リポジトリはパブリックに切り替え済み。GitHub課金($8.74)の免除依頼は返答待ち。
- 今後の候補(必須ではない): デバッグ用ダミー歌詞ボタン(`loadDebugLyrics`)の撤去、cluster部分更新時のartist空欄の吸収、長時間運用でのWebSocket再接続の安定性確認。
