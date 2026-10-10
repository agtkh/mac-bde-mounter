# Mac BDE Mounter

[English README](README.md)

**Mac BDE Mounter** は、macOS（macOS 13 Ventura 以降、Apple Silicon M1〜M5 対応）向けの軽量な常駐型メニューバーユーティリティです。カーネル拡張機能（KEXT）や Homebrew 等の外部パッケージマネージャーを必要とせず、Windows の BitLocker® 暗号化外付けドライブ（exFAT、NTFS、FAT32）の自動検知、パスワード解除、およびマウントをシームレスに行います。

> **商標および記述的利用に関する表示**:
> BitLocker® は、Microsoft Corporation の登録商標です。Mac および macOS は、Apple Inc. の商標です。
> Mac BDE Mounter は独立したオープンソースプロジェクトであり、Microsoft Corporation または Apple Inc. との提携、後援、承認等の関係はありません。詳細な法的表示については [TRADEMARKS.md](TRADEMARKS.md) をご覧ください。

---

## 主な機能

- **USB 接続の自動検知**: `DiskArbitration.framework` を使用し、ドライブの接続・切断をリアルタイムに検知。
- **macOS 初期化ダイアログの抑止**: 接続直後に BitLocker パーティションを早期クレーム（`DADiskClaim`）することで、macOS 標準の「セットしたディスクは、このコンピュータで読み取れないディスクでした（初期化...）」警告ダイアログを抑止。
- **キーチェーン連携**: ボリュームの GUID をキーとして、解除パスワードを macOS キーチェーン（`Security.framework`）に安全に保存・呼び出し。
- **特権分離アーキテクチャ**: UI およびイベント監視は一般ユーザー権限で動作し、マウントおよび raw ブロックデバイスへのアクセスは `SMAppService` で管理される独立した特権ヘルパーデーモン（`top.agata.MacBDEMounter.helper`）が担当。
- **完全スタンドアロン構成**: アプリケーションバンドル内に `dislocker` (GPLv2) および `FUSE-T` ユーザースペースファイルシステムドライバを内包。
- **安全なアンマウント保護**: ドライブ内のファイルが開かれている状態での強制アンマウント（`umount -f`）を防止し、ユーザーに安全を促すプロンプトを表示。
- **メニューバー常駐 UI**: 接続中ドライブの一覧、リアルタイム状態表示（ロック中、解除中、マウント中、マウント完了）、Finder で開く・取り出し等のクイックアクションを提供。
- **多言語対応 (i18n)**: 日本語および英語に完全対応。Xcode String Catalogs (`.xcstrings`) を採用し、将来の言語追加もコード変更なしで容易。
- **旧バージョンからの自動移行**: 旧 `BitLockerMounter` のデーモンや設定を自動クリーンアップし、古いアプリが `/Applications` に存在する場合は通知とゴミ箱移動機能を提供。
- **完全アンインストール機能**: メニュー内または CLI スクリプトから、デーモン、ヘルパーツール、サポートファイル、環境設定、TCC 権限を完全に消去可能。
- **自動アップデート**: Sparkle フレームワークを統合し、安全な自動更新をサポート。

---

## アーキテクチャ

```
[外付けドライブ接続]
       │
       ▼
 [DiskArbitration] ──(DADiskClaim: 初期化ダイアログ抑止)──► [メインアプリ (User)]
                                                                  │
                                                (キーチェーン照会 / パスワード入力)
                                                                  │
                                                        [XPC 通信]
                                                                  │
                                                                  ▼
                                                      [ヘルパーデーモン (Root)]
                                                                  │
                                                ┌─────────────────┴─────────────────┐
                                                ▼                                   ▼
                                       [dislocker + FUSE-T]               [hdiutil attach -nomount]
                                                │                                   │
                                                └─────────────────┬─────────────────┘
                                                                  ▼
                                                       [DADiskMount -> /Volumes]
```

---

## インストールとクイックスタート（ビルド不要）

