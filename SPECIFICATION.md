# 字幕抽出ツール 仕様書

## 1. 概要

### 1.1 製品名
字幕抽出ツール（Subtitle Extractor）

### 1.2 バージョン
v4.2

### 1.3 目的
ゲーム動画や映像コンテンツから字幕テキストを自動抽出し、編集・翻訳・SRT形式での出力を行うデスクトップアプリケーション。

### 1.4 対象ユーザー
- ゲーム実況者・配信者
- 動画翻訳者
- 字幕制作者
- コンテンツクリエイター

---

## 2. 機能仕様

### 2.1 コア機能

#### 2.1.1 動画読み込み
| 項目 | 仕様 |
|------|------|
| 対応形式 | MP4, AVI, MKV, MOV, WMV |
| 読み込み方法 | OpenCV (cv2.VideoCapture) |
| プレビュー | リアルタイムフレーム表示 |

#### 2.1.2 OCR字幕抽出
| 項目 | 仕様 |
|------|------|
| OCRエンジン | meikiOCR |
| 対応言語 | 日本語（主）、英語 |
| サンプリング | 可変FPS（1.0〜10.0） |
| 領域指定 | マウスドラッグによる矩形選択 |

#### 2.1.3 スクロール字幕検出
| 項目 | 仕様 |
|------|------|
| 検出方式 | テキスト類似度比較 |
| 類似度閾値 | 0.0〜1.0（デフォルト: 0.6） |
| 安定フレーム数 | 1〜10（デフォルト: 2） |

#### 2.1.4 AI翻訳
| 項目 | 仕様 |
|------|------|
| 翻訳エンジン | Ollama（ローカルLLM） |
| 対応モデル | llama3.2:3b, llama3.2:1b, gemma2:2b, qwen2.5:3b |
| 対応言語 | ja, en, zh, ko |

#### 2.1.5 SRT出力
| 項目 | 仕様 |
|------|------|
| 形式 | SubRip Subtitle (.srt) |
| エンコーディング | UTF-8 |
| タイムコード形式 | HH:MM:SS,mmm |

### 2.2 UI機能

#### 2.2.1 動画プレーヤー
- 再生/一時停止/停止
- シークバーによる位置移動
- キーボードショートカット対応
- 字幕オーバーレイ表示
- 翻訳テキスト表示切替

#### 2.2.2 字幕リスト
- 一覧表示（番号、時間、テキスト）
- クリックで選択・編集
- スクロール対応

#### 2.2.3 字幕編集パネル
- 開始/終了時間の編集
- テキストの編集
- 翻訳テキストの編集
- 追加/削除機能

#### 2.2.4 設定ダイアログ
- 抽出設定タブ
- 翻訳設定タブ
- 表示設定タブ
- 設定の保存/読み込み

---

## 3. 技術仕様

### 3.1 開発言語・フレームワーク
| 項目 | 技術 |
|------|------|
| 言語 | Python 3.8+ |
| GUI | Tkinter / ttk |
| 画像処理 | OpenCV, Pillow |
| OCR | meikiOCR |
| AI | Ollama API |

### 3.2 ファイル構成

```
字幕抽出ツール/
├── main_app.py          # メインアプリケーション
├── ocr_engines.py       # OCRエンジンモジュール
├── scroll_detector.py   # スクロール字幕検出
├── ollama_processor.py  # AI翻訳処理
├── requirements.txt     # 依存パッケージ
├── settings.json        # ユーザー設定（自動生成）
├── README.md            # 概要
├── MANUAL.md            # ユーザーマニュアル
└── SPECIFICATION.md     # 仕様書（本文書）
```

### 3.3 クラス構成

#### MainApplication
メインウィンドウとアプリケーションロジックを管理。

