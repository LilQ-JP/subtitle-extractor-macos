"""
字幕抽出・編集ツール
ゲーム動画から字幕を自動抽出し、編集・翻訳・SRT出力を行うデスクトップアプリケーション

対応OCR: meikiOCR（日本語ゲーム字幕特化）
"""

import os
import sys
import re
import json
import threading
import subprocess
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from fractions import Fraction
from typing import List, Optional, Callable, Tuple

import cv2
import numpy as np
from PIL import Image, ImageTk, ImageDraw, ImageFont
import tkinter as tk
import tkinter.font as tkfont
from tkinter import ttk, filedialog, messagebox, simpledialog

from ocr_engines import get_engine, list_engines, ENGINE_INFO
from scroll_detector import ScrollSubtitleDetector


@dataclass
class Subtitle:
    """字幕データ"""
    index: int
    start_time: float
    end_time: float
    text: str
    translated: str = ""
    confidence: float = 1.0


@dataclass
class AppSettings:
    """アプリケーション設定"""
    fps_sample: float = 2.0
    detect_scroll: bool = True
    auto_translate: bool = False
    translate_source: str = "ja"
    translate_target: str = "en"
    subtitle_font_size: int = 24
    subtitle_bg_opacity: int = 180
    min_subtitle_duration: float = 0.5
    max_subtitle_duration: float = 10.0
    similarity_threshold: float = 0.6
    stability_frames: int = 2
    ollama_model: str = "gemma3:4b"
    subtitle_wrap_width_ratio: float = 0.68
    max_chars_per_line: int = 20
    custom_dictionary: str = ""  # カスタム辞書（例: 原神=Genshin\nナヒダ=Nahida）
    
    def save(self, path: str):
        """設定を保存"""
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(self.__dict__, f, indent=2, ensure_ascii=False)
    
    @classmethod
    def load(cls, path: str) -> 'AppSettings':
        """設定を読み込み"""
        try:
            with open(path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                return cls(**data)
        except:
            return cls()


def format_time(seconds: float) -> str:
    """秒をSRT形式の時間文字列に変換"""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = seconds % 60
    return f"{h:02d}:{m:02d}:{s:06.3f}".replace('.', ',')


def parse_time(time_str: str) -> float:
    """SRT形式の時間文字列を秒に変換"""
    time_str = time_str.replace(',', '.')
    parts = time_str.split(':')
    if len(parts) == 3:
        h, m, s = parts
        return int(h) * 3600 + int(m) * 60 + float(s)
    return 0.0


def load_subtitle_font(font_size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    """字幕描画用フォントを読み込む"""
    candidates: List[str] = []
    if sys.platform == "darwin":
        candidates = [
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            "/System/Library/Fonts/AppleSDGothicNeo.ttc",
            "/Library/Fonts/Arial Unicode.ttf",
        ]
    elif sys.platform == "win32":
        candidates = ["msgothic.ttc", "C:\\Windows\\Fonts\\msgothic.ttc"]
    else:
        candidates = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]

    for candidate in candidates:
        try:
            if candidate == "msgothic.ttc" or os.path.exists(candidate):
                return ImageFont.truetype(candidate, font_size)
        except Exception:
            continue

    return ImageFont.load_default()


def measure_text_width(text: str, font: ImageFont.FreeTypeFont | ImageFont.ImageFont) -> float:
    """テキストの描画幅を取得"""
    if not text:
        return 0.0

    if hasattr(font, "getlength"):
        return float(font.getlength(text))

    bbox = font.getbbox(text)
    return float(bbox[2] - bbox[0])


def wrap_subtitle_text(
    text: str,
    max_width_px: float,
    font: ImageFont.FreeTypeFont | ImageFont.ImageFont
) -> str:
    """字幕テキストを描画幅ベースで自動改行"""
    normalized_text = text.replace('\r\n', '\n').replace('\r', '\n').strip()
    if not normalized_text or max_width_px <= 0:
        return normalized_text

    def split_long_token(token: str) -> List[str]:
        chunks: List[str] = []
        current = ""
        for char in token:
            candidate = current + char
            if current and measure_text_width(candidate, font) > max_width_px:
                chunks.append(current)
                current = char
            else:
                current = candidate
        if current:
            chunks.append(current)
        return chunks

    def is_space_separated(line: str) -> bool:
        ascii_chars = sum(1 for char in line if ord(char) < 128)
        return " " in line and ascii_chars >= len(line) * 0.45

    wrapped_lines: List[str] = []

    for raw_line in normalized_text.split('\n'):
        line = raw_line.strip()
        if not line:
            if wrapped_lines and wrapped_lines[-1] != "":
                wrapped_lines.append("")
            continue

        if measure_text_width(line, font) <= max_width_px:
            wrapped_lines.append(line)
            continue

        if is_space_separated(line):
            words = line.split()
            current_line = ""

            for word in words:
                if measure_text_width(word, font) > max_width_px:
                    if current_line:
                        wrapped_lines.append(current_line)
                        current_line = ""
                    split_words = split_long_token(word)
                    wrapped_lines.extend(split_words[:-1])
                    current_line = split_words[-1]
                    continue

                candidate = word if not current_line else f"{current_line} {word}"
                if current_line and measure_text_width(candidate, font) > max_width_px:
                    wrapped_lines.append(current_line)
                    current_line = word
                else:
                    current_line = candidate

            if current_line:
                wrapped_lines.append(current_line)
            continue

        current_line = ""
        for char in line:
            candidate = current_line + char
            if current_line and measure_text_width(candidate, font) > max_width_px:
                wrapped_lines.append(current_line)
                current_line = char
            else:
                current_line = candidate

        if current_line:
            wrapped_lines.append(current_line)

    return '\n'.join(wrapped_lines).strip()


def seconds_to_fcpx_time(seconds: float, fps: float) -> str:
    """秒をFCPXML用の時間文字列に変換"""
    safe_seconds = max(0.0, seconds)
    if safe_seconds == 0:
        return "0s"

    safe_fps = fps if fps and fps > 0 else 30.0
    fraction = Fraction(safe_seconds).limit_denominator(int(safe_fps * 1000))
    return f"{fraction.numerator}/{fraction.denominator}s"


def normalize_subtitle_timings(
    subtitles: List[Subtitle],
    min_duration: float,
    max_duration: float,
    timeline_end: Optional[float] = None
) -> List[Subtitle]:
    """字幕時間を正規化して重なりを防ぐ"""
    if not subtitles:
        return subtitles

    epsilon = 0.01
    subtitles.sort(key=lambda sub: (sub.start_time, sub.end_time, sub.index))
    previous_end = 0.0

    for i, sub in enumerate(subtitles):
        sub.start_time = max(0.0, float(sub.start_time), previous_end if i > 0 else 0.0)
        if timeline_end is not None:
            sub.start_time = min(sub.start_time, max(0.0, float(timeline_end) - epsilon))
        sub.end_time = max(sub.start_time + epsilon, float(sub.end_time))

        if max_duration > 0:
            sub.end_time = min(sub.end_time, sub.start_time + max_duration)

        next_start: Optional[float] = None
        if i + 1 < len(subtitles):
            next_start = max(0.0, float(subtitles[i + 1].start_time))
            next_start = max(next_start, sub.start_time + epsilon)
        elif timeline_end is not None:
            next_start = max(sub.start_time + epsilon, float(timeline_end))

        if min_duration > 0:
            desired_end = sub.start_time + min_duration
            if next_start is not None:
                desired_end = min(desired_end, next_start - epsilon)
            sub.end_time = max(sub.end_time, max(sub.start_time + epsilon, desired_end))

        if next_start is not None:
            sub.end_time = min(sub.end_time, max(sub.start_time + epsilon, next_start - epsilon))

        if timeline_end is not None:
            sub.end_time = min(sub.end_time, float(timeline_end))

        if sub.end_time <= sub.start_time:
            sub.end_time = sub.start_time + epsilon
            if timeline_end is not None:
                sub.end_time = max(sub.start_time + epsilon, min(sub.end_time, float(timeline_end)))

        previous_end = sub.end_time
        sub.index = i + 1

    return subtitles


class VideoPlayer:
    """動画プレーヤー"""
    
    def __init__(self, canvas: tk.Canvas, on_time_change: Callable = None):
        self.canvas = canvas
        self.on_time_change = on_time_change
        
        self.cap: Optional[cv2.VideoCapture] = None
        self.video_path: str = ""
        self.total_frames: int = 0
        self.fps: float = 30.0
        self.duration: float = 0.0
        self.current_frame: int = 0
        self.current_time: float = 0.0
        
        self.is_playing: bool = False
        self._after_id: Optional[str] = None  # afterのID（キャンセル用）
        
        self.subtitles: List[Subtitle] = []
        self.show_subtitles: bool = True
        self.show_translated: bool = False
        self.subtitle_font_size: int = 24
        self.subtitle_bg_opacity: int = 180
        self.subtitle_wrap_width_ratio: float = 0.68
        
        self.photo_image: Optional[ImageTk.PhotoImage] = None
        
        self.selection_rect = None
        self.selection_start = None
        self.subtitle_region = None
        
        self.audio_process = None
    
    def load_video(self, path: str) -> bool:
        """動画を読み込む"""
        self.stop()
        
        if self.cap:
            self.cap.release()
        
        self.cap = cv2.VideoCapture(path)
        if not self.cap.isOpened():
            return False
        
        self.video_path = path
        self.total_frames = int(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
        self.fps = self.cap.get(cv2.CAP_PROP_FPS) or 30.0
        self.duration = self.total_frames / self.fps
        self.current_frame = 0
        self.current_time = 0.0
        
        self.show_frame(0)
        return True
    
    def show_frame(self, frame_num: int, fast_mode: bool = False):
        """指定フレームを表示
        
        Args:
            frame_num: フレーム番号
            fast_mode: 高速モード（再生中は軽量なリサイズを使用）
        """
        if not self.cap:
            return
        
        frame_num = max(0, min(frame_num, self.total_frames - 1))
        
        self.cap.set(cv2.CAP_PROP_POS_FRAMES, frame_num)
        ret, frame = self.cap.read()
        
        if not ret:
            return
        
        self.current_frame = frame_num
        self.current_time = frame_num / self.fps
        
        canvas_width = self.canvas.winfo_width()
        canvas_height = self.canvas.winfo_height()
        
        if canvas_width > 1 and canvas_height > 1:
            ratio = min(canvas_width / frame.shape[1], canvas_height / frame.shape[0])
            new_width = int(frame.shape[1] * ratio)
            new_height = int(frame.shape[0] * ratio)
            
            # 高速モードではOpenCVでリサイズ（高速）
            if fast_mode:
                frame = cv2.resize(frame, (new_width, new_height), interpolation=cv2.INTER_LINEAR)
            else:
                frame = cv2.resize(frame, (new_width, new_height), interpolation=cv2.INTER_AREA)
        
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(frame_rgb)
        
        if self.subtitle_region:
            image = self._draw_region(image)
        
        if self.show_subtitles:
            image = self._overlay_subtitle(image)
        
        self.photo_image = ImageTk.PhotoImage(image)
        
        self.canvas.delete("all")
        x = canvas_width // 2
        y = canvas_height // 2
        self.canvas.create_image(x, y, image=self.photo_image, anchor=tk.CENTER)
        
        if self.on_time_change:
            self.on_time_change(self.current_time)
    
    def _overlay_subtitle(self, image: Image.Image) -> Image.Image:
        """字幕をオーバーレイ"""
        current_sub = self._get_current_subtitle()
        if not current_sub:
            return image
        
        draw = ImageDraw.Draw(image)
        
        font = load_subtitle_font(self.subtitle_font_size)
        
        if self.show_translated and current_sub.translated:
            text = current_sub.translated
        else:
            text = current_sub.text

        max_width = image.width * max(0.3, min(getattr(self, "subtitle_wrap_width_ratio", 0.68), 0.95))
        text = wrap_subtitle_text(text, max_width, font)

        bbox = draw.multiline_textbbox((0, 0), text, font=font, align="center", spacing=6)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
        
        x = (image.width - text_width) // 2
        y = image.height - text_height - 40
        
        padding = 10
        draw.rectangle(
            [x - padding, y - padding, x + text_width + padding, y + text_height + padding],
            fill=(0, 0, 0, self.subtitle_bg_opacity)
        )

        draw.multiline_text((x, y), text, font=font, fill=(255, 255, 255), align="center", spacing=6)
        
        return image
    
    def _draw_region(self, image: Image.Image) -> Image.Image:
        """字幕領域を描画"""
        if not self.subtitle_region:
            return image
        
        draw = ImageDraw.Draw(image)
        x, y, w, h = self.subtitle_region
        
        x1 = int(x * image.width)
        y1 = int(y * image.height)
        x2 = int((x + w) * image.width)
        y2 = int((y + h) * image.height)
        
        draw.rectangle([x1, y1, x2, y2], outline="#00ff00", width=2)
        
        return image
    
    def _get_current_subtitle(self) -> Optional[Subtitle]:
        """現在時刻の字幕を取得"""
        for sub in self.subtitles:
            if sub.start_time <= self.current_time <= sub.end_time:
                return sub
        return None
    
    def play(self):
        """再生開始"""
        if not self.cap or self.is_playing:
            return
        
        self.is_playing = True
        self._schedule_next_frame()
        self._start_audio()
    
    def _schedule_next_frame(self):
        """次のフレームをスケジュール（メインスレッドで実行）"""
        if not self.is_playing or not self.cap:
            return
        
        if self.current_frame >= self.total_frames - 1:
            self.is_playing = False
            self._stop_audio()
            return
        
        # 次のフレームを表示
        next_frame = self.current_frame + 1
        self.show_frame(next_frame, fast_mode=True)
        
        # 次のフレームをスケジュール（33ms ≈ 30fps）
        frame_delay = int(1000 / min(self.fps, 30))
        self._after_id = self.canvas.after(frame_delay, self._schedule_next_frame)
    
    def _start_audio(self):
        """音声再生を開始"""
        self._stop_audio()
        
        try:
            self.audio_process = subprocess.Popen(
                [
                    "ffplay", "-nodisp", "-autoexit",
                    "-ss", str(self.current_time),
                    "-i", self.video_path
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
        except:
            pass
    
    def _stop_audio(self):
        """音声再生を停止"""
        if self.audio_process:
            self.audio_process.terminate()
            self.audio_process = None
    
    def pause(self):
        """一時停止"""
        self.is_playing = False
        # スケジュールされたフレーム更新をキャンセル
        if self._after_id:
            try:
                self.canvas.after_cancel(self._after_id)
            except:
                pass
            self._after_id = None
        self._stop_audio()
    
    def stop(self):
        """停止"""
        self.is_playing = False
        # スケジュールされたフレーム更新をキャンセル
        if self._after_id:
            try:
                self.canvas.after_cancel(self._after_id)
            except:
                pass
            self._after_id = None
        self._stop_audio()
        self.current_frame = 0
        self.current_time = 0.0
    
    def seek(self, time_sec: float):
        """指定時刻にシーク"""
        if not self.cap:
            return
        
        frame_num = int(time_sec * self.fps)
        self.show_frame(frame_num)
    
    def set_subtitles(self, subtitles: List[Subtitle]):
        """字幕を設定"""
        self.subtitles = subtitles
    
    def set_subtitle_region(self, region: Optional[tuple]):
        """字幕領域を設定"""
        self.subtitle_region = region
        self.show_frame(self.current_frame)
    
    def release(self):
        """リソースを解放"""
        self.stop()
        if self.cap:
            self.cap.release()
            self.cap = None


class SubtitleExtractor:
    """字幕抽出エンジン"""
    
    GARBAGE_PATTERNS = [
        r'^[A-Z0-9]{2,6}$',
        r'^(LOAD|SAVE|MENU|QUIT|EXIT|START|STOP|PLAY|PAUSE|NEXT|BACK|OK|CANCEL|YES|NO|AUTO|SKIP|LOG|CONFIG|OPTION|SYSTEM|SYST|CAVT|OLOAD)!?$',
        r'^\d{1,5}$',
        r'^[A-Za-z0-9\-\_\.]{1,8}$',
        r'^0[A-Za-z]+$',
        r'^[A-Z]+\d+$',
    ]
    
    MIN_VALID_LENGTH = 3
    
    def __init__(self, settings: AppSettings):
        self.settings = settings
        self.engine = get_engine("meikiocr", "")
        self.is_cancelled = False
        self.scroll_detector = ScrollSubtitleDetector(
            similarity_threshold=settings.similarity_threshold,
            stability_frames=settings.stability_frames
        )
        
        self.garbage_regexes = [re.compile(p, re.IGNORECASE) for p in self.GARBAGE_PATTERNS]
    
    def _is_garbage_text(self, text: str) -> bool:
        """ゴミ文字かどうかを判定"""
        if not text:
            return True
        
        text = text.strip()
        
        if len(text) < self.MIN_VALID_LENGTH:
            return True
        
        for regex in self.garbage_regexes:
            if regex.match(text):
                return True
        
        has_japanese = bool(re.search(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]', text))
        
        if not has_japanese and len(text) < 10:
            if re.match(r'^[A-Za-z0-9\s\-\_\.\!\?]+$', text):
                return True
        
        return False
    
    def _clean_text(self, text: str) -> str:
        """テキストをクリーンアップ"""
        if not text:
            return ""
        
        lines = text.split('\n')
        clean_lines = []
        
        for line in lines:
            line = line.strip()
            if line and not self._is_garbage_text(line):
                clean_lines.append(line)
        
        return '\n'.join(clean_lines)
    
    def extract(
        self,
        video_path: str,
        region: Optional[tuple] = None,
        progress_callback: Callable = None,
        frame_callback: Callable = None
    ) -> List[Subtitle]:
        """動画から字幕を抽出"""
        
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise ValueError("動画を開けません")
        
        video_fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        duration = total_frames / video_fps
        
        frame_interval = int(video_fps / self.settings.fps_sample)
        
        frame_texts = []
        
        frame_num = 0
        processed = 0
        total_to_process = total_frames // frame_interval
        
        while frame_num < total_frames:
            if self.is_cancelled:
                break
            
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_num)
            ret, frame = cap.read()
            
            if not ret:
                frame_num += frame_interval
                continue
            
            if region:
                h, w = frame.shape[:2]
                x, y, rw, rh = region
                x1 = int(x * w)
                y1 = int(y * h)
                x2 = int((x + rw) * w)
                y2 = int((y + rh) * h)
                frame = frame[y1:y2, x1:x2]
            
            result = self.engine.recognize(frame)
            text = result.text.strip()
            
            text = self._clean_text(text)
            
            current_time = frame_num / video_fps
            
            frame_texts.append((current_time, text))
            
            processed += 1
            if progress_callback:
                progress_callback(processed / total_to_process * 100)
            
            if frame_callback:
                frame_callback(frame_num, text)
            
            frame_num += frame_interval
        
        cap.release()
        
        if self.settings.detect_scroll:
            result = self.scroll_detector.process_frames(frame_texts)
            subtitles = []
            for i, candidate in enumerate(result.subtitles):
                clean_text = self._clean_text(candidate.text)
                if clean_text:
                    sub = Subtitle(
                        index=len(subtitles) + 1,
                        start_time=candidate.start_time,
                        end_time=candidate.end_time,
                        text=clean_text,
                        confidence=candidate.confidence
                    )
                    
                    # 字幕の長さを制限
                    if sub.end_time - sub.start_time < self.settings.min_subtitle_duration:
                        sub.end_time = sub.start_time + self.settings.min_subtitle_duration
                    elif sub.end_time - sub.start_time > self.settings.max_subtitle_duration:
                        sub.end_time = sub.start_time + self.settings.max_subtitle_duration
                    
                    subtitles.append(sub)
            return subtitles
        else:
            return self._process_without_scroll_detection(frame_texts, duration)
    
    def _process_without_scroll_detection(
        self,
        frame_texts: List[tuple],
        duration: float
    ) -> List[Subtitle]:
        """スクロール検出なしで字幕を生成"""
        subtitles = []
        prev_text = ""
        current_sub_start = None
        
        for current_time, text in frame_texts:
            if text != prev_text:
                if prev_text and current_sub_start is not None:
                    subtitles.append(Subtitle(
                        index=len(subtitles) + 1,
                        start_time=current_sub_start,
                        end_time=current_time,
                        text=prev_text
                    ))
                
                if text:
                    current_sub_start = current_time
                else:
                    current_sub_start = None
                
                prev_text = text
        
        if prev_text and current_sub_start is not None:
            subtitles.append(Subtitle(
                index=len(subtitles) + 1,
                start_time=current_sub_start,
                end_time=duration,
                text=prev_text
            ))
        
        return subtitles
    
    def cancel(self):
        """抽出をキャンセル"""
        self.is_cancelled = True


class SettingsDialog(tk.Toplevel):
    """設定ダイアログ"""
    
    def __init__(self, parent, settings: AppSettings):
        super().__init__(parent)
        self.parent = parent
        
        self.title("詳細設定")
        self.geometry("500x600")
        self.resizable(False, False)
        self.transient(parent)
        self.grab_set()
        self.configure(bg=getattr(parent, "colors", {}).get("window", "#eef1f5"))
        
        self.settings = settings
        self.result = None
        
        self._create_ui()
        
        # 中央に配置
        self.update_idletasks()
        x = parent.winfo_x() + (parent.winfo_width() - self.winfo_width()) // 2
        y = parent.winfo_y() + (parent.winfo_height() - self.winfo_height()) // 2
        self.geometry(f"+{x}+{y}")
    
    def _create_ui(self):
        """UIを構築"""
        container = ttk.Frame(self, style="App.TFrame", padding=(16, 16, 16, 12))
        container.pack(fill=tk.BOTH, expand=True)

        notebook = ttk.Notebook(container, style="App.TNotebook")
        notebook.pack(fill=tk.BOTH, expand=True)
        
        # 抽出設定タブ
        extract_frame = ttk.Frame(notebook, style="Card.TFrame", padding=20)
        notebook.add(extract_frame, text="抽出設定")
        self._create_extract_settings(extract_frame)
        
        # 翻訳設定タブ
        translate_frame = ttk.Frame(notebook, style="Card.TFrame", padding=20)
        notebook.add(translate_frame, text="翻訳設定")
        self._create_translate_settings(translate_frame)
        
        # 表示設定タブ
        display_frame = ttk.Frame(notebook, style="Card.TFrame", padding=20)
        notebook.add(display_frame, text="表示設定")
        self._create_display_settings(display_frame)
        
        # ボタン
        btn_frame = ttk.Frame(container, style="App.TFrame")
        btn_frame.pack(fill=tk.X, pady=(12, 0))
        
        ttk.Button(btn_frame, text="OK", command=self._on_ok, width=10, style="Primary.TButton").pack(side=tk.RIGHT, padx=5)
        ttk.Button(btn_frame, text="キャンセル", command=self._on_cancel, width=10, style="Subtle.TButton").pack(side=tk.RIGHT)
        ttk.Button(btn_frame, text="デフォルトに戻す", command=self._on_reset, style="Toolbar.TButton").pack(side=tk.LEFT)
    
    def _create_extract_settings(self, parent):
        """抽出設定を作成"""
        # サンプリングFPS
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="サンプリングFPS:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.fps_var = tk.StringVar(value=str(self.settings.fps_sample))
        ttk.Entry(row, textvariable=self.fps_var, width=10).pack(side=tk.LEFT)
        ttk.Label(row, text="（1.0〜10.0、高いほど精度↑）").pack(side=tk.LEFT, padx=10)
        
        # スクロール検出
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        self.scroll_var = tk.BooleanVar(value=self.settings.detect_scroll)
        ttk.Checkbutton(row, text="スクロール字幕検出を有効にする", variable=self.scroll_var).pack(anchor=tk.W)
        
        # 類似度閾値
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="類似度閾値:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.similarity_var = tk.StringVar(value=str(self.settings.similarity_threshold))
        ttk.Entry(row, textvariable=self.similarity_var, width=10).pack(side=tk.LEFT)
        ttk.Label(row, text="（0.0〜1.0）").pack(side=tk.LEFT, padx=10)
        
        # 安定フレーム数
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="安定フレーム数:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.stability_var = tk.StringVar(value=str(self.settings.stability_frames))
        ttk.Entry(row, textvariable=self.stability_var, width=10).pack(side=tk.LEFT)
        ttk.Label(row, text="（1〜10）").pack(side=tk.LEFT, padx=10)
        
        # 最小字幕長
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="最小字幕長（秒）:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.min_dur_var = tk.StringVar(value=str(self.settings.min_subtitle_duration))
        ttk.Entry(row, textvariable=self.min_dur_var, width=10).pack(side=tk.LEFT)
        
        # 最大字幕長
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="最大字幕長（秒）:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.max_dur_var = tk.StringVar(value=str(self.settings.max_subtitle_duration))
        ttk.Entry(row, textvariable=self.max_dur_var, width=10).pack(side=tk.LEFT)
    
    def _create_translate_settings(self, parent):
        """翻訳設定を作成"""
        # 自動翻訳
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        self.auto_translate_var = tk.BooleanVar(value=self.settings.auto_translate)
        ttk.Checkbutton(row, text="抽出後に自動で翻訳する", variable=self.auto_translate_var).pack(anchor=tk.W)
        
        # 翻訳元言語
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="翻訳元言語:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.source_var = tk.StringVar(value=self.settings.translate_source)
        source_combo = ttk.Combobox(row, textvariable=self.source_var, state="readonly", width=15)
        source_combo['values'] = ["ja", "en", "zh", "ko"]
        source_combo.pack(side=tk.LEFT)
        
        # 翻訳先言語
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="翻訳先言語:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.target_var = tk.StringVar(value=self.settings.translate_target)
        target_combo = ttk.Combobox(row, textvariable=self.target_var, state="readonly", width=15)
        target_combo['values'] = ["en", "ja", "zh", "ko"]
        target_combo.pack(side=tk.LEFT)
        
        # Ollamaモデル
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="Ollamaモデル:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.model_var = tk.StringVar(value=self.settings.ollama_model)
        model_combo = ttk.Combobox(row, textvariable=self.model_var, width=20)
        model_combo['values'] = [
            "gemma3:4b",
            "gemma3:1b",
            "llama3.2:3b",
            "llama3.2:1b",
            "qwen2.5:3b",
            "qwen2.5:1.5b",
            "phi4-mini",
        ]
        model_combo.pack(side=tk.LEFT)
        
        # カスタム辞書
        dict_label = ttk.Label(parent, text="カスタム辞書（名前・固有名詞の翻訳指定）:")
        dict_label.pack(anchor=tk.W, pady=(10, 2))
        
        dict_hint = ttk.Label(parent, text="1行に1つ、「原文=翻訳」形式で入力（例: 原神=Genshin Impact）", foreground="gray")
        dict_hint.pack(anchor=tk.W, pady=(0, 2))
        
        import tkinter.scrolledtext as st
        self.dict_text = st.ScrolledText(parent, height=5, font=('TkDefaultFont', 10))
        self.dict_text.pack(fill=tk.X, pady=(0, 5))
        self.dict_text.insert('1.0', self.settings.custom_dictionary)
        if hasattr(self.parent, "_style_text_widget"):
            self.parent._style_text_widget(self.dict_text, font_size=12)
        
        # 注意書き
        note = ttk.Label(parent, text="※ 翻訳にはOllamaのインストールが必要です", foreground="gray")
        note.pack(anchor=tk.W, pady=10)
    
    def _create_display_settings(self, parent):
        """表示設定を作成"""
        # フォントサイズ
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="字幕フォントサイズ:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.font_size_var = tk.StringVar(value=str(self.settings.subtitle_font_size))
        ttk.Entry(row, textvariable=self.font_size_var, width=10).pack(side=tk.LEFT)
        ttk.Label(row, text="（12〜48）").pack(side=tk.LEFT, padx=10)
        
        # 背景透明度
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="字幕背景透明度:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.opacity_var = tk.StringVar(value=str(self.settings.subtitle_bg_opacity))
        ttk.Entry(row, textvariable=self.opacity_var, width=10).pack(side=tk.LEFT)
        ttk.Label(row, text="（0〜255）").pack(side=tk.LEFT, padx=10)
        
        # 自動改行の最大幅
        row = ttk.Frame(parent)
        row.pack(fill=tk.X, pady=5)
        ttk.Label(row, text="自動改行の最大幅:", width=20, anchor=tk.W).pack(side=tk.LEFT)
        self.wrap_ratio_var = tk.StringVar(value=str(round(self.settings.subtitle_wrap_width_ratio * 100)))
        ttk.Entry(row, textvariable=self.wrap_ratio_var, width=10).pack(side=tk.LEFT)
        ttk.Label(row, text="（% / 30〜95推奨）").pack(side=tk.LEFT, padx=10)
    
    def _on_ok(self):
        """OKボタン"""
        try:
            self.settings.fps_sample = float(self.fps_var.get())
            self.settings.detect_scroll = self.scroll_var.get()
            self.settings.similarity_threshold = float(self.similarity_var.get())
            self.settings.stability_frames = int(self.stability_var.get())
            self.settings.min_subtitle_duration = float(self.min_dur_var.get())
            self.settings.max_subtitle_duration = float(self.max_dur_var.get())
            self.settings.auto_translate = self.auto_translate_var.get()
            self.settings.translate_source = self.source_var.get()
            self.settings.translate_target = self.target_var.get()
            self.settings.ollama_model = self.model_var.get()
            self.settings.subtitle_font_size = int(self.font_size_var.get())
            self.settings.subtitle_bg_opacity = int(self.opacity_var.get())
            self.settings.subtitle_wrap_width_ratio = max(0.3, min(float(self.wrap_ratio_var.get()) / 100.0, 0.95))
            self.settings.custom_dictionary = self.dict_text.get('1.0', 'end-1c').strip()
            
            self.result = self.settings
            self.destroy()
        except ValueError as e:
            messagebox.showerror("エラー", f"入力値が不正です: {e}")
    
    def _on_cancel(self):
        """キャンセルボタン"""
        self.destroy()
    
    def _on_reset(self):
        """デフォルトに戻す"""
        default = AppSettings()
        self.fps_var.set(str(default.fps_sample))
        self.scroll_var.set(default.detect_scroll)
        self.similarity_var.set(str(default.similarity_threshold))
        self.stability_var.set(str(default.stability_frames))
        self.min_dur_var.set(str(default.min_subtitle_duration))
        self.max_dur_var.set(str(default.max_subtitle_duration))
        self.auto_translate_var.set(default.auto_translate)
        self.source_var.set(default.translate_source)
        self.target_var.set(default.translate_target)
        self.model_var.set(default.ollama_model)
        self.font_size_var.set(str(default.subtitle_font_size))
        self.opacity_var.set(str(default.subtitle_bg_opacity))
        self.wrap_ratio_var.set(str(round(default.subtitle_wrap_width_ratio * 100)))
        self.dict_text.delete('1.0', 'end')
        self.dict_text.insert('1.0', default.custom_dictionary)


class MainApplication(tk.Tk):
    """メインアプリケーション"""
    
    def __init__(self):
        super().__init__()
        
        self.title("字幕抽出ツール")
        self.geometry("1400x900")
        self.minsize(1000, 700)
        
        # 設定を読み込み
        self.settings_path = os.path.join(os.path.dirname(__file__), "settings.json")
        self.settings = AppSettings.load(self.settings_path)
        
        self._setup_styles()
        self.export_text_mode = tk.StringVar(value="original")
        
        self.video_path: str = ""
        self.subtitles: List[Subtitle] = []
        self.selected_subtitle_index: int = -1
        self.extractor: Optional[SubtitleExtractor] = None
        
        self._create_menu()
        self._create_ui()
        
        self.player = VideoPlayer(self.video_canvas, self._on_time_change)
        self.player.subtitle_font_size = self.settings.subtitle_font_size
        self.player.subtitle_bg_opacity = self.settings.subtitle_bg_opacity
        self.player.subtitle_wrap_width_ratio = self.settings.subtitle_wrap_width_ratio
        
        # キーバインド
        self.bind("<space>", lambda e: self._toggle_play())
        self.bind("<Left>", lambda e: self._seek_relative(-5))
        self.bind("<Right>", lambda e: self._seek_relative(5))
        self.bind("<Control-o>", lambda e: self._browse_video())
        self.bind("<Control-s>", lambda e: self._save_srt())

    def _preferred_font_family(self) -> str:
        """macOS風UI向けの優先フォントを取得"""
        families = set(tkfont.families())
        for candidate in ("SF Pro Text", "SF Pro", ".AppleSystemUIFont", "Helvetica Neue", "Hiragino Sans"):
            if candidate in families:
                return candidate
        return "TkDefaultFont"

    def _preferred_mono_font_family(self) -> str:
        """等幅フォントを取得"""
        families = set(tkfont.families())
        for candidate in ("SF Mono", "Menlo", "Monaco", "Courier New"):
            if candidate in families:
                return candidate
        return "TkFixedFont"

    def _setup_styles(self):
        """macOS向けにネイティブ寄りの見た目を設定"""
        self.font_family = self._preferred_font_family()
        self.mono_font_family = self._preferred_mono_font_family()

        style = ttk.Style(self)
        self.is_native_mac = sys.platform == "darwin" and "aqua" in style.theme_names()
        if self.is_native_mac:
            style.theme_use("aqua")
        elif "clam" in style.theme_names():
            style.theme_use("clam")

        self.colors = {
            "window": "#f5f5f7" if self.is_native_mac else "#eef1f5",
            "surface": "#ffffff" if self.is_native_mac else "#f7f9fc",
            "card": "#f5f5f7" if self.is_native_mac else "#ffffff",
            "text": "#1c1c1e" if self.is_native_mac else "#1f2937",
            "muted": "#6e6e73" if self.is_native_mac else "#6b7280",
            "border": "#d8d8dc" if self.is_native_mac else "#d6dbe4",
            "accent": "#0a84ff",
            "accent_pressed": "#006adc",
            "editor": "#ffffff",
            "canvas": "#111318",
        }
        self.style = style
        self.configure(bg=self.colors["window"])

        default_font = (self.font_family, 12)
        label_font = (self.font_family, 11)
        heading_font = (self.font_family, 12, "bold")
        title_font = (self.font_family, 16 if self.is_native_mac else 19, "bold")

        style.configure(".", font=default_font, foreground=self.colors["text"])
        style.configure("TFrame", background=self.colors["window"])
        style.configure("TLabel", background=self.colors["window"], foreground=self.colors["text"], font=default_font)
        style.configure("App.TFrame", background=self.colors["window"])
        style.configure("Pane.TFrame", background=self.colors["window"])
        style.configure("Header.TFrame", background=self.colors["window"])
        style.configure("Toolbar.TFrame", background=self.colors["window"])
        style.configure("Card.TFrame", background=self.colors["window"])
        style.configure(
            "Panel.TLabelframe",
            background=self.colors["window"],
            borderwidth=0 if self.is_native_mac else 1,
            relief="flat" if self.is_native_mac else "solid",
            bordercolor=self.colors["border"],
            lightcolor=self.colors["border"],
            darkcolor=self.colors["border"],
        )
        style.configure(
            "Panel.TLabelframe.Label",
            background=self.colors["window"],
            foreground=self.colors["muted"],
            font=(self.font_family, 11, "bold")
        )
        style.configure("HeaderTitle.TLabel", background=self.colors["window"], foreground=self.colors["text"], font=title_font)
        style.configure("HeaderSub.TLabel", background=self.colors["window"], foreground=self.colors["muted"], font=label_font)
        style.configure("Info.TLabel", background=self.colors["window"], foreground=self.colors["muted"], font=label_font)
        style.configure("Value.TLabel", background=self.colors["window"], foreground=self.colors["text"], font=heading_font)
        style.configure("Section.TLabel", background=self.colors["window"], foreground=self.colors["muted"], font=label_font)
        style.configure("Status.TLabel", background=self.colors["window"], foreground=self.colors["muted"], font=label_font)

        if self.is_native_mac:
            style.configure("Toolbar.TButton", font=default_font, padding=(10, 4))
            style.configure("Subtle.TButton", font=default_font, padding=(10, 4))
            style.configure("Primary.TButton", font=heading_font, padding=(12, 4))
        else:
            style.configure(
                "Toolbar.TButton",
                font=default_font,
                padding=(14, 8),
                background=self.colors["surface"],
                foreground=self.colors["text"],
                borderwidth=1,
                relief="flat",
                bordercolor=self.colors["border"],
                focuscolor=self.colors["accent"],
            )
            style.map(
                "Toolbar.TButton",
                background=[("active", self.colors["surface"]), ("pressed", self.colors["surface"])],
                bordercolor=[("focus", self.colors["accent"])]
            )
            style.configure(
                "Subtle.TButton",
                font=default_font,
                padding=(14, 8),
                background=self.colors["surface"],
                foreground=self.colors["text"],
                borderwidth=1,
                relief="flat",
                bordercolor=self.colors["border"],
                focuscolor=self.colors["accent"],
            )
            style.map(
                "Subtle.TButton",
                background=[("active", "#edf4ff"), ("pressed", "#edf4ff")],
                bordercolor=[("focus", self.colors["accent"])]
            )
            style.configure(
                "Primary.TButton",
                font=heading_font,
                padding=(16, 9),
                background=self.colors["accent"],
                foreground="#ffffff",
                borderwidth=1,
                relief="flat",
                bordercolor=self.colors["accent"],
                focuscolor=self.colors["accent"],
            )
            style.map(
                "Primary.TButton",
                background=[("active", self.colors["accent_pressed"]), ("pressed", self.colors["accent_pressed"])],
                bordercolor=[("focus", self.colors["accent_pressed"])]
            )
        style.configure(
            "TEntry",
            padding=8,
            fieldbackground=self.colors["editor"],
            background=self.colors["editor"],
            foreground=self.colors["text"],
            bordercolor=self.colors["border"],
            lightcolor=self.colors["border"],
            darkcolor=self.colors["border"],
            insertcolor=self.colors["text"],
        )
        style.map(
            "TEntry",
            bordercolor=[("focus", self.colors["accent"])],
            lightcolor=[("focus", self.colors["accent"])],
            darkcolor=[("focus", self.colors["accent"])]
        )
        style.configure(
            "TCombobox",
            padding=6,
            fieldbackground=self.colors["editor"],
            background=self.colors["editor"],
            foreground=self.colors["text"],
            bordercolor=self.colors["border"],
            arrowsize=14
        )
        style.map("TCombobox", bordercolor=[("focus", self.colors["accent"])])
        style.configure(
            "Treeview",
            background=self.colors["surface"],
            fieldbackground=self.colors["surface"],
            foreground=self.colors["text"],
            borderwidth=0,
            rowheight=28,
            font=default_font
        )
        style.configure(
            "Treeview.Heading",
            background=self.colors["window"],
            foreground=self.colors["muted"],
            relief="flat",
            font=heading_font
        )
        style.map("Treeview", background=[("selected", "#d7ebff")], foreground=[("selected", self.colors["text"])])
        style.configure(
            "Horizontal.TProgressbar",
            background=self.colors["accent"],
            troughcolor=self.colors["surface"],
            bordercolor=self.colors["surface"],
            lightcolor=self.colors["accent"],
            darkcolor=self.colors["accent"],
            thickness=8
        )
        style.configure(
            "TNotebook",
            background=self.colors["window"],
            borderwidth=0,
            tabmargins=(0, 0, 0, 0)
        )
        style.configure(
            "App.TNotebook",
            background=self.colors["window"],
            borderwidth=0,
            tabmargins=(0, 0, 0, 0)
        )
        style.configure(
            "TNotebook.Tab",
            padding=(16, 8),
            background=self.colors["surface"],
            foreground=self.colors["muted"],
            borderwidth=0
        )
        style.map(
            "TNotebook.Tab",
            background=[("selected", self.colors["card"]), ("active", self.colors["surface"])],
            foreground=[("selected", self.colors["text"])]
        )
        style.configure("TCheckbutton", background=self.colors["card"], foreground=self.colors["text"], font=default_font)
        style.configure("TRadiobutton", background=self.colors["card"], foreground=self.colors["text"], font=default_font)
        style.configure("TScale", background=self.colors["window"], troughcolor=self.colors["surface"])

    def _style_text_widget(self, widget: tk.Text, font_size: int = 13):
        """プレーンText/ScrolledTextをmacOS風に整える"""
        widget.configure(
            bg=self.colors["editor"],
            fg=self.colors["text"],
            insertbackground=self.colors["text"],
            relief=tk.FLAT,
            bd=0,
            highlightthickness=1,
            highlightbackground=self.colors["border"],
            highlightcolor=self.colors["accent"],
            font=(self.font_family, font_size),
            padx=12,
            pady=10,
            wrap=tk.WORD,
            undo=True,
        )
    
    def _create_menu(self):
        """メニューバーを作成"""
        menubar = tk.Menu(self)
        self.config(menu=menubar)
        
        # ファイルメニュー
        file_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="ファイル", menu=file_menu)
        file_menu.add_command(label="動画を開く...", command=self._browse_video, accelerator="Ctrl+O")
        file_menu.add_separator()
        file_menu.add_command(label="SRTを読み込み...", command=self._load_srt)
        file_menu.add_command(label="字幕を書き出し (SRT)...", command=self._save_srt, accelerator="Ctrl+S")
        file_menu.add_command(label="字幕を書き出し (FCPXML)...", command=self._save_fcpxml)
        file_menu.add_command(label="翻訳字幕を書き出し (SRT)...", command=self._save_translated_srt)
        file_menu.add_command(label="翻訳字幕を書き出し (FCPXML)...", command=self._save_translated_fcpxml)
        file_menu.add_separator()
        file_menu.add_command(label="終了", command=self.quit)
        
        # 編集メニュー
        edit_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="編集", menu=edit_menu)
        edit_menu.add_command(label="字幕を追加", command=self._add_subtitle)
        edit_menu.add_command(label="字幕を削除", command=self._delete_subtitle)
        edit_menu.add_separator()
        edit_menu.add_command(label="すべての字幕を削除", command=self._clear_all_subtitles)
        
        # ツールメニュー
        tools_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="ツール", menu=tools_menu)
        tools_menu.add_command(label="字幕を抽出", command=self._start_extraction)
        tools_menu.add_command(label="AI翻訳を実行", command=self._translate_subtitles)
        tools_menu.add_separator()
        tools_menu.add_command(label="詳細設定...", command=self._open_settings)
        
        # ヘルプメニュー
        help_menu = tk.Menu(menubar, tearoff=0)
        menubar.add_cascade(label="ヘルプ", menu=help_menu)
        help_menu.add_command(label="使い方", command=self._show_help)
        help_menu.add_command(label="バージョン情報", command=self._show_about)
    
    def _create_ui(self):
        """UIを構築"""
        main_frame = ttk.Frame(self, style="App.TFrame", padding=18)
        main_frame.pack(fill=tk.BOTH, expand=True)

        header = ttk.Frame(main_frame, style="Header.TFrame")
        header.pack(fill=tk.X, pady=(0, 14))
        ttk.Label(header, text="字幕抽出ツール", style="HeaderTitle.TLabel").pack(anchor=tk.W)
        ttk.Label(
            header,
            text="1. 動画を開く  2. 字幕を抽出  3. 必要なら翻訳・編集  4. SRT / FCPXML で書き出し",
            style="HeaderSub.TLabel"
        ).pack(anchor=tk.W, pady=(2, 0))

        content = ttk.Panedwindow(main_frame, orient=tk.HORIZONTAL)
        content.pack(fill=tk.BOTH, expand=True)

        left_frame = ttk.Frame(content, style="Pane.TFrame")
        right_frame = ttk.Frame(content, style="Pane.TFrame", width=430)

        content.add(left_frame, weight=5)
        content.add(right_frame, weight=3)

        self._create_video_panel(left_frame)
        self._create_control_panel(right_frame)
    
    def _create_video_panel(self, parent):
        """動画パネルを作成"""
        toolbar = ttk.Frame(parent, style="Toolbar.TFrame")
        toolbar.pack(fill=tk.X, pady=(0, 12))

        action_group = ttk.LabelFrame(toolbar, text="抽出", style="Panel.TLabelframe", padding=(12, 10))
        action_group.pack(side=tk.LEFT, padx=(0, 10))
        ttk.Button(action_group, text="動画を開く", command=self._browse_video, style="Toolbar.TButton").pack(side=tk.LEFT)
        ttk.Button(action_group, text="字幕を抽出", command=self._start_extraction, style="Primary.TButton").pack(side=tk.LEFT, padx=8)
        ttk.Button(action_group, text="AI翻訳", command=self._translate_subtitles, style="Subtle.TButton").pack(side=tk.LEFT)

        export_group = ttk.LabelFrame(toolbar, text="書き出し", style="Panel.TLabelframe", padding=(12, 10))
        export_group.pack(side=tk.LEFT, padx=(0, 10))
        export_mode_frame = ttk.Frame(export_group, style="Card.TFrame")
        export_mode_frame.pack(side=tk.LEFT, padx=(0, 10))
        ttk.Label(export_mode_frame, text="内容:", style="Section.TLabel").pack(side=tk.LEFT, padx=(0, 6))
        ttk.Radiobutton(export_mode_frame, text="原文", variable=self.export_text_mode, value="original").pack(side=tk.LEFT)
        ttk.Radiobutton(export_mode_frame, text="翻訳字幕", variable=self.export_text_mode, value="translated").pack(side=tk.LEFT, padx=(6, 0))

        ttk.Button(export_group, text="SRT書き出し", command=self._save_srt, style="Toolbar.TButton").pack(side=tk.LEFT)
        ttk.Button(export_group, text="FCPXML書き出し", command=self._save_fcpxml, style="Toolbar.TButton").pack(side=tk.LEFT, padx=8)

        utility_group = ttk.LabelFrame(toolbar, text="設定", style="Panel.TLabelframe", padding=(12, 10))
        utility_group.pack(side=tk.LEFT)
        ttk.Button(utility_group, text="詳細設定", command=self._open_settings, style="Toolbar.TButton").pack(side=tk.LEFT)

        canvas_frame = ttk.LabelFrame(parent, text="動画プレビュー", style="Panel.TLabelframe", padding=14)
        canvas_frame.pack(fill=tk.BOTH, expand=True)

        self.video_canvas = tk.Canvas(
            canvas_frame,
            bg=self.colors["canvas"],
            highlightthickness=1,
            highlightbackground="#1b2330"
        )
        self.video_canvas.pack(fill=tk.BOTH, expand=True)
        
        # キャンバスイベント
        self.video_canvas.bind("<ButtonPress-1>", self._on_canvas_press)
        self.video_canvas.bind("<B1-Motion>", self._on_canvas_drag)
        self.video_canvas.bind("<ButtonRelease-1>", self._on_canvas_release)
        
        # コントロールバー
        control_frame = ttk.LabelFrame(parent, text="再生コントロール", style="Panel.TLabelframe", padding=(14, 12))
        control_frame.pack(fill=tk.X, pady=(12, 0))
        
        # 再生ボタン
        btn_frame = ttk.Frame(control_frame, style="Card.TFrame")
        btn_frame.pack(side=tk.LEFT)
        
        self.play_btn = ttk.Button(btn_frame, text="▶", command=self._toggle_play, width=3, style="Toolbar.TButton")
        self.play_btn.pack(side=tk.LEFT, padx=2)
        
        ttk.Button(btn_frame, text="⏹", command=self._stop_video, width=3, style="Toolbar.TButton").pack(side=tk.LEFT, padx=2)
        
        # シークバー
        self.seek_var = tk.DoubleVar(value=0)
        self.seek_bar = ttk.Scale(
            control_frame,
            from_=0,
            to=100,
            variable=self.seek_var,
            orient=tk.HORIZONTAL,
            command=self._on_seek
        )
        self.seek_bar.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=10)
        
        # 時間表示
        self.time_label = ttk.Label(control_frame, text="00:00:00 / 00:00:00", style="Status.TLabel")
        self.time_label.pack(side=tk.RIGHT)
        
        option_frame = ttk.LabelFrame(parent, text="表示オプション", style="Panel.TLabelframe", padding=(14, 12))
        option_frame.pack(fill=tk.X, pady=(12, 0))
        
        self.subtitle_toggle_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(
            option_frame,
            text="字幕を表示",
            variable=self.subtitle_toggle_var,
            command=self._toggle_subtitle_display
        ).pack(side=tk.LEFT)
        
        self.translated_toggle_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(
            option_frame,
            text="翻訳を表示",
            variable=self.translated_toggle_var,
            command=self._toggle_translated_display
        ).pack(side=tk.LEFT, padx=10)
        
        # 字幕領域
        ttk.Label(option_frame, text="字幕領域:").pack(side=tk.LEFT, padx=(20, 5))
        self.region_label = ttk.Label(option_frame, text="未設定", style="Value.TLabel")
        self.region_label.pack(side=tk.LEFT)
        ttk.Button(option_frame, text="クリア", command=self._clear_region, width=6, style="Toolbar.TButton").pack(side=tk.LEFT, padx=5)
        
        status_frame = ttk.LabelFrame(parent, text="処理状況", style="Panel.TLabelframe", padding=(14, 12))
        status_frame.pack(fill=tk.X, pady=(12, 0))
        
        self.progress_var = tk.DoubleVar(value=0)
        self.progress_bar = ttk.Progressbar(
            status_frame,
            variable=self.progress_var,
            maximum=100
        )
        self.progress_bar.pack(side=tk.LEFT, fill=tk.X, expand=True)
        
        self.status_label = ttk.Label(status_frame, text="準備完了", width=40, anchor=tk.W, style="Status.TLabel")
        self.status_label.pack(side=tk.RIGHT, padx=(10, 0))
    
    def _create_control_panel(self, parent):
        """コントロールパネルを作成"""
        list_frame = ttk.LabelFrame(parent, text="字幕リスト", style="Panel.TLabelframe", padding=14)
        list_frame.pack(fill=tk.BOTH, expand=True)

        list_meta = ttk.Frame(list_frame, style="Card.TFrame")
        list_meta.pack(fill=tk.X, pady=(0, 10))
        ttk.Label(list_meta, text="抽出された字幕をここで確認・修正します", style="Section.TLabel").pack(side=tk.LEFT)
        ttk.Label(list_meta, text="時間重なりは自動補正", style="Info.TLabel").pack(side=tk.RIGHT)
        
        columns = ("index", "time", "text")
        self.subtitle_tree = ttk.Treeview(
            list_frame,
            columns=columns,
            show="headings",
            height=15
        )
        
        self.subtitle_tree.heading("index", text="#")
        self.subtitle_tree.heading("time", text="時間")
        self.subtitle_tree.heading("text", text="テキスト")
        
        self.subtitle_tree.column("index", width=30)
        self.subtitle_tree.column("time", width=100)
        self.subtitle_tree.column("text", width=200)
        
        scrollbar = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=self.subtitle_tree.yview)
        self.subtitle_tree.configure(yscrollcommand=scrollbar.set)
        
        self.subtitle_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.subtitle_tree.bind("<<TreeviewSelect>>", self._on_subtitle_select)
        
        edit_frame = ttk.LabelFrame(parent, text="字幕編集", style="Panel.TLabelframe", padding=14)
        edit_frame.pack(fill=tk.X, pady=(12, 0))
        
        # 時間編集
        time_frame = ttk.Frame(edit_frame, style="Card.TFrame")
        time_frame.pack(fill=tk.X, pady=(0, 8))
        
        ttk.Label(time_frame, text="開始:").pack(side=tk.LEFT)
        self.start_time_entry = ttk.Entry(time_frame, width=12)
        self.start_time_entry.pack(side=tk.LEFT, padx=5)
        
        ttk.Label(time_frame, text="終了:").pack(side=tk.LEFT)
        self.end_time_entry = ttk.Entry(time_frame, width=12)
        self.end_time_entry.pack(side=tk.LEFT, padx=5)
        
        # テキスト編集
        ttk.Label(edit_frame, text="テキスト:", style="Section.TLabel").pack(anchor=tk.W)
        self.text_entry = tk.Text(edit_frame, height=4)
        self.text_entry.pack(fill=tk.X, pady=(4, 10))
        self._style_text_widget(self.text_entry)
        
        # 翻訳テキスト
        ttk.Label(edit_frame, text="翻訳:", style="Section.TLabel").pack(anchor=tk.W)
        self.translated_entry = tk.Text(edit_frame, height=2)
        self.translated_entry.pack(fill=tk.X, pady=(4, 10))
        self._style_text_widget(self.translated_entry)
        
        # 編集ボタン
        btn_frame = ttk.Frame(edit_frame, style="Card.TFrame")
        btn_frame.pack(fill=tk.X)
        
        ttk.Button(btn_frame, text="変更を適用", command=self._apply_edit, style="Primary.TButton").pack(side=tk.LEFT)
        ttk.Button(btn_frame, text="追加", command=self._add_subtitle, style="Toolbar.TButton").pack(side=tk.LEFT, padx=8)
        ttk.Button(btn_frame, text="削除", command=self._delete_subtitle, style="Subtle.TButton").pack(side=tk.LEFT)
    
    # イベントハンドラ
    def _browse_video(self):
        """動画ファイルを選択"""
        path = filedialog.askopenfilename(
            title="動画ファイルを選択",
            filetypes=[
                ("動画ファイル", "*.mp4 *.avi *.mkv *.mov *.wmv"),
                ("すべてのファイル", "*.*")
            ]
        )
        
        if path:
            self.video_path = path
            if self.player.load_video(path):
                self.seek_bar.configure(to=self.player.duration)
                self._update_time_display()
                self.status_label.configure(text=f"読み込み完了: {os.path.basename(path)}")
            else:
                messagebox.showerror("エラー", "動画を読み込めませんでした")
    
    def _on_canvas_press(self, event):
        """キャンバスクリック開始"""
        if not self.video_path:
            return
        self.player.selection_start = (event.x, event.y)
    
    def _on_canvas_drag(self, event):
        """キャンバスドラッグ"""
        if not self.video_path or not self.player.selection_start:
            return
        
        if self.player.selection_rect:
            self.video_canvas.delete(self.player.selection_rect)
        
        x1, y1 = self.player.selection_start
        x2, y2 = event.x, event.y
        
        self.player.selection_rect = self.video_canvas.create_rectangle(
            x1, y1, x2, y2,
            outline="#00ff00",
            width=2
        )
    
    def _on_canvas_release(self, event):
        """キャンバスクリック終了"""
        if not self.video_path or not self.player.selection_start:
            return
        
        x1, y1 = self.player.selection_start
        x2, y2 = event.x, event.y
        
        if abs(x2 - x1) < 10 or abs(y2 - y1) < 10:
            self.player.selection_start = None
            if self.player.selection_rect:
                self.video_canvas.delete(self.player.selection_rect)
            return
        
        canvas_width = self.video_canvas.winfo_width()
        canvas_height = self.video_canvas.winfo_height()
        
        if self.player.photo_image:
            img_width = self.player.photo_image.width()
            img_height = self.player.photo_image.height()
            
            offset_x = (canvas_width - img_width) / 2
            offset_y = (canvas_height - img_height) / 2
            
            rel_x1 = (min(x1, x2) - offset_x) / img_width
            rel_y1 = (min(y1, y2) - offset_y) / img_height
            rel_x2 = (max(x1, x2) - offset_x) / img_width
            rel_y2 = (max(y1, y2) - offset_y) / img_height
            
            rel_x1 = max(0, min(1, rel_x1))
            rel_y1 = max(0, min(1, rel_y1))
            rel_x2 = max(0, min(1, rel_x2))
            rel_y2 = max(0, min(1, rel_y2))
            
            region = (rel_x1, rel_y1, rel_x2 - rel_x1, rel_y2 - rel_y1)
            self.player.set_subtitle_region(region)
            self.region_label.configure(text="設定済み")
        
        self.player.selection_start = None
    
    def _clear_region(self):
        """字幕領域をクリア"""
        self.player.set_subtitle_region(None)
        self.region_label.configure(text="未設定")
    
    def _toggle_play(self):
        """再生/一時停止を切り替え"""
        if not self.video_path:
            return
        
        if self.player.is_playing:
            self.player.pause()
            self.play_btn.configure(text="▶")
        else:
            self.player.play()
            self.play_btn.configure(text="⏸")
    
    def _stop_video(self):
        """動画を停止"""
        self.player.stop()
        self.play_btn.configure(text="▶")
        self.player.show_frame(0)
    
    def _on_seek(self, value):
        """シークバー操作"""
        if self.video_path:
            self.player.seek(float(value))
    
    def _seek_relative(self, seconds: float):
        """相対シーク"""
        if self.video_path:
            new_time = max(0, min(self.player.current_time + seconds, self.player.duration))
            self.player.seek(new_time)
            self.seek_var.set(new_time)
    
    def _on_time_change(self, current_time: float):
        """時間変更時"""
        self.seek_var.set(current_time)
        self._update_time_display()
    
    def _update_time_display(self):
        """時間表示を更新"""
        current = format_time(self.player.current_time).split(',')[0]
        total = format_time(self.player.duration).split(',')[0]
        self.time_label.configure(text=f"{current} / {total}")
    
    def _toggle_subtitle_display(self):
        """字幕表示を切り替え"""
        self.player.show_subtitles = self.subtitle_toggle_var.get()
        self.player.show_frame(self.player.current_frame)
    
    def _toggle_translated_display(self):
        """翻訳表示を切り替え"""
        self.player.show_translated = self.translated_toggle_var.get()
        self.player.show_frame(self.player.current_frame)

    def _sync_export_mode(self, prefer_translated: bool = False):
        """翻訳有無に応じて書き出し内容を整える"""
        has_translation = any(sub.translated.strip() for sub in self.subtitles)
        if prefer_translated and has_translation:
            self.export_text_mode.set("translated")
        elif not has_translation and self.export_text_mode.get() == "translated":
            self.export_text_mode.set("original")

    def _get_timeline_end(self) -> Optional[float]:
        """字幕の上限時間を取得"""
        if self.player and self.player.duration > 0:
            return self.player.duration
        if self.subtitles:
            return max(sub.end_time for sub in self.subtitles)
        return None

    def _normalize_subtitles(self):
        """字幕リストを時間順に正規化"""
        if not self.subtitles:
            return

        normalize_subtitle_timings(
            self.subtitles,
            self.settings.min_subtitle_duration,
            self.settings.max_subtitle_duration,
            self._get_timeline_end()
        )

    def _subtitle_wrap_width_px(self, width: Optional[int] = None) -> float:
        """字幕の折り返し最大幅をピクセルで取得"""
        base_width = width or self._get_video_size()[0]
        ratio = max(0.3, min(self.settings.subtitle_wrap_width_ratio, 0.95))
        return base_width * ratio

    def _formatted_subtitle_text(
        self,
        subtitle: Subtitle,
        translated: bool = False,
        font_size: Optional[int] = None,
        width: Optional[int] = None
    ) -> str:
        """書き出し用の字幕テキストを取得"""
        base_text = subtitle.translated if translated and subtitle.translated else subtitle.text
        target_font_size = font_size or self.settings.subtitle_font_size
        font = load_subtitle_font(target_font_size)
        return wrap_subtitle_text(base_text, self._subtitle_wrap_width_px(width), font)

    def _get_video_size(self) -> Tuple[int, int]:
        """動画サイズを取得"""
        if self.player and self.player.cap:
            width = int(self.player.cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
            height = int(self.player.cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
            if width > 0 and height > 0:
                return width, height
        return 1920, 1080

    def _write_srt_file(self, path: str, translated: bool = False):
        """SRTを書き出し"""
        self._normalize_subtitles()
        video_width, _ = self._get_video_size()

        with open(path, 'w', encoding='utf-8') as f:
            for sub in self.subtitles:
                f.write(f"{sub.index}\n")
                f.write(f"{format_time(sub.start_time)} --> {format_time(sub.end_time)}\n")
                f.write(f"{self._formatted_subtitle_text(sub, translated, width=video_width)}\n\n")

    def _write_fcpxml_file(self, path: str, translated: bool = False):
        """FCPXMLを書き出し"""
        self._normalize_subtitles()

        fps = self.player.fps if self.player and self.player.fps > 0 else 30.0
        width, height = self._get_video_size()
        total_duration = self._get_timeline_end() or max(sub.end_time for sub in self.subtitles)
        font_size = max(36, int(self.settings.subtitle_font_size * 1.8))

        root = ET.Element("fcpxml", version="1.11")
        resources = ET.SubElement(root, "resources")
        ET.SubElement(
            resources,
            "format",
            id="r1",
            name=f"SubtitleFormat{height}p",
            frameDuration=seconds_to_fcpx_time(1.0 / fps, fps),
            width=str(width),
            height=str(height),
            colorSpace="1-1-1 (Rec. 709)"
        )
        ET.SubElement(
            resources,
            "effect",
            id="r2",
            name="Basic Title",
            uid=".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"
        )

        library = ET.SubElement(root, "library")
        event = ET.SubElement(library, "event", name="Subtitle Export")
        project = ET.SubElement(event, "project", name=os.path.splitext(os.path.basename(path))[0])
        sequence = ET.SubElement(
            project,
            "sequence",
            format="r1",
            duration=seconds_to_fcpx_time(total_duration, fps),
            tcStart="0s",
            tcFormat="NDF",
            audioLayout="stereo",
            audioRate="48k"
        )
        spine = ET.SubElement(sequence, "spine")
        gap = ET.SubElement(
            spine,
            "gap",
            name="Gap",
            offset="0s",
            start="0s",
            duration=seconds_to_fcpx_time(total_duration, fps)
        )

        for sub in self.subtitles:
            title = ET.SubElement(
                gap,
                "title",
                ref="r2",
                name=f"Subtitle {sub.index}",
                lane="1",
                offset=seconds_to_fcpx_time(sub.start_time, fps),
                start="0s",
                duration=seconds_to_fcpx_time(sub.end_time - sub.start_time, fps)
            )
            text = ET.SubElement(title, "text")
            style_id = f"ts{sub.index}"
            text_style = ET.SubElement(text, "text-style", ref=style_id)
            text_style.text = self._formatted_subtitle_text(sub, translated, font_size=font_size, width=width)
            style_def = ET.SubElement(title, "text-style-def", id=style_id)
            ET.SubElement(
                style_def,
                "text-style",
                font="Hiragino Sans",
                fontSize=str(font_size),
                fontFace="Regular",
                fontColor="1 1 1 1",
                alignment="center"
            )

        tree = ET.ElementTree(root)
        ET.indent(tree, space="  ")
        tree.write(path, encoding="utf-8", xml_declaration=True)

    def _export_subtitles(self, translated: Optional[bool] = None, export_format: str = "srt"):
        """字幕を書き出し"""
        if not self.subtitles:
            messagebox.showwarning("警告", "保存する字幕がありません")
            return

        if translated is None:
            translated = self.export_text_mode.get() == "translated"

        if translated and not any(sub.translated for sub in self.subtitles):
            messagebox.showwarning("警告", "翻訳された字幕がありません")
            return

        export_format = export_format.lower()
        extension = ".fcpxml" if export_format == "fcpxml" else ".srt"
        label = "FCPXMLファイル" if export_format == "fcpxml" else "SRTファイル"

        path = filedialog.asksaveasfilename(
            title=f"{label}を保存",
            defaultextension=extension,
            filetypes=[(label, f"*{extension}")]
        )

        if not path:
            return

        try:
            if export_format == "fcpxml":
                self._write_fcpxml_file(path, translated=translated)
            else:
                self._write_srt_file(path, translated=translated)
            self.player.set_subtitles(self.subtitles)
            self.player.show_frame(self.player.current_frame)
            self._update_subtitle_list()
            self.status_label.configure(text=f"保存完了: {os.path.basename(path)}")
        except Exception as e:
            messagebox.showerror("エラー", f"保存に失敗しました: {e}")

    def _open_settings(self):
        """設定ダイアログを開く"""
        dialog = SettingsDialog(self, self.settings)
        self.wait_window(dialog)
        
        if dialog.result:
            self.settings = dialog.result
            self.settings.save(self.settings_path)
            
            # プレーヤーに設定を反映
            self.player.subtitle_font_size = self.settings.subtitle_font_size
            self.player.subtitle_bg_opacity = self.settings.subtitle_bg_opacity
            self.player.subtitle_wrap_width_ratio = self.settings.subtitle_wrap_width_ratio
            self._normalize_subtitles()
            self._update_subtitle_list()
            self.player.show_frame(self.player.current_frame)
            
            self.status_label.configure(text="設定を保存しました")
    
    def _start_extraction(self):
        """字幕抽出を開始"""
        if not self.video_path:
            messagebox.showwarning("警告", "動画ファイルを選択してください")
            return
        
        self.progress_var.set(0)
        self.status_label.configure(text="字幕を抽出中...")
        
        def extract_thread():
            try:
                self.extractor = SubtitleExtractor(self.settings)
                
                def update_progress(p):
                    self.after(0, lambda p=p: self.progress_var.set(p))
                
                def update_frame(f, t):
                    self.after(0, lambda f=f, t=t: self._on_frame_processed(f, t))
                
                subtitles = self.extractor.extract(
                    self.video_path,
                    region=self.player.subtitle_region,
                    progress_callback=update_progress,
                    frame_callback=update_frame
                )
                
                auto_translate = self.settings.auto_translate
                self.after(0, lambda s=subtitles, at=auto_translate: self._on_extraction_complete(s, at))
            except Exception as e:
                error_msg = str(e)
                self.after(0, lambda msg=error_msg: self._on_extraction_error(msg))
        
        threading.Thread(target=extract_thread, daemon=True).start()
    
    def _on_frame_processed(self, frame_num: int, text: str):
        """フレーム処理時のコールバック"""
        self.player.show_frame(frame_num)
        if text:
            self.status_label.configure(text=f"認識中: {text[:30]}...")
    
    def _on_extraction_complete(self, subtitles: List[Subtitle], auto_translate: bool = False):
        """抽出完了時"""
        self.subtitles = subtitles
        self._normalize_subtitles()
        self._sync_export_mode()
        self.player.set_subtitles(subtitles)
        self._update_subtitle_list()
        
        if auto_translate and subtitles:
            self.status_label.configure(text=f"抽出完了: {len(subtitles)}件 → 翻訳中...")
            self._translate_subtitles_internal()
        else:
            self.progress_var.set(100)
            self.status_label.configure(text=f"完了: {len(subtitles)}件の字幕を抽出しました")
    
    def _on_extraction_error(self, error: str):
        """抽出エラー時"""
        self.status_label.configure(text=f"エラー: {error}")
        messagebox.showerror("エラー", f"抽出中にエラーが発生しました:\n{error}")
    
    def _translate_subtitles(self):
        """字幕を翻訳"""
        if not self.subtitles:
            messagebox.showwarning("警告", "翻訳する字幕がありません")
            return
        
        self.status_label.configure(text="翻訳中...")
        self._translate_subtitles_internal()
    
    def _translate_subtitles_internal(self):
        """字幕を翻訳（内部用）"""
        def translate_thread():
            try:
                from ollama_processor import OllamaProcessor
                processor = OllamaProcessor(model=self.settings.ollama_model)
                
                total = len(self.subtitles)
                for i, sub in enumerate(self.subtitles):
                    if sub.text:
                        translated = processor.translate(
                            sub.text,
                            self.settings.translate_source,
                            self.settings.translate_target
                        )
                        sub.translated = translated
                    
                    progress = (i + 1) / total * 100
                    self.after(0, lambda p=progress: self.progress_var.set(p))
                    self.after(0, lambda i=i, t=total: self.status_label.configure(text=f"翻訳中: {i+1}/{t}"))
                
                self.after(0, self._on_translate_complete)
            except Exception as e:
                error_msg = str(e)
                self.after(0, lambda msg=error_msg: self._on_translate_error(msg))
        
        threading.Thread(target=translate_thread, daemon=True).start()
    
    def _on_translate_complete(self):
        """翻訳完了時"""
        self.progress_var.set(100)
        self.status_label.configure(text=f"翻訳完了: {len(self.subtitles)}件")
        self._sync_export_mode(prefer_translated=True)
        self._update_subtitle_list()
        self.player.set_subtitles(self.subtitles)
        self.player.show_frame(self.player.current_frame)
    
    def _on_translate_error(self, error: str):
        """翻訳エラー時"""
        self.status_label.configure(text=f"翻訳エラー: {error}")
        messagebox.showwarning("警告", f"翻訳中にエラーが発生しました:\n{error}")
    
    def _update_subtitle_list(self):
        """字幕リストを更新"""
        self.subtitle_tree.delete(*self.subtitle_tree.get_children())
        self.subtitle_tree.tag_configure("even", background=self.colors["surface"])
        self.subtitle_tree.tag_configure("odd", background="#fbfbfd" if self.is_native_mac else "#f6f8fb")
        
        for row_index, sub in enumerate(self.subtitles):
            time_str = f"{format_time(sub.start_time).split(',')[0]}"
            tag = "even" if row_index % 2 == 0 else "odd"
            self.subtitle_tree.insert("", tk.END, values=(sub.index, time_str, sub.text[:40]), tags=(tag,))
    
    def _on_subtitle_select(self, event):
        """字幕選択時"""
        selection = self.subtitle_tree.selection()
        if not selection:
            return
        
        try:
            item = self.subtitle_tree.item(selection[0])
            values = item.get('values', [])
            if not values:
                return
            
            index = int(values[0]) - 1
            
            if 0 <= index < len(self.subtitles):
                self.selected_subtitle_index = index
                sub = self.subtitles[index]
                
                self.start_time_entry.delete(0, tk.END)
                self.start_time_entry.insert(0, format_time(sub.start_time))
                
                self.end_time_entry.delete(0, tk.END)
                self.end_time_entry.insert(0, format_time(sub.end_time))
                
                self.text_entry.delete("1.0", tk.END)
                self.text_entry.insert("1.0", sub.text)
                
                self.translated_entry.delete("1.0", tk.END)
                self.translated_entry.insert("1.0", sub.translated if sub.translated else "")
                
                if self.video_path:
                    self.player.seek(sub.start_time)
        except Exception as e:
            print(f"Subtitle selection error: {e}")
    
    def _apply_edit(self):
        """編集を適用"""
        if self.selected_subtitle_index < 0:
            messagebox.showwarning("警告", "字幕を選択してください")
            return
        
        if self.selected_subtitle_index >= len(self.subtitles):
            return
        
        try:
            sub = self.subtitles[self.selected_subtitle_index]
            
            sub.start_time = parse_time(self.start_time_entry.get())
            sub.end_time = parse_time(self.end_time_entry.get())
            sub.text = self.text_entry.get("1.0", tk.END).strip()
            sub.translated = self.translated_entry.get("1.0", tk.END).strip()

            self._normalize_subtitles()
            self._sync_export_mode(prefer_translated=bool(sub.translated))
            self._update_subtitle_list()
            self.player.set_subtitles(self.subtitles)
            self.player.show_frame(self.player.current_frame)
            self.status_label.configure(text="変更を適用しました")
        except Exception as e:
            messagebox.showerror("エラー", f"編集の適用に失敗しました: {e}")
    
    def _add_subtitle(self):
        """字幕を追加"""
        new_sub = Subtitle(
            index=len(self.subtitles) + 1,
            start_time=self.player.current_time,
            end_time=self.player.current_time + 2.0,
            text="新しい字幕"
        )
        self.subtitles.append(new_sub)
        self._normalize_subtitles()
        self._update_subtitle_list()
        self.player.set_subtitles(self.subtitles)
        self.player.show_frame(self.player.current_frame)
    
    def _delete_subtitle(self):
        """字幕を削除"""
        if self.selected_subtitle_index < 0:
            return
        
        del self.subtitles[self.selected_subtitle_index]
        
        for i, sub in enumerate(self.subtitles):
            sub.index = i + 1
        
        self.selected_subtitle_index = -1
        self._normalize_subtitles()
        self._sync_export_mode()
        self._update_subtitle_list()
        self.player.set_subtitles(self.subtitles)
        self.player.show_frame(self.player.current_frame)
    
    def _clear_all_subtitles(self):
        """すべての字幕を削除"""
        if not self.subtitles:
            return
        
        if messagebox.askyesno("確認", "すべての字幕を削除しますか？"):
            self.subtitles = []
            self.selected_subtitle_index = -1
            self._sync_export_mode()
            self._update_subtitle_list()
            self.player.set_subtitles(self.subtitles)
    
    def _load_srt(self):
        """SRTファイルを読み込み"""
        path = filedialog.askopenfilename(
            title="SRTファイルを選択",
            filetypes=[("SRTファイル", "*.srt")]
        )
        
        if not path:
            return
        
        try:
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            self.subtitles = []
            blocks = content.strip().split('\n\n')
            
            for block in blocks:
                lines = block.strip().split('\n')
                if len(lines) >= 3:
                    index = int(lines[0])
                    times = lines[1].split(' --> ')
                    start_time = parse_time(times[0])
                    end_time = parse_time(times[1])
                    text = '\n'.join(lines[2:])
                    
                    self.subtitles.append(Subtitle(
                        index=index,
                        start_time=start_time,
                        end_time=end_time,
                        text=text
                    ))
            
            self._normalize_subtitles()
            self._sync_export_mode()
            self._update_subtitle_list()
            self.player.set_subtitles(self.subtitles)
            self.status_label.configure(text=f"読み込み完了: {len(self.subtitles)}件")
        except Exception as e:
            messagebox.showerror("エラー", f"読み込みに失敗しました: {e}")

    def _save_srt(self):
        """SRTファイルを保存"""
        self._export_subtitles(translated=None, export_format="srt")

    def _save_translated_srt(self):
        """翻訳SRTファイルを保存"""
        self._export_subtitles(translated=True, export_format="srt")

    def _save_fcpxml(self):
        """FCPXMLファイルを保存"""
        self._export_subtitles(translated=None, export_format="fcpxml")

    def _save_translated_fcpxml(self):
        """翻訳FCPXMLファイルを保存"""
        self._export_subtitles(translated=True, export_format="fcpxml")
    
    def _show_help(self):
        """ヘルプを表示"""
        help_text = """【字幕抽出ツール 使い方】

1. 「動画を開く」で動画ファイルを選択
2. 動画上でドラッグして字幕領域を選択（任意）
3. 「字幕を抽出」ボタンをクリック
4. 抽出完了後、必要に応じて編集
5. 保存前に「書き出し」欄で `原文 / 翻訳字幕` を選択
6. 必要に応じて自動改行の最大幅を設定
7. `SRT` または `FCPXML` で書き出し

【ショートカットキー】
- Space: 再生/一時停止
- ←/→: 5秒シーク
- Ctrl+O: 動画を開く
- Ctrl+S: 字幕をSRTで書き出し

【翻訳機能】
翻訳にはOllamaが必要です。
インストール後、「AI翻訳」ボタンで実行できます。

【自動改行】
文字数ではなく、設定の「自動改行の最大幅」に合わせて
プレビューと書き出しの両方で折り返します。
"""
        messagebox.showinfo("使い方", help_text)
    
    def _show_about(self):
        """バージョン情報を表示"""
        messagebox.showinfo("バージョン情報", "字幕抽出ツール v4.1\n\nmeikiOCRを使用した\nゲーム字幕抽出ツール")


if __name__ == "__main__":
    app = MainApplication()
    app.mainloop()
