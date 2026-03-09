# Subtitle Extractor for macOS

SwiftUI ベースの macOS 字幕抽出・翻訳・焼き込みツールです。  
ゲーム動画や配信アーカイブから字幕を抽出し、翻訳、追加字幕、オーバーレイ合成、`SRT` / `FCPXML` / `MP4` / `MOV` 書き出しまでを 1 本で扱えます。

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
- 追加字幕レイヤー
- オーバーレイ画像のクロマキー透過
- 字幕枠 / 追加字幕枠 / 動画窓の手動調整
- macOS font と追加インストール font の利用
- font お気に入り登録
- 設定と overlay preset の永続化
- 初回起動チュートリアル
- キーボードショートカット

## 必要環境

- macOS 14 以降
- Python 3
- 必要な Python モジュール

## セットアップ

```bash
pip3 install -r requirements.txt
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

## 配布物

この作業フォルダには GitHub 配布用 zip / pkg を生成できます。

- app bundle: `.build/arm64-apple-macosx/release/SubtitleExtractorMacApp.app`
- zip: `release/SubtitleExtractorMacApp-macOS.zip`
- pkg: `release/SubtitleExtractorMacApp-macOS.pkg`

SHA-256:

```text
9a80c71cf40277262588cc73de7edffb3aaca0a36b913c4f1fd5eb4df0369ddd  release/SubtitleExtractorMacApp-macOS.zip
```

pkg 作成:

```bash
./package_mac_pkg.sh release 1.0.0
```

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
