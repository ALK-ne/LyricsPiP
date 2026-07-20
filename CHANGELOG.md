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

### 18. 実運用で見つかった不具合の連続修正(プレイリスト・広告・PiP再起動)

E2E成功後、実際に使い込む中で顕在化した不具合を順に修正。

- **artist_nameがプレイリスト再生で欠落する問題**: アルバム再生ではclusterに`artist_name`が入るが、プレイリスト再生では**フィールド自体が省略され`artist_uri`しか来ない**ことが判明(当初「充填の遅延」と誤診断)。lrclibの`/api/get`は空artistで400(アプリの-1011の正体)。→ track URIをhex GIDに変換し、Spotify内部の`metadata/4/track/<gid>`(レート制限なし)で正確なアーティスト名を解決するようにした(`SpotifyID.gidHex`をCoreに追加、実値でテスト)。実機で`アーティスト解決: Coffee / Mrs. GREEN APPLE`→歌詞取得成功を確認。
- **PiPが`-1003`で起動できない問題**: 「Spotify再生中だと競合」と最初に誤診断したが、ログ精査で真因判明。`AVSampleBufferDisplayLayer`は**中身が空だとPiP起動不可**(PGPegasusErrorDomain -1003)。`updateFrame`のガードが、初回にアクティブ歌詞行が無い(currentText nil)ケースでプレースホルダーフレームすら抑制していた。build 53は曲が歌詞途中まで再生済み=アクティブ行ありで露見しなかっただけの潜在バグ。→ 初回フレームは必ずenqueueするラッチ(`hasEnqueuedFrame`)を追加し、`start()`で現在の歌詞状態を強制描画してからPiP起動するようにした。実機で曲頭でも`開始成功`を確認。
- **オーディオセッションが`.mixWithOthers`に**: Spotifyを中断しないよう(かつ再生中も我々のセッションを有効化できるよう)`.playback`に`.mixWithOthers`を付与、有効化の成否もログ化。実機で`オーディオセッション有効化 (mixWithOthers)`を確認、Spotifyの再生は止まらない。
- **広告への耐性を実機確認**: Spotify Freeの広告(キリンビール等、Spotifyの「広告ナシで〜」プロモ)を「曲」として検知するが無害(PiPは空表示)。広告終了後に自動で曲検知→歌詞取得が再開することを確認。
- 副次的な整理として、デバッグ用ダミー歌詞ボタン撤去・部分更新時のartist空欄吸収(`TrackMetadataMerge`)・空artist時の歌詞取得保留も実施済み。

### 19. 歌詞ソースにSpotify自身の同期歌詞を追加(カバレッジ大幅改善)

lrclibだけでは同期歌詞が見つからない曲が想定より多かったため、歌詞ソースを多段化。

- **Spotifyの内部歌詞エンドポイント`color-lyrics/v2/track/<id>`を第一候補に採用**。Spotifyアプリ内で表示されるものと同じ同期歌詞(Musixmatch/syncpower製、`LINE_SYNCED`で行ごとのタイムスタンプ付き)。Nodeで実証後に実装。
- **track IDだけで引ける**のが決定的な利点: アーティスト名・アルバム名・時間マッチが不要になり、プレイリストのartist欠落問題も、lrclibの表記揺れによる取りこぼしも回避。カバレッジもユーザーの実際のSpotifyライブラリと一致する。
- 取得順: ①Spotify color-lyrics(track id) → ②lrclib(artist/track/album/duration) → ③どちらも無ければ歌詞なし。`LyricsSyncEngine`は成功した曲IDを`loadedTrackId`で記録し、アーティスト解決後の再試行で重複取得しないようにした。
- Coreに`SpotifyColorLyrics`モデル+`syncedLines`パーサ(LINE_SYNCEDのみ採用)を追加してテスト。アプリ側は`SpotifyLyricsService`(spclientホスト+web-playerトークンで取得)。
- 実機で確認: 以前lrclibで「歌詞なし」だった`FLASH BACK!!!!!!!!`が`Spotify歌詞: 66行`、`あなたはかいぶつ`が44行取得できるようになった。