| メソッド | 説明 |
|----------|------|
| _create_menu() | メニューバーの構築 |
| _create_ui() | UIコンポーネントの構築 |
| _browse_video() | 動画ファイル選択 |
| _start_extraction() | 字幕抽出の開始 |
| _translate_subtitles() | AI翻訳の実行 |
| _save_srt() | SRTファイル保存 |

#### VideoPlayer
動画再生とプレビュー表示を管理。

| メソッド | 説明 |
|----------|------|
| load_video() | 動画の読み込み |
| show_frame() | フレームの表示 |
| play() | 再生開始 |
| pause() | 一時停止 |
| seek() | シーク |

#### SubtitleExtractor
OCR処理と字幕抽出を管理。

| メソッド | 説明 |
|----------|------|
| extract() | 字幕抽出の実行 |
| _is_garbage_text() | ゴミ文字判定 |
| _clean_text() | テキストクリーンアップ |

#### SettingsDialog
設定ダイアログを管理。

| メソッド | 説明 |
|----------|------|
| _create_extract_settings() | 抽出設定UI |
| _create_translate_settings() | 翻訳設定UI |
| _create_display_settings() | 表示設定UI |

### 3.4 データ構造

#### Subtitle
```python
@dataclass
class Subtitle:
    index: int           # 字幕番号
    start_time: float    # 開始時間（秒）
    end_time: float      # 終了時間（秒）
    text: str            # 字幕テキスト
    translated: str      # 翻訳テキスト
    confidence: float    # 信頼度
```

#### AppSettings
```python
@dataclass
class AppSettings:
    fps_sample: float           # サンプリングFPS
    detect_scroll: bool         # スクロール検出
    auto_translate: bool        # 自動翻訳
    translate_source: str       # 翻訳元言語
    translate_target: str       # 翻訳先言語
    subtitle_font_size: int     # フォントサイズ
    subtitle_bg_opacity: int    # 背景透明度
    min_subtitle_duration: float # 最小字幕長
    max_subtitle_duration: float # 最大字幕長
    similarity_threshold: float  # 類似度閾値
    stability_frames: int       # 安定フレーム数
    ollama_model: str           # Ollamaモデル
```

---

## 4. 外部依存

### 4.1 Pythonパッケージ

| パッケージ | バージョン | 用途 |
|------------|------------|------|
| opencv-python | >=4.5 | 動画処理 |
| Pillow | >=9.0 | 画像処理 |
| numpy | >=1.20 | 数値計算 |
| meikiocr | >=1.0 | OCR |
| requests | >=2.25 | HTTP通信 |

### 4.2 外部ソフトウェア

| ソフトウェア | 必須/任意 | 用途 |
|--------------|-----------|------|
| FFmpeg | 任意 | 音声再生 |
| Ollama | 任意 | AI翻訳 |

---

## 5. 制限事項

### 5.1 既知の制限

1. **動画形式**: 一部のコーデックは対応していない場合があります
2. **OCR精度**: 低解像度や特殊フォントでは精度が低下します
3. **AI翻訳**: Ollamaのインストールが必要です
4. **パフォーマンス**: 高解像度動画では処理が重くなる場合があります

### 5.2 推奨環境

- 動画解像度: 720p〜1080p
- 字幕フォント: 標準的なゴシック体
- 字幕背景: 単色または半透明

---

## 6. 更新履歴

| バージョン | 日付 | 変更内容 |
|------------|------|----------|
| v4.2 | 2025-01-17 | 再生パフォーマンス改善、ドキュメント追加 |
| v4.1 | 2025-01-17 | Windows標準UIスタイル、詳細設定ダイアログ |
| v4.0 | 2025-01-17 | 商品レベルUI、機能整理 |
| v3.5 | 2025-01-17 | ゴミ文字フィルタリング |
| v3.0 | 2025-01-17 | meikiOCR統合、スクロール検出 |

---

## 7. ライセンス

本ソフトウェアは商用利用可能です。
依存パッケージのライセンスについては各パッケージのドキュメントを参照してください。
