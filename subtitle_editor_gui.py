"""
字幕抽出・編集GUIアプリケーション
- 複数のOCRエンジン対応（EasyOCR, manga-ocr, GPT-4 Vision, Llama Vision, LLaVA, moondream）
- スクロール字幕検出機能
- AI校正・翻訳機能
- 字幕編集機能
- SRT入出力
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext
import threading
import cv2
import os
from pathlib import Path
from typing import Optional, List
from dataclasses import dataclass


@dataclass
class Subtitle:
    """字幕データ"""
    start_time: float
    end_time: float
    text: str
    translated: str = ""
    is_complete: bool = True


class SubtitleEditorGUI:
    """字幕抽出・編集GUIアプリケーション"""
    
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("字幕抽出・編集ツール v2.0")
        self.root.geometry("1200x800")
        
        # 状態変数
        self.video_path: Optional[str] = None
        self.subtitles: List[Subtitle] = []
        self.selected_index: int = -1
        self.region = None  # 字幕領域
        self.is_processing = False
        self.is_playing = False
        self.cap = None  # VideoCapture
        
        # UI構築
        self._create_menu()
        self._create_main_layout()
        self._create_status_bar()
        
        # キーバインド
        self.root.bind('<Control-s>', lambda e: self.save_srt())
        self.root.bind('<Control-o>', lambda e: self.open_video())
    
    def _create_menu(self):
        """メニューバーを作成"""
        menubar = tk.Menu(self.root)
        self.root.config(menu=menubar)
        # ファイルメニュー
        file_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="ファイル", menu=file_menu)
        file_menu.add_command(label="動画を開く...", command=self.open_video)
        file_menu.add_command(label="SRTを開く...", command=self.open_srt)
        file_menu.add_separator()
        file_menu.add_command(label="SRTを保存...", command=self.save_srt)
        file_menu.add_command(label="翻訳SRTを保存...", command=self.save_translated_srt)
        file_menu.add_separator()
        file_menu.add_command(label="終了", command=self.root.quit)
        
        # ツールメニュー
        tools_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="ツール", menu=tools_menu)
        tools_menu.add_command(label="詳細設定...", command=self.open_settings)
        
        # ヘルプメニュー
        help_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="ヘルプ", menu=help_menu)
        help_menu.add_command(label="使い方", command=self.show_help)
    
    def _create_main_layout(self):
        """メインレイアウトを作成"""
        # メインフレーム
        main_frame = ttk.Frame(self.root, padding=10)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # 左右に分割
        left_frame = ttk.Frame(main_frame)
        left_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        right_frame = ttk.Frame(main_frame, width=400)
        right_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=(10, 0))
        right_frame.pack_propagate(False)
        
        # === 左側: 動画プレビューと設定 ===
        self._create_video_panel(left_frame)
        self._create_settings_panel(left_frame)
        
        # === 右側: 字幕リストと編集 ===
        self._create_subtitle_panel(right_frame)
    
    def _create_video_panel(self, parent):
        """動画プレビューパネルを作成"""
        video_frame = ttk.LabelFrame(parent, text="動画プレビュー", padding=5)
        video_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 10))
        
        # ファイル選択
        file_frame = ttk.Frame(video_frame)
        file_frame.pack(fill=tk.X, pady=(0, 5))
        
        self.video_path_var = tk.StringVar()
        ttk.Entry(file_frame, textvariable=self.video_path_var, state='readonly').pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(file_frame, text="参照...", command=self.open_video).pack(side=tk.RIGHT, padx=(5, 0))
        
        # プレビューキャンバス
        self.canvas = tk.Canvas(video_frame, bg='black', width=640, height=360)
        self.canvas.pack(fill=tk.BOTH, expand=True)
        self.canvas.bind('<Button-1>', self._on_canvas_click)
        self.canvas.bind('<B1-Motion>', self._on_canvas_drag)
        self.canvas.bind('<ButtonRelease-1>', self._on_canvas_release)
        
        # シークバーと再生コントロール
        seek_frame = ttk.Frame(video_frame)
        seek_frame.pack(fill=tk.X, pady=(5, 0))
        
        self.play_btn = ttk.Button(seek_frame, text="▶ 再生", command=self.toggle_play, width=6)
        self.play_btn.pack(side=tk.LEFT, padx=(0, 5))
        
        self.seek_var = tk.DoubleVar(value=0)
        self.seek_scale = ttk.Scale(seek_frame, from_=0, to=100, variable=self.seek_var, 
                                    orient=tk.HORIZONTAL, command=self._on_seek)
        self.seek_scale.pack(side=tk.LEFT, fill=tk.X, expand=True)
        
        self.time_label = ttk.Label(seek_frame, text="00:00 / 00:00")
        self.time_label.pack(side=tk.LEFT, padx=(5, 5))
        
        self.preview_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(seek_frame, text="字幕プレビュー", variable=self.preview_var, command=self._update_preview).pack(side=tk.RIGHT)
        
        # プレビュー言語選択（原文 / 翻訳）
        self.preview_lang_var = tk.StringVar(value="original")
        ttk.Radiobutton(seek_frame, text="翻訳", variable=self.preview_lang_var, value="translated", command=self._update_preview).pack(side=tk.RIGHT, padx=(0, 5))
        ttk.Radiobutton(seek_frame, text="原文", variable=self.preview_lang_var, value="original", command=self._update_preview).pack(side=tk.RIGHT, padx=(0, 2))
        
        # 領域選択状態
        self.drag_start = None
        self.drag_rect = None
    
    def _create_settings_panel(self, parent):
        """設定パネルを作成"""
        settings_frame = ttk.LabelFrame(parent, text="設定", padding=5)
        settings_frame.pack(fill=tk.X)
        
        # サンプリングFPS
        fps_frame = ttk.Frame(settings_frame)
        fps_frame.pack(fill=tk.X, pady=2)
        
        ttk.Label(fps_frame, text="サンプリングFPS:").pack(side=tk.LEFT)
        self.fps_var = tk.DoubleVar(value=2.0)
        ttk.Spinbox(fps_frame, from_=0.5, to=10, increment=0.5, textvariable=self.fps_var, width=5).pack(side=tk.LEFT, padx=(5, 0))
        
        # オプション
        options_frame = ttk.Frame(settings_frame)
        options_frame.pack(fill=tk.X, pady=2)
        
        self.scroll_detect_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(options_frame, text="スクロール字幕検出", variable=self.scroll_detect_var).pack(side=tk.LEFT)
        
        self.ai_correct_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(options_frame, text="AI校正", variable=self.ai_correct_var).pack(side=tk.LEFT, padx=(10, 0))
        
        self.translate_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(options_frame, text="英語翻訳", variable=self.translate_var).pack(side=tk.LEFT, padx=(10, 0))
        
        # 字幕領域表示
        region_frame = ttk.Frame(settings_frame)
        region_frame.pack(fill=tk.X, pady=2)
        
        ttk.Label(region_frame, text="字幕領域:").pack(side=tk.LEFT)
        self.region_label = ttk.Label(region_frame, text="未設定（全画面）")
        self.region_label.pack(side=tk.LEFT, padx=(5, 0))
        ttk.Button(region_frame, text="リセット", command=self._reset_region).pack(side=tk.RIGHT)
        
        # 実行ボタン
        button_frame = ttk.Frame(settings_frame)
        button_frame.pack(fill=tk.X, pady=(10, 0))
        
        self.extract_btn = ttk.Button(button_frame, text="字幕を抽出", command=self.extract_subtitles)
        self.extract_btn.pack(side=tk.LEFT)
        
        self.stop_btn = ttk.Button(button_frame, text="中止", command=self.stop_extraction, state=tk.DISABLED)
        self.stop_btn.pack(side=tk.LEFT, padx=(5, 0))
        
        # プログレスバー
        self.progress_var = tk.DoubleVar(value=0)
        self.progress_bar = ttk.Progressbar(settings_frame, variable=self.progress_var, maximum=100)
        self.progress_bar.pack(fill=tk.X, pady=(5, 0))
    
    def _create_subtitle_panel(self, parent):
        """字幕パネルを作成"""
        # 字幕リスト
        list_frame = ttk.LabelFrame(parent, text="字幕リスト", padding=5)
        list_frame.pack(fill=tk.BOTH, expand=True)
        
        # ボタン
        btn_frame = ttk.Frame(list_frame)
        btn_frame.pack(fill=tk.X, pady=(0, 5))
        
        ttk.Button(btn_frame, text="追加", command=self.add_subtitle).pack(side=tk.LEFT)
        ttk.Button(btn_frame, text="削除", command=self.delete_subtitle).pack(side=tk.LEFT, padx=2)
        ttk.Button(btn_frame, text="↑", command=self.move_up, width=3).pack(side=tk.LEFT, padx=2)
        ttk.Button(btn_frame, text="↓", command=self.move_down, width=3).pack(side=tk.LEFT)
        
        # リストボックス
        list_container = ttk.Frame(list_frame)
        list_container.pack(fill=tk.BOTH, expand=True)
        
        self.subtitle_list = tk.Listbox(list_container, selectmode=tk.SINGLE, font=('TkDefaultFont', 10))
        self.subtitle_list.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.subtitle_list.bind('<<ListboxSelect>>', self._on_subtitle_select)
        
        scrollbar = ttk.Scrollbar(list_container, orient=tk.VERTICAL, command=self.subtitle_list.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.subtitle_list.config(yscrollcommand=scrollbar.set)
        
        # 編集パネル
        edit_frame = ttk.LabelFrame(parent, text="字幕編集", padding=5)
        edit_frame.pack(fill=tk.X, pady=(10, 0))
        
        # 時間
        time_frame = ttk.Frame(edit_frame)
        time_frame.pack(fill=tk.X, pady=2)
        
        ttk.Label(time_frame, text="開始:").pack(side=tk.LEFT)
        self.start_time_var = tk.StringVar()
        ttk.Entry(time_frame, textvariable=self.start_time_var, width=10).pack(side=tk.LEFT, padx=(2, 10))
        
        ttk.Label(time_frame, text="終了:").pack(side=tk.LEFT)
        self.end_time_var = tk.StringVar()
        ttk.Entry(time_frame, textvariable=self.end_time_var, width=10).pack(side=tk.LEFT, padx=2)
        
        # テキスト
        ttk.Label(edit_frame, text="テキスト:").pack(anchor=tk.W, pady=(5, 0))
        self.text_entry = scrolledtext.ScrolledText(edit_frame, height=3, font=('TkDefaultFont', 11))
        self.text_entry.pack(fill=tk.X, pady=2)
        
        # 翻訳
        ttk.Label(edit_frame, text="翻訳:").pack(anchor=tk.W, pady=(5, 0))
        self.translated_entry = scrolledtext.ScrolledText(edit_frame, height=3, font=('TkDefaultFont', 11))
        self.translated_entry.pack(fill=tk.X, pady=2)
        
        # 適用ボタン
        ttk.Button(edit_frame, text="変更を適用", command=self.apply_changes).pack(pady=(5, 0))
        
        # AI処理ボタン
        ai_frame = ttk.Frame(edit_frame)
        ai_frame.pack(fill=tk.X, pady=(10, 0))
        
        ttk.Button(ai_frame, text="AI校正", command=self.ai_correct_selected).pack(side=tk.LEFT)
        ttk.Button(ai_frame, text="AI翻訳", command=self.ai_translate_selected).pack(side=tk.LEFT, padx=5)
        ttk.Button(ai_frame, text="全てAI処理", command=self.ai_process_all).pack(side=tk.LEFT)
        
        # 保存ボタン
        save_frame = ttk.Frame(parent)
        save_frame.pack(fill=tk.X, pady=(10, 0))
        
        ttk.Button(save_frame, text="SRT保存", command=self.save_srt).pack(side=tk.LEFT)
        ttk.Button(save_frame, text="翻訳SRT保存", command=self.save_translated_srt).pack(side=tk.LEFT, padx=5)
        ttk.Button(save_frame, text="SRT読込", command=self.open_srt).pack(side=tk.RIGHT)
    
    def _create_status_bar(self):
        """ステータスバーを作成"""
        self.status_var = tk.StringVar(value="準備完了")
        status_bar = ttk.Label(self.root, textvariable=self.status_var, relief=tk.SUNKEN, anchor=tk.W)
        status_bar.pack(side=tk.BOTTOM, fill=tk.X)
    
    # === イベントハンドラ ===
    
    def _on_canvas_click(self, event):
        """キャンバスクリック"""
        self.drag_start = (event.x, event.y)
        if self.drag_rect:
            self.canvas.delete(self.drag_rect)
            self.drag_rect = None
    
    def _on_canvas_drag(self, event):
        """キャンバスドラッグ"""
        if self.drag_start:
            if self.drag_rect:
                self.canvas.delete(self.drag_rect)
            x1, y1 = self.drag_start
            x2, y2 = event.x, event.y
            self.drag_rect = self.canvas.create_rectangle(x1, y1, x2, y2, outline='red', width=2)
    
    def _on_canvas_release(self, event):
        """キャンバスリリース"""
        if self.drag_start:
            x1, y1 = self.drag_start
            x2, y2 = event.x, event.y
            
            # 正規化座標に変換
            canvas_w = self.canvas.winfo_width()
            canvas_h = self.canvas.winfo_height()
            
            if canvas_w > 0 and canvas_h > 0:
                rx1 = min(x1, x2) / canvas_w
                ry1 = min(y1, y2) / canvas_h
                rx2 = max(x1, x2) / canvas_w
                ry2 = max(y1, y2) / canvas_h
                
                if rx2 - rx1 > 0.05 and ry2 - ry1 > 0.05:
                    self.region = {
                        'x': rx1,
                        'y': ry1,
                        'width': rx2 - rx1,
                        'height': ry2 - ry1
                    }
                    self.region_label.config(text=f"({rx1:.2f}, {ry1:.2f}) - ({rx2:.2f}, {ry2:.2f})")
            
            self.drag_start = None
    
    def _on_seek(self, value):
        """シーク操作"""
        if self.cap and self.cap.isOpened():
            total_frames = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
            frame_idx = int(float(value) / 100 * total_frames)
            self.cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            self._update_preview()
    
    def _on_subtitle_select(self, event):
        """字幕選択"""
        selection = self.subtitle_list.curselection()
        if selection:
            self.selected_index = selection[0]
            sub = self.subtitles[self.selected_index]
            
            self.start_time_var.set(self._format_time(sub.start_time))
            self.end_time_var.set(self._format_time(sub.end_time))
            
            self.text_entry.delete('1.0', tk.END)
            self.text_entry.insert('1.0', sub.text)
            
            self.translated_entry.delete('1.0', tk.END)
            self.translated_entry.insert('1.0', sub.translated)
            
            # 動画をその位置にシーク
            if self.cap and self.cap.isOpened():
                fps = self.cap.get(cv2.CAP_PROP_FPS)
                frame_idx = int(sub.start_time * fps)
                self.cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
                self._update_preview()
    
    def _reset_region(self):
        """領域をリセット"""
        self.region = None
        self.region_label.config(text="未設定（全画面）")
        if self.drag_rect:
            self.canvas.delete(self.drag_rect)
            self.drag_rect = None
    
    # === 動画操作 ===
    
    def open_video(self):
        """動画を開く"""
        path = filedialog.askopenfilename(
            title="動画を選択",
            filetypes=[
                ("動画ファイル", "*.mp4 *.avi *.mkv *.mov *.webm"),
                ("すべてのファイル", "*.*")
            ]
        )
        if path:
            self.video_path = path
            self.video_path_var.set(path)
            
            if self.cap:
                self.cap.release()
            
            self.cap = cv2.VideoCapture(path)
            if self.cap.isOpened():
                self._update_preview()
                self.status_var.set(f"動画を読み込みました: {Path(path).name}")
            else:
                messagebox.showerror("エラー", "動画を開けませんでした")
    
    def _update_preview(self):
        """プレビューを更新"""
        if self.cap and self.cap.isOpened():
            # Get time info first
            fps = self.cap.get(cv2.CAP_PROP_FPS)
            current_frame = int(self.cap.get(cv2.CAP_PROP_POS_FRAMES))
            total_frames = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
            current_time = current_frame / fps if fps > 0 else 0
            
            ret, frame = self.cap.read()
            if ret:
                # リサイズ
                canvas_w = self.canvas.winfo_width()
                canvas_h = self.canvas.winfo_height()
                
                if canvas_w > 1 and canvas_h > 1:
                    h, w = frame.shape[:2]
                    scale = min(canvas_w / w, canvas_h / h)
                    new_w = int(w * scale)
                    new_h = int(h * scale)
                    
                    frame = cv2.resize(frame, (new_w, new_h))
                    frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    
                    from PIL import Image, ImageTk, ImageDraw, ImageFont
                    import platform
                    import os
                    
                    img = Image.fromarray(frame)
                    
                    # 字幕の描画ロジック (プレビューがオンの場合のみ)
                    if self.subtitles and self.preview_var.get():
                        active_sub = None
                        for sub in self.subtitles:
                            if sub.start_time <= current_time <= sub.end_time:
                                active_sub = sub
                                break
                        
                        if active_sub:
                            draw = ImageDraw.Draw(img)
                            
                            # フォントの準備
                            font_path = None
                            system = platform.system()
                            if system == 'Darwin':
                                font_paths_to_check = [
                                    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
                                    "/System/Library/Fonts/Hiragino Sans GB.ttc",
                                    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
                                    "/Library/Fonts/Arial Unicode.ttf"
                                ]
                                for p in font_paths_to_check:
                                    if os.path.exists(p):
                                        font_path = p
                                        break
                            elif system == 'Windows':
                                font_path = "C:\\Windows\\Fonts\\msgothic.ttc"
                                
                            try:
                                if font_path and os.path.exists(font_path):
                                    # 動的なフォントサイズ（画面高さの約5%程度）
                                    font_size = max(16, int(new_h * 0.05))
                                    font = ImageFont.truetype(font_path, font_size)
                                else:
                                    font = ImageFont.load_default()
                            except:
                                font = ImageFont.load_default()
                            
                            # テキストの取得と改行処理
                            use_translated = (self.preview_lang_var.get() == "translated") and active_sub.translated
                            text = active_sub.translated if use_translated else active_sub.text
                            
                            max_chars = 0
                            if hasattr(self, 'root') and hasattr(self.root, 'master') and hasattr(self.root.master, 'settings'):
                                max_chars = self.root.master.settings.max_chars_per_line
                                
                            text = self._apply_line_breaks(text, max_chars)
                            
                            # テキストサイズの計算 (Pillow >= 8.0.0 では getbbox が推奨)
                            try:
                                bbox = draw.multiline_textbbox((0, 0), text, font=font)
                                text_w = bbox[2] - bbox[0]
                                text_h = bbox[3] - bbox[1]
                            except AttributeError:
                                # 古いPillowのフォールバック
                                text_w, text_h = draw.textsize(text, font=font)
                                
                            x_pos = (new_w - text_w) // 2
                            # 下から10%または最低20pxの位置
                            y_pad = max(20, int(new_h * 0.1))
                            y_pos = new_h - text_h - y_pad
                            
                            # 黒い縁取り（または半透明背景）の描画
                            # 縁取りを描画
                            outline_color = (0, 0, 0)
                            outline_width = max(1, font_size // 15) if font_path else 1
                            for adj_x in range(-outline_width, outline_width + 1):
                                for adj_y in range(-outline_width, outline_width + 1):
                                    if adj_x != 0 or adj_y != 0:
                                        draw.multiline_text((x_pos + adj_x, y_pos + adj_y), text, font=font, fill=outline_color, align='center')
                            
                            # 本体を描画
                            draw.multiline_text((x_pos, y_pos), text, font=font, fill=(255, 255, 255), align='center')
                    
                    self.photo = ImageTk.PhotoImage(img)
                    
                    self.canvas.delete('all')
                    x = (canvas_w - new_w) // 2
                    y = (canvas_h - new_h) // 2
                    self.canvas.create_image(x, y, anchor=tk.NW, image=self.photo)
                    
                    # 領域を再描画
                    if self.region:
                        rx1 = int(self.region['x'] * canvas_w)
                        ry1 = int(self.region['y'] * canvas_h)
                        rx2 = int((self.region['x'] + self.region['width']) * canvas_w)
                        ry2 = int((self.region['y'] + self.region['height']) * canvas_h)
                        self.canvas.create_rectangle(rx1, ry1, rx2, ry2, outline='red', width=2)
            
            # 時間表示を更新
            total_time = total_frames / fps if fps > 0 else 0
            
            self.time_label.config(text=f"{self._format_time(current_time)} / {self._format_time(total_time)}")
            self.seek_var.set(current_frame / total_frames * 100 if total_frames > 0 else 0)
    
    # === 字幕操作 ===
    
    def toggle_play(self):
        """再生/一時停止の切り替え"""
        if not self.cap or not self.cap.isOpened():
            return
            
        self.is_playing = not self.is_playing
        if self.is_playing:
            self.play_btn.config(text="⏸ 停止")
            self._play_loop()
        else:
            self.play_btn.config(text="▶ 再生")
            
    def _play_loop(self):
        """再生ループ"""
        if not self.is_playing or not self.cap or not self.cap.isOpened():
            self.is_playing = False
            self.play_btn.config(text="▶ 再生")
            return
            
        current_frame = int(self.cap.get(cv2.CAP_PROP_POS_FRAMES))
        total_frames = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
        
        if current_frame >= total_frames - 1:
            self.is_playing = False
            self.play_btn.config(text="▶ 再生")
            return
            
        # 次のフレームを読み込んでプレビュー更新
        self._update_preview()
        
        # FPSに基づいて待機時間を計算
        fps = self.cap.get(cv2.CAP_PROP_FPS)
        delay = int(1000 / fps) if fps > 0 else 33
        
        self.root.after(delay, self._play_loop)
    
    def extract_subtitles(self):
        """字幕を抽出"""
        if not self.video_path:
            messagebox.showwarning("警告", "動画を選択してください")
            return
        
        self.is_processing = True
        self.extract_btn.config(state=tk.DISABLED)
        self.stop_btn.config(state=tk.NORMAL)
        
        # 別スレッドで実行
        thread = threading.Thread(target=self._extract_thread)
        thread.daemon = True
        thread.start()
    
    def _extract_thread(self):
        """抽出スレッド"""
        try:
            from unified_ocr import UnifiedOCR, OCREngine, SubtitleRegion
            
            # エンジンを取得（meikiOCRのみ）
            engine = OCREngine.MEIKI_OCR
            
            # 領域を設定
            region = None
            if self.region:
                region = SubtitleRegion(
                    x=self.region['x'],
                    y=self.region['y'],
                    width=self.region['width'],
                    height=self.region['height']
                )
            
            # OCRを初期化
            ocr = UnifiedOCR(
                engine=engine,
                language='ja',
                enable_scroll_detection=self.scroll_detect_var.get()
            )
            
            def progress_callback(current, total):
                if not self.is_processing:
                    raise InterruptedError("処理が中止されました")
                progress = current / total * 100
                self.root.after(0, lambda: self.progress_var.set(progress))
                self.root.after(0, lambda: self.status_var.set(f"処理中... {current}/{total}"))
            
            # 抽出
            entries = ocr.extract_from_video(
                self.video_path,
                region=region,
                fps_sample=self.fps_var.get(),
                progress_callback=progress_callback
            )
            
            # 結果を変換
            self.subtitles = [
                Subtitle(
                    start_time=e.start_time,
                    end_time=e.end_time,
                    text=e.text,
                    translated=e.translated,
                    is_complete=e.is_complete
                )
                for e in entries
            ]
            
            # AI処理
            if (self.ai_correct_var.get() or self.translate_var.get()) and self.subtitles:
                self.root.after(0, lambda: self.status_var.set("AI処理中..."))
                self._ai_process_subtitles()
            
            # UIを更新
            self.root.after(0, self._update_subtitle_list)
            self.root.after(0, lambda: self.status_var.set(f"完了: {len(self.subtitles)}件の字幕を抽出"))
            
        except InterruptedError:
            self.root.after(0, lambda: self.status_var.set("処理を中止しました"))
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("エラー", str(e)))
            self.root.after(0, lambda: self.status_var.set("エラーが発生しました"))
        finally:
            self.is_processing = False
            self.root.after(0, lambda: self.extract_btn.config(state=tk.NORMAL))
            self.root.after(0, lambda: self.stop_btn.config(state=tk.DISABLED))
            self.root.after(0, lambda: self.progress_var.set(0))
    
    def _get_ollama_processor(self):
        """設定を反映したOllamaProcessorを生成"""
        from ollama_processor import OllamaProcessor
        model = 'gemma3:4b'
        custom_dict = ''
        if hasattr(self, 'root') and hasattr(self.root, 'master') and hasattr(self.root.master, 'settings'):
            model = self.root.master.settings.ollama_model
            custom_dict = self.root.master.settings.custom_dictionary
        return OllamaProcessor(model=model, custom_dictionary=custom_dict)
    
    def _ai_process_subtitles(self):
        """AI処理を実行"""
        try:
            processor = self._get_ollama_processor()
            if not processor.check_available():
                return
            
            for i, sub in enumerate(self.subtitles):
                if not self.is_processing:
                    break
                
                if self.ai_correct_var.get() and sub.text:
                    result = processor.correct_ocr(sub.text)
                    if result.success:
                        sub.text = result.processed
                
                if self.translate_var.get() and sub.text:
                    result = processor.translate_to_english(sub.text)
                    if result.success:
                        sub.translated = result.processed
        except Exception as e:
            print(f"AI処理エラー: {e}")
    
    def stop_extraction(self):
        """抽出を中止"""
        self.is_processing = False
    
    def _update_subtitle_list(self):
        """字幕リストを更新"""
        self.subtitle_list.delete(0, tk.END)
        for i, sub in enumerate(self.subtitles):
            time_str = f"{self._format_time(sub.start_time)} - {self._format_time(sub.end_time)}"
            text_preview = sub.text[:30] + "..." if len(sub.text) > 30 else sub.text
            status = "✓" if sub.is_complete else "△"
            self.subtitle_list.insert(tk.END, f"{status} {time_str} | {text_preview}")
    
    def add_subtitle(self):
        """字幕を追加"""
        new_sub = Subtitle(start_time=0, end_time=1, text="新しい字幕")
        self.subtitles.append(new_sub)
        self._update_subtitle_list()
        self.subtitle_list.selection_set(len(self.subtitles) - 1)
    
    def delete_subtitle(self):
        """字幕を削除"""
        if self.selected_index >= 0 and self.selected_index < len(self.subtitles):
            del self.subtitles[self.selected_index]
            self._update_subtitle_list()
            self.selected_index = -1
    
    def move_up(self):
        """字幕を上に移動"""
        if self.selected_index > 0:
            self.subtitles[self.selected_index], self.subtitles[self.selected_index - 1] = \
                self.subtitles[self.selected_index - 1], self.subtitles[self.selected_index]
            self._update_subtitle_list()
            self.subtitle_list.selection_set(self.selected_index - 1)
            self.selected_index -= 1
    
    def move_down(self):
        """字幕を下に移動"""
        if self.selected_index >= 0 and self.selected_index < len(self.subtitles) - 1:
            self.subtitles[self.selected_index], self.subtitles[self.selected_index + 1] = \
                self.subtitles[self.selected_index + 1], self.subtitles[self.selected_index]
            self._update_subtitle_list()
            self.subtitle_list.selection_set(self.selected_index + 1)
            self.selected_index += 1
    
    def apply_changes(self):
        """変更を適用"""
        if self.selected_index >= 0 and self.selected_index < len(self.subtitles):
            sub = self.subtitles[self.selected_index]
            sub.start_time = self._parse_time(self.start_time_var.get())
            sub.end_time = self._parse_time(self.end_time_var.get())
            sub.text = self.text_entry.get('1.0', tk.END).strip()
            sub.translated = self.translated_entry.get('1.0', tk.END).strip()
            self._update_subtitle_list()
            self.status_var.set("変更を適用しました")
    
    # === AI処理 ===
    
    def ai_correct_selected(self):
        """選択した字幕をAI校正"""
        if self.selected_index < 0:
            return
        
        try:
            processor = self._get_ollama_processor()
            
            if not processor.check_available():
                messagebox.showwarning("警告", "Ollamaが起動していません。'ollama serve'を実行してください。")
                return
            
            sub = self.subtitles[self.selected_index]
            result = processor.correct_ocr(sub.text)
            
            if result.success:
                self.text_entry.delete('1.0', tk.END)
                self.text_entry.insert('1.0', result.processed)
                self.status_var.set("AI校正完了")
            else:
                messagebox.showerror("エラー", result.error)
        except Exception as e:
            messagebox.showerror("エラー", str(e))
    
    def ai_translate_selected(self):
        """選択した字幕をAI翻訳"""
        if self.selected_index < 0:
            return
        
        try:
            processor = self._get_ollama_processor()
            
            if not processor.check_available():
                messagebox.showwarning("警告", "Ollamaが起動していません。'ollama serve'を実行してください。")
                return
            
            text = self.text_entry.get('1.0', tk.END).strip()
            result = processor.translate_to_english(text)
            
            if result.success:
                self.translated_entry.delete('1.0', tk.END)
                self.translated_entry.insert('1.0', result.processed)
                self.status_var.set("AI翻訳完了")
            else:
                messagebox.showerror("エラー", result.error)
        except Exception as e:
            messagebox.showerror("エラー", str(e))
    
    def ai_process_all(self):
        """全字幕をAI処理"""
        if not self.subtitles:
            return
        
        if not messagebox.askyesno("確認", f"{len(self.subtitles)}件の字幕をAI処理しますか？\n（時間がかかる場合があります）"):
            return
        
        self.is_processing = True
        thread = threading.Thread(target=self._ai_process_all_thread)
        thread.daemon = True
        thread.start()
    
    def _ai_process_all_thread(self):
        """全字幕AI処理スレッド"""
        try:
            processor = self._get_ollama_processor()
            
            if not processor.check_available():
                self.root.after(0, lambda: messagebox.showwarning("警告", "Ollamaが起動していません"))
                return
            
            total = len(self.subtitles)
            for i, sub in enumerate(self.subtitles):
                if not self.is_processing:
                    break
                
                self.root.after(0, lambda i=i: self.status_var.set(f"AI処理中... {i+1}/{total}"))
                self.root.after(0, lambda i=i: self.progress_var.set((i+1)/total*100))
                
                # 校正
                result = processor.correct_ocr(sub.text)
                if result.success:
                    sub.text = result.processed
                
                # 翻訳
                result = processor.translate_to_english(sub.text)
                if result.success:
                    sub.translated = result.processed
            
            self.root.after(0, self._update_subtitle_list)
            self.root.after(0, lambda: self.status_var.set("AI処理完了"))
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("エラー", str(e)))
        finally:
            self.is_processing = False
            self.root.after(0, lambda: self.progress_var.set(0))
    
    # === SRT操作 ===
    
    def open_srt(self):
        """SRTを開く"""
        path = filedialog.askopenfilename(
            title="SRTを選択",
            filetypes=[("SRTファイル", "*.srt"), ("すべてのファイル", "*.*")]
        )
        if path:
            self._load_srt(path)
    
    def _load_srt(self, path: str):
        """SRTを読み込み"""
        try:
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            self.subtitles = []
            blocks = content.strip().split('\n\n')
            
            for block in blocks:
                lines = block.strip().split('\n')
                if len(lines) >= 3:
                    time_line = lines[1]
                    text = '\n'.join(lines[2:])
                    
                    start, end = time_line.split(' --> ')
                    start_time = self._parse_srt_time(start)
                    end_time = self._parse_srt_time(end)
                    
                    self.subtitles.append(Subtitle(
                        start_time=start_time,
                        end_time=end_time,
                        text=text
                    ))
            
            self._update_subtitle_list()
            self.status_var.set(f"SRTを読み込みました: {len(self.subtitles)}件")
        except Exception as e:
            messagebox.showerror("エラー", f"SRTの読み込みに失敗: {e}")
    
    def save_srt(self):
        """SRTを保存"""
        if not self.subtitles:
            messagebox.showwarning("警告", "保存する字幕がありません")
            return
        
        path = filedialog.asksaveasfilename(
            title="SRTを保存",
            defaultextension=".srt",
            filetypes=[("SRTファイル", "*.srt")]
        )
        if path:
            self._save_srt(path, use_translated=False)
    
    def save_translated_srt(self):
        """翻訳SRTを保存"""
        if not self.subtitles:
            messagebox.showwarning("警告", "保存する字幕がありません")
            return
        
        path = filedialog.asksaveasfilename(
            title="翻訳SRTを保存",
            defaultextension=".srt",
            filetypes=[("SRTファイル", "*.srt")]
        )
        if path:
            self._save_srt(path, use_translated=True)
    
    def _apply_line_breaks(self, text: str, max_chars: int) -> str:
        """指定文字数で改行を挿入する（英語は単語境界で折り返す）"""
        if max_chars <= 0 or not text:
            return text
            
        import unicodedata
        
        def is_ascii_text(t):
            """ASCIIベースのテキストか判定"""
            ascii_count = sum(1 for c in t if ord(c) < 128)
            return ascii_count > len(t) * 0.7
        
        # 既に改行がある場合は、段落ごとに処理
        paragraphs = text.split('\n')
        result_lines = []
        
        for p in paragraphs:
            if not p.strip():
                result_lines.append(p)
                continue
                
            if is_ascii_text(p):
                # 英語: 単語境界で折り返す
                words = p.split(' ')
                current_line = ""
                for word in words:
                    test_line = f"{current_line} {word}".strip() if current_line else word
                    if len(test_line) > max_chars and current_line:
                        result_lines.append(current_line)
                        current_line = word
                    else:
                        current_line = test_line
                if current_line:
                    result_lines.append(current_line)
            else:
                # 日本語: 文字幅で折り返す
                current_line = ""
                current_length = 0
                
                for char in p:
                    char_width = 2 if unicodedata.east_asian_width(char) in 'FWA' else 1
                    
                    if current_length + char_width > max_chars * 2:
                        result_lines.append(current_line)
                        current_line = char
                        current_length = char_width
                    else:
                        current_line += char
                        current_length += char_width
                
                if current_line:
                    result_lines.append(current_line)
                
        return '\n'.join(result_lines)

    def _save_srt(self, path: str, use_translated: bool = False):
        """SRTを保存"""
        try:
            # main_app側から渡された設定を取得する対応
            max_chars = 0
            if hasattr(self, 'root') and hasattr(self.root, 'master') and hasattr(self.root.master, 'settings'):
                max_chars = self.root.master.settings.max_chars_per_line
                
            with open(path, 'w', encoding='utf-8') as f:
                for i, sub in enumerate(self.subtitles, 1):
                    text = sub.translated if use_translated and sub.translated else sub.text
                    text = self._apply_line_breaks(text, max_chars)
                    
                    f.write(f"{i}\n")
                    f.write(f"{self._format_srt_time(sub.start_time)} --> {self._format_srt_time(sub.end_time)}\n")
                    f.write(f"{text}\n\n")
            
            self.status_var.set(f"SRTを保存しました: {path}")
        except Exception as e:
            messagebox.showerror("エラー", f"保存に失敗: {e}")
            
    # === ユーティリティ ===
    
    def _format_time(self, seconds: float) -> str:
        """秒を MM:SS 形式に変換"""
        m = int(seconds // 60)
        s = int(seconds % 60)
        return f"{m:02d}:{s:02d}"
    
    def _parse_time(self, time_str: str) -> float:
        """MM:SS 形式を秒に変換"""
        try:
            parts = time_str.split(':')
            if len(parts) == 2:
                return int(parts[0]) * 60 + float(parts[1])
            return float(time_str)
        except:
            return 0.0
    
    def _format_srt_time(self, seconds: float) -> str:
        """秒を SRT時間形式に変換"""
        h = int(seconds // 3600)
        m = int((seconds % 3600) // 60)
        s = int(seconds % 60)
        ms = int((seconds % 1) * 1000)
        return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"
    
    def _parse_srt_time(self, time_str: str) -> float:
        """SRT時間形式を秒に変換"""
        time_str = time_str.strip().replace(',', '.')
        parts = time_str.split(':')
        if len(parts) == 3:
            h, m, s = parts
            return int(h) * 3600 + int(m) * 60 + float(s)
        return 0.0
    
    def show_help(self):
        """ヘルプを表示"""
        help_text = """