### 20. PiPウィンドウの形をワイドに変更、アプリ内ミニプレビューを撤去

ユーザーから「歌詞の上下に黒い余白が大きい」との指摘を受け、PiPの見た目を調整。

- **描画フレームの縦横比を変更**: 16:9(640×360)→3:1(720×240)→最終的に3.6:1(720×200)。PiPウィンドウは描画フレームの比率にそのまま従うため、フレームを横長・低くすることで2行歌詞に対する上下の余白が大幅に削減された。テキスト矩形の上下・行間の余白も詰め(34/66px→8/12/10px)、フォントサイズも拡大。ユーザー確認で「丁度いい」の評価。
- **アプリ内ミニプレビューを撤去**: 黒背景の枠+「PIPプレビュー」ラベルを削除。ただし表示レイヤー(`PiPHostView`)はPiP起動可否判定(`isPictureInPicturePossible`)に描画ツリー上の存在が必須なため、極小(48×16pt)・ほぼ透明(opacity 0.02)にして「PIPで表示」ボタンの背後に隠す形で存続させている。レイアウトは圧迫せず、PiP自体の起動・サイズには影響なし。

### 21. WebSocket頻繁切断の原因調査と修正

「約60秒ごとに`Software caused connection abort`で切れる」件を調査。

- Node.jsで同じプロトコル(購読+30秒ごとのapp-level ping)を再現したところ140秒間切断なしだった一方、実機ログでは20〜92秒とばらついた間隔で頻繁に切断していたことから、**プロトコル自体ではなくiOS/URLSession固有の問題**と判断。
- 調査の結果、`URLSession.shared`のデフォルト`timeoutIntervalForRequest`が60秒であり、`URLSessionWebSocketTask`はこのタイムアウトがWebSocketフレーム受信で正しくリセットされない既知の不具合がAppleデベロッパフォーラム等で広く報告されていることが判明。観測された切断間隔(60〜90秒台中心)とも符合。
- **対策**: `timeoutIntervalForRequest`を300秒に設定した専用の`URLSessionConfiguration`を`PlaybackWatcher`に追加し、`URLSession.shared`の代わりに使用(1行の差し替え)。根本的なリセット不具合そのものは直せない可能性がある前提で、まず間隔を延ばす対症療法として実施。
- **実機で確認**: 修正後、フォアグラウンドでの利用中は**約8分半、接続エラーが一度も発生しなかった**(修正前は20〜92秒間隔で頻発)。大幅に改善したと判断。
- 別枠の挙動として、**PiP未起動の状態でアプリをバックグラウンドに回すと切断される**現象が別途確認されたが、これはiOSの通常のバックグラウンド実行制限によるもので、今回の対策の対象外(想定内の挙動)。

### 22. PiPのバックグラウンド自動開始・フォアグラウンド自動終了、手動ボタン撤去

ユーザーから「PIPで表示/閉じるボタンを廃止し、バックグラウンド移行で自動的にPiPを出したい」との要望を受け、実現可能性の調査から実装まで対応。