Mac BDE Mounter は事前ビルド済みパッケージ（DMG）を提供しています。**ソースコードのビルドや Xcode、Homebrew のインストールは一切不要です。**

Apple の高額な有料開発者証明書（年間$99）を介さずにオープンソースとして配布しているため、ダウンロード後に**自己署名（アドホック署名）**を1度行うだけですぐに使用できます。

### 簡単3ステップで使い始める

1. **DMG をダウンロード**:
   [**GitHub Releases**](https://github.com/agtkh/mac-bed-mounter/releases) から最新の `MacBDEMounter.dmg` をダウンロードします。
2. **Applications に配置**:
   ダウンロードした `MacBDEMounter.dmg` を開き、`MacBDEMounter.app` を **Applications** フォルダにドラッグ＆ドロップします。
3. **自己署名（Gatekeeper 検疫解除）を実行**:
   DMG 内にある **`SelfSign.command`** をダブルクリックします。
   > [!TIP]
   > 初回起動時に「開発元を検証できないため開けません」と警告された場合は、`SelfSign.command` を**右クリック（または Control キーを押しながらクリック）して「開く」**を選択してください。
   > 
   > **ターミナル派の方**: 以下のコマンドを1行実行するだけでも完了します:
   > ```bash
   > sudo xattr -cr /Applications/MacBDEMounter.app && codesign --force --deep -s - /Applications/MacBDEMounter.app
   > ```

### 初回起動時の設定

1. `/Applications/MacBDEMounter.app` を起動します。メニューバーにアイコンが表示されます。
2. **フルディスクアクセス (Full Disk Access) を許可**:
   macOS の **システム設定 > プライバシーとセキュリティ > フルディスクアクセス** を開き、**Mac BDE Mounter** を「オン」にしてください。
   *(※接続された外付けドライブから初期化警告を出さずに BitLocker ボリュームを検知するために必要です)*
3. **特権ヘルパーの承認**:
   バックグラウンドでのマウント処理を担当するヘルパーデーモンのインストール確認が表示されたら、管理者パスワードまたは Touch ID を入力して承認します。

これで準備完了です！Windows で暗号化された BitLocker ドライブを接続すると自動的に認識され、パスワード入力プロンプトが表示されます。

---

## 動作環境

- **OS**: macOS 13.0 (Ventura) 以降
- **対応ハードウェア**: Apple Silicon Mac (M1 / M2 / M3 / M4 / M5)

---

## ソースコードからのビルド（開発者向け）

自分でビルドやカスタマイズを行いたい開発者向けの手順です。通常利用のユーザーは上記の手順でバイナリをご利用いただけます。

### 必要な開発ツール
- Xcode 15 以降（または Command Line Tools + Xcode.app）
- `cmake` (`brew install cmake`)
- `xcodegen` (`brew install xcodegen`)
- Python 3 (`python3`)


### 1. サードパーティ依存ライブラリのビルド (dislocker, mbedTLS, FUSE-T)

```bash
make deps
```

このコマンドにより:
1. 公式 FUSE-T パッケージをローカルに取得・展開（システムへのインストールは不要）。
2. 静的ライブラリ `mbedTLS 3.6.7` をビルド。
3. `dislocker` を静的リンクでビルド。
4. スタンドアロンバイナリを `vendor/dist/bin/` に配置。

### 2. Xcode プロジェクト生成とビルド

```bash
make project   # XcodeGen により MacBDEMounter.xcodeproj を生成
make build     # Debug 構成でビルド（アドホック署名）
```

ビルドされたアプリは `build.nosync/Debug/MacBDEMounter.app` に出力されます。

### 3. 単体テストと多言語検証の実行

```bash
make test         # xcodebuild によるテスト実行
make l10n-check   # 文字列カタログの全言語翻訳チェック
```

### 4. アプリケーションの実行

```bash
make run
```

---

## 多言語対応 (i18n) と言語の追加方法

Mac BDE Mounter は、Xcode String Catalogs を使用して多言語化されています:
- [`App/Resources/Localizable.xcstrings`](App/Resources/Localizable.xcstrings): アプリケーション UI、ステータス、警告、通知の文字列
- [`App/Resources/InfoPlist.xcstrings`](App/Resources/InfoPlist.xcstrings): アプリ表示名および TCC プライバシー権限の説明文

### 新しい言語を追加する手順

1. `project.yml` の `knownRegions` に対象言語コード（例: `de`, `fr`, `zh-Hans` 等）を追加します。
2. `App/Resources/Localizable.xcstrings` および `App/Resources/InfoPlist.xcstrings` に対象言語の翻訳を追加します（Xcode の String Catalog エディタまたは JSON 編集）。
3. `make l10n-check` を実行して、未翻訳キーがないか検証します。
4. `make project && make test` を実行して反映を確認します。

アプリの表示言語は、macOS の「システム設定 > 一般 > 言語と地域」の優先言語順序に従って自動的に切り替わります。

---

## 初期設定と必要な権限

初回起動時、macOS で以下の権限設定が必要です:

1. **フルディスクアクセス (Full Disk Access)**:
   **システム設定 > プライバシーとセキュリティ > フルディスクアクセス** で **Mac BDE Mounter** を有効にしてください。これにより、初期化警告を出さずに raw ブロックデバイス（`/dev/rdisk*`）から BitLocker ヘッダを検知できるようになります。
2. **特権ヘルパーデーモン**:
   アプリのセットアップ画面からインストールできます。ローカル開発用のアドホック署名ビルドで手動インストールする場合は以下を実行します:
   ```bash
   make dev-install-helper
   ```
   ヘルパーを削除する場合:
   ```bash
   make dev-uninstall-helper
   ```

---

## 完全アンインストール手順

Mac BDE Mounter および関連するすべてのシステムサービス、デーモン、マウントポイント、キャッシュ、設定、権限を完全に消去するには、以下のいずれかの方法を使用します:

### 方法 1: アプリ画面から実行
1. メニューバーの **Mac BDE Mounter** アイコンをクリック。
2. **About & Licenses...**（または **Setup...**）を開く。
3. **アンインストール...** をクリック。
4. ダイアログを確認し、管理者認証（Touch ID またはパスワード）を承認。

### 方法 2: ターミナルから実行 (CLI)
リポジトリルートから:
```bash
make uninstall
# または直接:
sudo ./scripts/uninstall.sh
```

### 方法 3: DMG パッケージから実行
`MacBDEMounter.dmg` 内に含まれる `Uninstall.command` をダブルクリックして実行。

アンインストーラーは以下を完全に消去します:
- 仮想 BitLocker ドライブのアンマウント
- 実行中プロセス (`MacBDEMounter`, 旧 `BitLockerMounter`, `dislocker`, `go-nfsv4`, ヘルパー) の停止
- 特権ヘルパーデーモン (`top.agata.MacBDEMounter.helper` および旧 `top.agata.BitLockerMounter.helper`)
- システムサポートファイル (`/Library/Application Support/MacBDEMounter` および旧パス)
- 一時ファイルおよび作業ログ (`/tmp/blm-*`, `/private/tmp/dislocker_*`)
- ユーザー環境設定、キャッシュ、保存された状態 (`~/Library/Preferences/top.agata.MacBDEMounter*` 等)
- `/Applications` 内のアプリケーション本体
- フルディスクアクセス権限 (TCC 設定のリセット)

---

## ライセンスおよび商標

- **作者**: K. Agata
- **ライセンス**: [GNU General Public License v2.0 or later (GPL-2.0-or-later)](LICENSE)
- **サードパーティ通知**: 同梱ライブラリ（`dislocker`, `FUSE-T`, `mbedTLS`, `Sparkle`）のライセンス詳細は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。
- **商標表示**: 商標帰属および免責事項については [TRADEMARKS.md](TRADEMARKS.md) を参照してください。
