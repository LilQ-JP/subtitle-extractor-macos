"""
統合OCRエンジン
従来のOCR（EasyOCR, manga-ocr）とVision AI（Llama, LLaVA, moondream）を統合
スクロール字幕検出機能付き
"""

import cv2
import numpy as np
import subprocess
import tempfile
import os
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional, Tuple, Callable
from enum import Enum


class OCREngine(Enum):
    """OCRエンジンの種類"""
    MEIKI_OCR = "meikiocr"


@dataclass
class SubtitleEntry:
    """字幕エントリ"""
    start_time: float
    end_time: float
    text: str
    translated: str = ""
    confidence: float = 1.0
    is_complete: bool = True


@dataclass
class SubtitleRegion:
    """字幕領域（正規化座標 0.0-1.0）"""
    x: float
    y: float
    width: float
    height: float


class UnifiedOCR:
    """統合OCRエンジン"""
    
    def __init__(self, 
                 engine: OCREngine = OCREngine.MEIKI_OCR,
                 language: str = 'ja',
                 enable_scroll_detection: bool = True):
        self.engine = engine
        self.language = language
        self.enable_scroll_detection = enable_scroll_detection
        self._ocr_instance = None
        self._scroll_detector = None
        
    def _init_meiki_ocr(self):
        if self._ocr_instance is None:
            from meikiocr import MeikiOCR
            self._ocr_instance = MeikiOCR()
        return self._ocr_instance
    
    def _init_scroll_detector(self):
        if self._scroll_detector is None:
            from scroll_detector import ScrollSubtitleDetector
            self._scroll_detector = ScrollSubtitleDetector(
                similarity_threshold=0.6,
                stability_frames=2
            )
        return self._scroll_detector
    
    def _preprocess_image(self, image: np.ndarray) -> np.ndarray:
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(gray)
        denoised = cv2.fastNlMeansDenoising(enhanced, None, 10, 7, 21)
        scale = 2
        enlarged = cv2.resize(denoised, None, fx=scale, fy=scale, 
                             interpolation=cv2.INTER_CUBIC)
        return enlarged
    
    def _crop_region(self, image: np.ndarray, 
                     region: Optional[SubtitleRegion]) -> np.ndarray:
        if region is None:
            return image
        h, w = image.shape[:2]
        x1 = int(region.x * w)
        y1 = int(region.y * h)
        x2 = int((region.x + region.width) * w)
        y2 = int((region.y + region.height) * h)
        x1 = max(0, min(x1, w))
        x2 = max(0, min(x2, w))
        y1 = max(0, min(y1, h))
        y2 = max(0, min(y2, h))
        return image[y1:y2, x1:x2]
    
    def recognize_image(self, image: np.ndarray, 
                        region: Optional[SubtitleRegion] = None) -> Tuple[str, float]:
        cropped = self._crop_region(image, region)
        if cropped.size == 0:
            return "", 0.0
        if self.engine == OCREngine.MEIKI_OCR:
            return self._recognize_meiki_ocr(cropped)
        else:
            raise ValueError(f"未対応のエンジン: {self.engine}")
            
    def _recognize_meiki_ocr(self, image: np.ndarray) -> Tuple[str, float]:
        ocr = self._init_meiki_ocr()
        # meikiOCR accepts numpy arrays directly
        results = ocr.run_ocr(image)
        if results:
            texts = [line['text'] for line in results if line.get('text')]
            combined_text = '\n'.join(texts)
            return combined_text, 0.95
        return "", 0.0
    
    def extract_from_video(self, 
                           video_path: str,
                           region: Optional[SubtitleRegion] = None,
                           fps_sample: float = 2.0,
                           progress_callback: Optional[Callable[..., None]] = None
                           ) -> List[SubtitleEntry]:
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise RuntimeError(f"動画を開けません: {video_path}")
        fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        frame_interval = int(fps / fps_sample)
        if frame_interval < 1:
            frame_interval = 1
        frame_texts: List[Tuple[float, str]] = []
        frame_idx = 0
        processed = 0
        total_to_process = max(1, total_frames // frame_interval)
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            if frame_idx % frame_interval == 0:
                timestamp = frame_idx / fps
                try:
                    text, confidence = self.recognize_image(frame, region)
                    if text.strip():
                        frame_texts.append((timestamp, text))
                except Exception as e:
                    print(f"フレーム {frame_idx} の認識エラー: {e}")
                processed += 1
                if progress_callback:
                    try:
                        progress_callback(processed, total_to_process, timestamp)
                    except TypeError:
                        progress_callback(processed, total_to_process)
            frame_idx += 1
        cap.release()
        if self.enable_scroll_detection and frame_texts:
            detector = self._init_scroll_detector()
            result = detector.process_frames(frame_texts)
            subtitles = []
            for candidate in result.subtitles:
                subtitles.append(SubtitleEntry(
                    start_time=candidate.start_time,
                    end_time=candidate.end_time,
                    text=candidate.text,
                    confidence=candidate.confidence,
                    is_complete=candidate.is_complete
                ))
            return subtitles
        else:
            return self._merge_subtitles(frame_texts)
    
    def _merge_subtitles(self, frame_texts: List[Tuple[float, str]]) -> List[SubtitleEntry]:
        from difflib import SequenceMatcher
        if not frame_texts:
            return []
        subtitles = []
        current_text = ""
        start_time = 0.0
        end_time = 0.0
        for timestamp, text in frame_texts:
            if not current_text:
                current_text = text
                start_time = timestamp
                end_time = timestamp
            else:
                similarity = SequenceMatcher(None, current_text, text).ratio()
                if similarity > 0.8:
                    end_time = timestamp
                    if len(text) > len(current_text):
                        current_text = text
                else:
                    subtitles.append(SubtitleEntry(
                        start_time=start_time,
                        end_time=end_time,
                        text=current_text
                    ))
                    current_text = text
                    start_time = timestamp
                    end_time = timestamp
        if current_text:
            subtitles.append(SubtitleEntry(
                start_time=start_time,
                end_time=end_time,
                text=current_text
            ))
        return subtitles


def get_available_engines() -> List[dict]:
    """利用可能なOCRエンジンの情報を取得"""
    return [
        {'id': OCREngine.MEIKI_OCR.value, 'name': 'meikiOCR', 'type': 'local', 'description': '最高精度、日本語ゲーム特化', 'requires': 'なし'},
    ]


if __name__ == '__main__':
    print("=== 統合OCRエンジン ===\n")
    for engine in get_available_engines():
        print(f"  {engine['name']} ({engine['id']}): {engine['description']}")