- **自動開始**: `AVPictureInPictureController.canStartPictureInPictureAutomaticallyFromInline`を採用。歌詞が読み込まれた時点(ボタン操作を待たず)でオーディオセッション(`.mixWithOthers`)・PiPコントローラー・無音ループ再生を先んじて準備し、フラグを立てておくことで、実際にアプリが背後に回った瞬間にiOS側が自動でPiPを開始する。実機で動作確認済み。
- **自動終了の不具合と対処**: `canStartPictureInPictureAutomaticallyFromInline`は「フォアグラウンド復帰で自動終了」も仕様上セットのはずだが、実機ログで検証したところ**PiP自身の「戻る」ボタン経由でしか自動終了が発火しない**ことが判明(アプリを直接開いた場合は`stopPictureInPicture`自体が一度も呼ばれていなかった)。そのため`UIApplication.didBecomeActiveNotification`を自前で監視し、PiP表示中にアプリがアクティブになったら明示的に`stopPictureInPicture()`を呼ぶよう実装。これにより、PiP側のボタン経由でも直接アプリを開いた場合でも確実に閉じるようになった。
- 副次的に、`AVPictureInPictureControllerDelegate`の`restoreUserInterfaceForPictureInPictureStopWithCompletionHandler`(未実装だと終了処理が完了せずPiPが開いたままになる)も追加。
- **ログの圧迫を2箇所修正**: PiPフレーム更新ログ(数秒おきに出力)と、自動開始準備の`configureAudioSession`ログ(0.2秒間隔の再生位置更新のたびに再実行され緊急に無限出力していた)を、それぞれ削除・一度きりのガードに変更。
- **実機で全パターンの動作を確認**: バックグラウンド移行→自動起動、PiP側ボタンでの終了、アプリ直接再オープンでの終了、すべて問題なし。これを受けて手動の「PIPで表示」「PIPを閉じる」ボタンと関連コード(`start()`/`stop()`/`waitForPossibleThenStart()`/`isPiPPossible`)を完全に撤去し、UIはボタン無しの完全自動運用になった。

### 23. デバッグログパネルの非表示化

ユーザーから「デバッグログ機能をアプリ側から見えないようにしてほしい、リモートログは機能するように」との要望を受け対応。

- `DebugLog`本体(ログ記録・`RemoteLogSender`によるPOST送信)はUIから独立して動いており、リモートログサーバーのURLも`UserDefaults`に永続化済みのため、画面上の`DebugLogView`を`ContentView`から外すだけでリモート送信機能はそのまま維持される。
- `ContentView`から`DebugLogView()`の呼び出しを削除。ファイル自体(`DebugLogView.swift`)は今後の再デバッグ用に残置。
- 実機で、画面上にログが表示されないこと・ログサーバー側には引き続きログが届くことの両方を確認済み。

## 2026-07-12〜13

### 24. YouTube Music / Amazon Music対応の実現可能性調査(ドキュメント化のみ、実装なし)

将来の別セッションでの着手に備え、他の音楽サービス対応の可否を調査。

- **YouTube Music**: ネイティブアプリの再生をSpotify Connectのように外から観測する手段は存在しない(iOS 16+でMediaRemoteも封鎖済み)。一方、**WKWebViewでYouTube Music web版を埋め込み、その中で再生させる**方式なら、`video.currentTime`/`mediaSession.metadata`をJSで直接読めるため実現可能と判明。ただし**GoogleがWKWebView内でのログインを技術的にブロック**しており、これが最大の壁(回避策はSpotifyの`sp_dc`と同様、正規ブラウザでログイン→認証クッキーをWKWebViewに注入)。
- **Amazon Music**: 同じくネイティブ観測は不可能だが、埋め込み方式は同様に可能。**AmazonはWKWebView内ログインを技術的にブロックしておらず**(「非推奨」と案内するのみ)、YouTube Musicより着手しやすいと判断。
- 両サービスとも埋め込み方式共通の未知数として、**WKWebViewでのDRM(EME)音声再生の安定性**が挙げられる(iOSのWebKit自体はFairPlay対応だが、WKWebView埋め込みでの信頼性は歴史的に不安定)。
- 既存のPiP/歌詞同期スタック(`LyricsSyncEngine`・`PiPLyricsController`等)は、新規`XxxWatcher`が既存の`@Published currentTrack/isPlaying/estimatedPositionMs`インターフェースに合わせて実装されれば、そのまま流用可能という設計方針を確認。
- YouTube Music分の詳細な設計・調査結果は`docs/youtube-music-feasibility.md`に引き継ぎ資料としてまとめてREADMEからリンク。Amazon Music分はユーザーの希望によりドキュメント化せず、この場の会話のみに留める。
- 今回は調査のみで実装はしていない。着手する場合は上記ドキュメント、または本セクションを参照。