字幕抽出・編集ツール v2.0

【使い方】
1. 「参照...」で動画を選択
2. プレビュー上でマウスドラッグして字幕領域を選択（オプション）
3. OCRエンジンを選択
4. 「字幕を抽出」をクリック
5. 字幕リストで選択して編集
6. 「SRT保存」で保存

【OCRエンジン】
- EasyOCR: 無料、汎用的
- manga-ocr: 無料、日本語特化
- GPT-4 Vision: 最高精度（APIキー必要）
- Llama 3.2 Vision: ローカルAI（Ollama必要、8GB RAM）
- LLaVA: ローカルAI（Ollama必要、6GB RAM）
- Moondream: 軽量AI（Ollama必要、4GB RAM）

【AI機能】
- AI校正: OCRの誤認識を修正
- AI翻訳: 日本語→英語翻訳

※ AI機能を使用するには、Ollamaを起動してください:
  ollama serve
"""
        messagebox.showinfo("ヘルプ", help_text)
        
    def open_settings(self):
        """詳細設定ダイアログを開く"""
        try:
            from main_app import SettingsDialog, AppSettings
            
            # 親ウィンドウ(MainApplicationなど)が存在し、設定を持っていればそれを使う
            current_settings = None
            if hasattr(self, 'root') and hasattr(self.root, 'master') and hasattr(self.root.master, 'settings'):
                current_settings = self.root.master.settings
            else:
                current_settings = AppSettings()
                
            dialog = SettingsDialog(self.root, current_settings)
            
            if dialog.result:
                # 設定が更新された場合、適用する
                if hasattr(self, 'root') and hasattr(self.root, 'master') and hasattr(self.root.master, 'settings'):
                    self.root.master.settings = dialog.result
                    if hasattr(self.root.master, 'settings_path'):
                        dialog.result.save(self.root.master.settings_path)
                else:
                    # 単独実行時はJSONに保存
                    import os
                    settings_path = os.path.join(os.path.dirname(__file__), "settings.json")
                    dialog.result.save(settings_path)
                    
                messagebox.showinfo("設定", "設定を保存しました。一部の設定は次回保存時や処理開始時に反映されます。")
        except Exception as e:
            messagebox.showerror("エラー", f"設定画面を開けませんでした: {e}")

def main():
    try:
        from main_app import MainApplication

        app = MainApplication()
        app.mainloop()
    except Exception:
        root = tk.Tk()
        app = SubtitleEditorGUI(root)
        root.mainloop()


if __name__ == '__main__':
    main()
