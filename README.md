# Caption Studio for macOS

SwiftUI ベースの macOS 字幕抽出・翻訳・焼き込みツールです。  
ゲーム動画や配信アーカイブから字幕を抽出し、翻訳、オーバーレイ合成、`SRT` / `FCPXML` / `MP4` / `MOV` 書き出しまでを 1 本で扱えます。

## 現在のアプリ構成

- macOS ネイティブ UI: SwiftUI + AppKit
- OCR / 翻訳 backend: Python
- 動画書き出し: AVFoundation
- 対応出力:
  - `SRT`
  - `FCPXML`
  - 字幕焼き込み `MP4`
  - 字幕焼き込み `MOV`

## 主な機能

- 動画 preview とシーク
- 字幕抽出範囲のドラッグ指定
- 抽出後の字幕一覧編集
- 翻訳字幕の保存
- オーバーレイ画像のクロマキー透過
- 字幕枠 / 動画窓の手動調整
- macOS font と追加インストール font の利用
- font お気に入り登録
- 設定と overlay preset の永続化
- 初回セットアップ + クイックスタートチュートリアル
- キーボードショートカット

## 必要環境

- macOS 14 以降
- Python 3
- Python backend 用モジュール

配布用の `release app / zip / pkg` には backend 実行ファイルを同梱するので、受け取る側の Mac に `Xcode` や `Python` は不要です。  
翻訳を使う場合だけ `Ollama` が必要です。

## セットアップ

```bash
./Tools/setup_python_backend.sh
```

このスクリプトは `~/Library/Application Support/CaptionStudio/python-env` にローカル専用の Python 環境を作り、必要な backend モジュールをまとめて入れます。  
起動時はこの managed Python を自動検出します。

手動で入れたい場合:

```bash
python3 -m pip install -r requirements.txt
```

翻訳に Ollama を使う場合:

```bash
ollama serve
ollama pull gemma3:4b
```

## 起動方法

Xcode で開く:

```bash
./open_in_xcode.sh
```

そのまま起動:

```bash
./run_editor.sh
```

release build:

```bash
./build_mac.sh
```

配布用インストーラーを作る:

```bash
./package_mac_pkg.sh release
```

## 配布物

この作業フォルダには GitHub 配布用 `app / zip / pkg` を生成できます。  
受け取る側に Xcode や Python は不要で、通常は `.pkg` を渡せばインストールできます。

- app bundle: `release/<version>/Caption Studio.app`
- zip: `release/<version>/CaptionStudio-<version>-macOS.zip`
- pkg: `release/<version>/CaptionStudio-<version>-macOS.pkg`

`.pkg` は Installer から入れられます。通常は `/Applications`、ユーザー install では `~/Applications` に配置されます。

SHA-256 はブランド変更後の配布物を再生成したあとに更新してください。

installer 作成:

```bash
./package_mac_pkg.sh release
```

一般公開前のチェック:

```bash
./Tools/release_preflight.sh
```

notarization まで含めた配布 build:

```bash
./notarize_release.sh
```

事前に必要なもの:

- login keychain に `Developer ID Application` 証明書
- login keychain に `Developer ID Installer` 証明書
- `notarytool` の認証 profile

認証 profile の保存例:

```bash
xcrun notarytool store-credentials "SubtitleExtractorNotary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID"
```

`notarize_release.sh` は既定で `SubtitleExtractorNotary` という profile 名を見ます。  
別名を使う場合は `NOTARY_PROFILE=YourProfile ./notarize_release.sh` で実行できます。

一般公開までの順番は [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) にまとめています。

## アイコン差し替え

自分で作ったアイコンを入れる場合は次のどちらかです。

- そのまま使う: `Assets/AppIcon.icns`
- PNG から自動変換させる: `Assets/AppIcon.png`

おすすめは `1024x1024` の PNG を `Assets/AppIcon.png` として置く方法です。  
その状態で `./package_mac_pkg.sh release` を実行すると、配布用の app / zip / pkg に反映されます。

版番号はルートの `VERSION` を更新すると、app / pkg / notarize の既定値に反映されます。
`./Tools/bump_version.sh patch` で `1.0.0 -> 1.0.1` のように上げられます。
配布物は `release/<version>/` にまとまり、`CaptionStudio-<version>-macOS.zip` / `CaptionStudio-<version>-macOS.pkg` という名前で出力されます。

## 設定

- ツールバー右上の `gear` から設定を開けます。
- macOS のメニューバーからも `設定…` `⌘,` で開けます。
- 設定画面では、アプリ言語、ワークスペースレイアウト、Ollama の状態確認、更新確認をまとめて扱えます。
- アップデート設定の `プレリリース版も候補に含める` をオンにすると、GitHub Releases の beta / rc 版も更新候補として確認できます。

## ショートカット

- `⌘O`: 動画を開く
- `⌘⇧O`: オーバーレイを開く
- `⌘⇧I`: SRT を読み込む
- `⌘⇧E`: 字幕抽出
- `⌘↩`: 翻訳
- `Space`: 再生 / 停止
- `⌘⇧N`: 字幕追加
- `⌘⌫`: 字幕削除
- `⌘⇧L`: 時間補正
- `⌘⇧4`: MP4 書き出し
- `⌘⇧5`: MOV 書き出し
- `⌘/`: チュートリアル表示

## 注意

現在の zip / pkg はローカル build を ad-hoc 署名したものです。  
GitHub で一般公開して「ダウンロードしてすぐ開ける」状態にするには、最終的に Apple Developer ID 署名と notarization が必要です。