### 25. アプリアイコンの新規デザイン

これまでプレースホルダー(単色緑)だったアプリアイコンを、ユーザーの手書きスケッチをもとに新規デザイン。

- ユーザーがペイントで描いたラフ(「LYRICS」の文字+その下に黒い角丸ボックスで「PiP」、全体は緑、Spotify寄りの色調で)を解釈し、Pillow(この session でインストール)でベクター風に再描画。
- 「LYRICS」のフォントを4候補(Georgia BoldItalic / Times BoldItalic / Brush Script / Segoe Script Bold)で並べて提示し、ユーザーがGeorgia系を選択。ただしイタリック(斜体)は不要とのことで、直立のGeorgia Boldに変更。
- 背景色は当初Spotifyの旧ブランドカラー`#1DB954`を使用したが、実機で本物のSpotifyアイコンと並べた際に色味のズレをユーザーが指摘。Spotifyの現行ブランドカラー`#1ED760`(より明るい緑)に修正し、実機で問題なしを確認。
- `LyricsPiP/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`を差し替え。1024×1024・RGB(アルファ無し)。

## 2026-07-19

### 26. バージョン表記スキームの導入とアプリ内バージョン表示の簡略化

セマンティックバージョニング風のルールを導入し、バージョン運用を整理。

- 現時点の最新を **1.0** とし、`メジャー.マイナー.パッチ` 形式に統一。機能追加=マイナー(1.0→1.1)、バグ修正・細かい調整=パッチ(1.0→1.0.1)。バージョンを上げる操作は `LyricsPiP/App/Info.plist` の `CFBundleShortVersionString` の書き換え。
- リリースごとの変更要約を記録する **`RELEASE_NOTES.md`** を新設。開発の詳細な経緯は本CHANGELOG、バージョン別の要約はRELEASE_NOTES.mdという二分にした。
- アプリ内のバージョン表示を、これまでの `v{版} (build {CI番号})` から **マーケティング版のみ**(例 `v1.0`)に簡略化。`CFBundleVersion`(GitHub Actionsの実行番号)は表示しないよう `ContentView.versionString` を変更。

### 27. PiPに表示する歌詞の行数を設定可能に(v1.1)

これまで「現在行+次の1行」固定だったPiPの歌詞表示を、設定でカスタマイズできるようにした(以前ユーザーと検討していた案の実装)。

- **設定画面**を追加(`ContentView`右上の歯車アイコン → `LyricsSettingsView`をシート表示)。
- **次の行数**を 1〜5 行から選択可能に(Stepper、デフォルト1)。行数に応じて描画フレームの高さが伸び、PiPウィンドウ自体も縦に大きくなる。
- **「1行前も表示」トグル**を追加(デフォルトOFF)。オンにすると現在行が中央に配置され、前の歌詞も見えるようになる。
- 設定は `LyricsDisplaySettings`(`UserDefaults`バックのObservableObject、shared)に永続化。`PiPLyricsController`がこれを購読し、設定変更時に即再描画する。
- `LyricsFrameRenderer` を2行固定描画からN行可変・高さ連動に一般化(2行時は従来と同じ720×200を維持)。
- `CFBundleShortVersionString` を 1.0 → **1.1** に。デフォルト設定のままなら表示は1.0と同一。実機で動作確認済み。

### 28. 横画面での全画面歌詞表示(v1.2)

横画面での「PiPを画面いっぱいに」という案は、**PiPウィンドウの絶対サイズ・位置をアプリから指定するAPIがiOSに存在しない**ため断念(比率は変えられても大きさ・場所は触れない)。代わりに、アプリ自身がフォアグラウンドで横画面のときに全画面で歌詞を出す方式で実現した。

