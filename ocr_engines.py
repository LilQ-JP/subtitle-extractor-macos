"""
OCRエンジンモジュール
対応エンジン:
- meikiOCR (ローカル、無料、日本語ゲーム字幕特化、最高精度)
"""

import os
from dataclasses import dataclass
from typing import Optional, List, Tuple
from abc import ABC, abstractmethod

import cv2
import numpy as np
from PIL import Image


@dataclass
class OCRResult:
    """OCR結果"""
    text: str
    confidence: float = 1.0
    bbox: Optional[Tuple[int, int, int, int]] = None  # x, y, w, h


class BaseOCREngine(ABC):
    """OCRエンジンの基底クラス"""
    
    @property
    @abstractmethod
    def name(self) -> str:
        """エンジン名"""
        pass
    
    @property
    @abstractmethod
    def description(self) -> str:
        """エンジンの説明"""
        pass
    
    @property
    @abstractmethod
    def is_local(self) -> bool:
        """ローカル実行かどうか"""
        pass
    
    @property
    @abstractmethod
    def requires_api_key(self) -> bool:
        """APIキーが必要かどうか"""
        pass
    
    @abstractmethod
    def recognize(self, image: np.ndarray, language: str = "ja") -> OCRResult:
        """画像からテキストを認識"""
        pass


class MeikiOCREngine(BaseOCREngine):
    """meikiOCR エンジン（日本語ゲーム字幕特化）"""
    
    def __init__(self):
        self._ocr = None
    
    @property
    def name(self) -> str:
        return "meikiOCR"
    
    @property
    def description(self) -> str:
        return "日本語ゲーム字幕特化OCR（無料・ローカル・最高精度）"
    
    @property
    def is_local(self) -> bool:
        return True
    
    @property
    def requires_api_key(self) -> bool:
        return False
    
    def _get_ocr(self):
        if self._ocr is None:
            try:
                from meikiocr import MeikiOCR
                self._ocr = MeikiOCR()
            except ImportError:
                raise ImportError("meikiOCRがインストールされていません。pip install meikiocr を実行してください。")
        return self._ocr
    
    def recognize(self, image: np.ndarray, language: str = "ja") -> OCRResult:
        ocr = self._get_ocr()
        
        try:
            # meikiOCRで認識（画像を直接渡す）
            results = ocr.run_ocr(image)
            
            # 結果からテキストを抽出
            if results:
                texts = [line['text'] for line in results if line.get('text')]
                text = '\n'.join(texts)
                return OCRResult(text=text, confidence=0.95)
            else:
                return OCRResult(text="", confidence=0.0)
        except Exception as e:
            print(f"meikiOCR error: {e}")
            return OCRResult(text="", confidence=0.0)


# エンジンのレジストリ
AVAILABLE_ENGINES = {
    "meikiocr": MeikiOCREngine,
}

ENGINE_INFO = {
    "meikiocr": {
        "name": "meikiOCR",
        "description": "日本語ゲーム字幕特化（無料・ローカル・最高精度）",
        "is_local": True,
        "requires_api_key": False,
    },
}


def get_engine(engine_id: str, api_key: str = "") -> BaseOCREngine:
    """エンジンIDからエンジンインスタンスを取得"""
    if engine_id not in AVAILABLE_ENGINES:
        raise ValueError(f"Unknown engine: {engine_id}")
    
    engine_class = AVAILABLE_ENGINES[engine_id]
    return engine_class()


def list_engines() -> List[dict]:
    """利用可能なエンジンの一覧を取得"""
    return [
        {"id": engine_id, **info}
        for engine_id, info in ENGINE_INFO.items()
    ]