- `Info.plist` の `UISupportedInterfaceOrientations` に横向き(LandscapeLeft/Right)を追加(それまでは縦固定)。
- `verticalSizeClass == .compact` を横画面判定に使い、`ContentView` が「縦=通常UI / 横=`LandscapeLyricsView`」を切り替え。フォアグラウンドの向き判定なので①で問題になったバックグラウンド回転検知の不確実性は無い。
- `LandscapeLyricsView`(新規): 全画面・大きな文字で歌詞を表示。PiPと同じ表示設定(行数②・1行前③)を反映。曲/歌詞が無いときはプレースホルダーを全画面表示。
- 行の切り出しロジックを `LyricsLineWindow` / `DisplayLyricLine`(新規)に共通化し、PiPと横画面ビューで共用(`LyricsFrameRenderer.Line` を置換して重複を解消)。
- `PiPHostView` を向き切り替えをまたいで常設するよう `ContentView` を再構成(PiPはバックグラウンド機能なので横画面ビュー表示中も表示レイヤーを維持)。
- `CFBundleShortVersionString` を 1.1 → **1.2** に。
- 落とし穴: 最初 Info.plist にだけ横向きを追加したが、CIの `xcodegen generate` が
  `project.yml` の `info.properties`(Portraitのみ)で上書きし横画面が効かなかった。
  `project.yml` にも横向きを追加して解決(以後、向き等のInfo.plistキーはproject.yml側が真)。

### 29. タップで横画面に切り替えるボタン(v1.2.1)

物理回転に頼らず、ボタンで全画面歌詞(横画面)に入れるようにした。特にiOSの画面回転ロックON時は物理回転が効かないため、この経路が唯一の横画面手段になる。

- `OrientationManager`(新規、@MainActor shared): 向きの強制状態(none/landscape/portrait)を持ち、`UIWindowScene.requestGeometryUpdate(.iOS(interfaceOrientations:))` で回転を要求。回転ロックONでも貫通する。
- `AppDelegate`(新規、`@UIApplicationDelegateAdaptor`): `application(_:supportedInterfaceOrientationsFor:)` で `OrientationManager.supportedMask` を返し、強制中は該当向きにロック。
- 物理向き監視: `UIDevice.orientationDidChangeNotification` を購読し、強制中に端末を逆向きへ倒したらロックを解除して物理向きへ戻す(強制の確実な保持と「倒したら戻る」を両立)。
- UI: 縦画面メインに横向きボタン(`rectangle.landscape.rotate`)、横画面ビューに縦向きの戻るボタン(`rectangle.portrait.rotate`)。
- `CFBundleShortVersionString` を 1.2 → **1.2.1** に(既存機能の強化なのでパッチ。project.yml側)。

### 30. 横画面の全画面歌詞に曲情報ヘッダーを追加(v1.2.2)

`LandscapeLyricsView` の上部に、縦画面と同じく曲タイトル+アーティスト名を表示。`ContentView` から `trackName` / `trackArtist` を渡し、黒背景に合わせて白文字でスタイリング。曲があるときのみ表示し、左上の戻るボタンと被らないよう横パディングを確保。`CFBundleShortVersionString` を 1.2.1 → **1.2.2**(表示情報の追加、パッチ)。

### 31. アプリUIをiOS標準デザインに整える(v1.3.0)

ユーザー要望「AppleのUIを使って(アプリ全体・iOS標準で上品に)」に対応。

- メイン画面(`ContentView`)を `systemGroupedBackground` + `secondarySystemGroupedBackground` のカード構成に。曲情報ヘッダーと歌詞プレビューをそれぞれ角丸カード化。
- 横画面ボタンをツールバー `topBarLeading`(ログイン時のみ)、設定ボタンを `topBarTrailing` に整理。バージョンとログアウトをフッターへ(ログアウトは `role: .destructive`)。
- ログイン前画面をシンボル+タイトル+説明+prominentボタンの標準導入画面に。
- `LyricsPreviewView` の空状態/エラーを `ContentUnavailableView`(iOS17標準)に統一、取得中はProgressViewを中央表示。現在行ハイライトに軽いフェード。
- `CFBundleShortVersionString` を 1.2.2 → **1.3.0**(ユーザー目線で大きな見た目の変更のためマイナー)。
- 横画面の全画面歌詞ビュー(LandscapeLyricsView)とPiPは表示専用面なので今回は変更せず維持。

### 32. 横画面の全画面歌詞に行切り替えフェードを追加(v1.3.1)

縦画面カードの「現在行ハイライトのフェード」に相当する挙動を横画面にも。横画面は固定ウィンドウ(前/現在/次)の中身を差し替える方式なので、`.contentTransition(.opacity)` + `.animation(.easeInOut(duration: 0.2), value: activeIndex)` で、行が進むときに各スロットの文字をクロスフェード。

- PiPはラスタライズ(CGImage→CMSampleBuffer)方式で、アニメには連続フレーム生成が必要かつ現在の安定動作(DisplayImmediately/タイムベース無し)を壊すリスクがあるため今回は対象外(ユーザー判断でAのみ実装)。
- `CFBundleShortVersionString` を 1.3.0 → **1.3.1**(小さな演出追加、パッチ)。

### 33. 横画面を全行スクロール表示に変更(B2、v1.3.2)

横画面の固定ウィンドウ+フェード(項目32)は「その場で溶けて入れ替わる」ため読みづらい、との指摘を受け、全行スクロール方式に作り替え。

- `LandscapeLyricsView` を、全歌詞を並べた `ScrollView` + `ScrollViewReader` に変更。`activeIndex` 変化で `scrollTo(anchor: .center)` を `withAnimation` で駆動し、現在行を中央に保ちつつ上流れ。先頭/末尾も中央に来るよう上下に `height*0.45` のパディング。
- ②③は横画面では**文字サイズに読み替え**て適用: 目標表示行数 = (③?1:0)+1+②、`fontSize ≈ height / 行数 × 0.58`(22〜80でクランプ)。②が実質ズーム/密度つまみ。③はスクロールでは常に前行が見えるため密度+1の効きに留まる(割り切り)。
- `GeometryReader` で高さ取得。設定/回転で `base` が変わったら現在行を再センタリング。現在行は太字・やや大きめ・白、他は白45%。行の切り替えに軽い `.animation(value: activeIndex)`。
- PiPは従来どおり②③がそのまま適用(`LyricsLineWindow` はPiP側で引き続き使用)。`LandscapeLyricsView` は固定ウィンドウ方式(`LyricsLineWindow`/`DisplayLyricLine`)の使用をやめた。
- `CFBundleShortVersionString` を 1.3.1 → **1.3.2**。

### 34. 横画面の歌詞折り返しを調整(v1.3.3)

②=1・③OFF(目標行数L=2)でフォントが上限まで大きくなり、1行の歌詞が横幅からあふれて2行に折り返す問題への対応。

- 各行に `.lineLimit(1)` + `.minimumScaleFactor(0.35)` を付与し、長い行は折り返さず幅に合わせて縮小(1歌詞=1行に固定)。
- `maxFontSize` を 80 → 54 に。縦の高さだけで決めた大きい文字は横幅に対して過大なため、上限を下げて折り返しを起きにくく。
- 大きさ vs 折り返しは本質的にトレードオフ(2行ぶんで縦を埋めるほど大きい文字は長い歌詞の横幅に収まらない)。上限・最小倍率は今後の調整余地あり。
- `CFBundleShortVersionString` を 1.3.2 → **1.3.3**。

### 35. 横画面の②③の効きを実効化(v1.3.4)

実機で「③が無意味(現在行中央固定で常に前行が見える)」「②を変えてもサイズが変わらない(上限キャップに張り付き)」との指摘に対応。

- **③ → スクロールアンカー**: `showPreviousLine` ON=`.center`(前行が上に見える)、OFF=`UnitPoint(0.5, 0.16)`(現在行を上寄せ、前行は画面外)。③変更時に再スクロールで反映。これで「1行前を出す/出さない」が視覚的に意味を持つ。
- **② → 直線マッピングのフォントサイズ+行間**: 旧 `height/L*0.58` は低Lで上限54に張り付き②=1,2,3が同一サイズだった。`big(=height*0.15, ≤54) → small(=height*0.072, ≥22)` を②=1..5で線形補間。さらに行間を `base*(0.9 - 0.5*sizeT)` で②連動(①小=広い間隔/少行、⑤大=狭い/多行)にし、②の効果を強調。
- `CFBundleShortVersionString` を 1.3.3 → **1.3.4**。

### 36. 横画面②③を「表示行数」直接制御に作り替え(v1.3.5)

実機(②5/2/1・③OFF)で「③OFFでも前行が出る(②3〜5で顕著)」「②1で次の行が2行出る」との指摘。フォントサイズ中心の制御では画面内行数を直接制御できないのが原因。ユーザー提案の「行間で調整」を採用。

- `visibleLineCount = (③?2:1) + ②`。`pitch = height / visibleLineCount` を行のピッチに。`font = min(54, pitch*0.7)`(横幅で頭打ち)、`spacing = max(2, pitch - font*1.2)`。→ 行数が少ないほどフォントは上限で頭打ち、余った縦間隔が**広い行間**になり、狙った行数ちょうどに収まる(②1で次1行のみ+大きな隙間)。
- アンカーを行数基準に: `y = (③ON ? 1.5 : 0.5) / visibleLineCount`。③OFFは現在行が最上段(前行は画面外)、③ONは2段目(前行1つ上)。固定割合(0.16)だと小フォント時に前行が見えていたのを解消。
- `padding(.vertical, height)` で任意の行を目標位置へスクロール可能に。`onChange(of: pitch)` で②③/回転時に再配置。
- 旧 `fontSize/sizeT/scrollAnchor/minFontSize` を廃し `visibleLineCount` に集約。
- `CFBundleShortVersionString` を 1.3.4 → **1.3.5**。

### 37. 横画面の最下行の見切れを解消(固定スロット化、v1.3.6)

②3〜5・③OFFで一番下の行が中途半端に見切れる(「N行表示なのにN行出ていない」)との指摘。自由スクロールは端で必ず行が途切れるのが原因。フェードでの糊塗はユーザーが拒否(表示行数の詐称になる)。

- `ScrollView` をやめ、各行を `.frame(height: pitch)`(pitch=height/vis)の**固定スロット**に収める `VStack` に変更。vis スロットで画面をちょうど埋めるため、見切れる行が原理的に発生しない。
- 帯全体に `.offset(y: (currentSlot - activeIndex) * pitch)` を掛け、`.clipped()` で画面外を隠す。`currentSlot`=③OFF:0/③ON:1。activeIndex変化時に `.animation(value: activeIndex)` でスライド(上流れのスクロール感を維持)。
- 全行を非遅延VStackで描画(クリップ外は非表示)。曲数十行でも軽量。
- 副作用: 手動スクロールは不可(同期表示なので実害なし)。
- `CFBundleShortVersionString` を 1.3.5 → **1.3.6**。

### 38. 横画面スクロールを連続+上下フェードに(視認性優先、v1.3.7)

固定スロット(1.3.6)は「1行ずつ離散スライド」でカクつき視認性が悪いとの指摘。ユーザー判断で実装を1つ戻し(連続スクロール)、端の見切れはフェードで対応(案B方向)。

- 1.3.5 の `ScrollView` + `ScrollViewReader` + `scrollTo(anchor)` 連続スクロールに復帰。`anchor y = (③ON?1.5:0.5)/vis`。
- `.mask()` に上下フェードの `LinearGradient`(clear→black 0.05 / black→clear 0.85)を掛け、出入りする行を黒へ溶かす。上端のクリア領域(0.05)は③OFF最上位置(0.5/vis)より上なので現在行は褪せない。
- 行送りアニメを 0.4s に。手動スクロールは有効のまま(scrollDisabledはscrollToを阻害する報告があり不使用)。
- トレードオフ: 「N行きっちり全表示」は放棄(端はフェード)。代わりに滑らかで読みやすい。②は密度、③は現在行位置。
- `CFBundleShortVersionString` を 1.3.6 → **1.3.7**。

### 現状・残タスク

- 横画面スクロールを連続+上下フェードに(項目38、v1.3.7、視認性優先)。1.3.6の固定スロットは撤回。
- 横画面の最下行見切れを解消(項目37、v1.3.6)→ 視認性の観点で項目38に置き換え。
- 横画面②③を表示行数の直接制御に(項目36、v1.3.5)→ 項目37で固定スロット化。
- 横画面の②③を実効化(項目35、v1.3.4)→ 項目36で更に作り替え。
- 横画面の歌詞折り返しを調整(項目34、v1.3.3、1歌詞=1行固定+縮小)。
- 横画面を全行スクロール表示に変更、②③は文字サイズで疑似再現(項目33、v1.3.2)。
- 横画面の全画面歌詞に行切り替えフェードを追加(項目32、v1.3.1)→ 項目33のスクロール化で置き換え。PiPは方式上見送り。
- アプリUIをiOS標準デザインに整えた(項目31、v1.3.0)。
- 横画面の全画面歌詞にも曲タイトル/アーティストを表示(項目30、v1.2.2)。
- タップで横画面に入るボタンを追加(項目29、v1.2.1)。回転ロックON時でも横画面歌詞に入れる。
- **横画面PiP(①)は iOS 制約により断念**、代わりに横画面のアプリ内全画面歌詞表示で対応(項目28、v1.2)。
- バージョン表記は1.0基準のセマンティックバージョニング風に統一済み(項目26)。現在は **1.3.7**(横画面スクロールを連続+上下フェードに)。
- PiPの歌詞表示は行数をユーザー設定で変更可能(次1〜5行/1行前表示トグル、項目27)。実機確認済み。
- Issue #1の対応項目(1・2a・2b・3・4・5)は実装済み、README/CHANGELOGにも反映済み。
- **中核機能(Spotify曲検知→歌詞取得→PIP同期表示)は実機でエンドツーエンド動作確認済み**。プレイリスト再生・広告挟み込みでも動作継続を確認。PiPの見た目(横長ワイド、ミニプレビュー無し)もユーザー確認済み。
- **PiPは完全自動運用**(バックグラウンドで自動開始・フォアグラウンドで自動終了、手動ボタンなし)。実機で全パターン確認済み。
- **WebSocketの頻繁切断は大幅に改善**(専用URLSessionConfigurationで対応、フォアグラウンド利用中は8分半以上安定)。PiP未起動時のバックグラウンド切断は既知の挙動として許容(現在はPiPが常時自動起動するため、実質的にほぼ発生しなくなった)。
- **画面上のデバッグログパネルは非表示化済み**(リモートログサーバーへの送信は`UserDefaults`永続化のURLで独立して継続動作、実機確認済み)。
- **アプリアイコンも新規デザインに差し替え済み**(実機でSpotifyアイコンと並べて色味も確認済み)。
- リポジトリはパブリックに切り替え済み。GitHub課金($8.74)の免除依頼は返答待ち。
- lrclib/Spotifyどちらにも同期歌詞が無い曲は「歌詞なし」表示になる(仕様上の制約)。
- YouTube Music / Amazon Music対応は実現可能性の調査のみ完了、未着手(詳細は項目24参照)。
