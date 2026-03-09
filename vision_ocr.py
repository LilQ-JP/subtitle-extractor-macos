"""
Vision AI OCR Module
Llama 3.2 Vision, LLaVA, moondreamを使用した画像からのテキスト認識

使用方法:
    # Ollamaを起動
    ollama serve
    
    # モデルをダウンロード
    ollama pull llama3.2-vision  # 高精度（8GB+ RAM）
    ollama pull llava:7b         # バランス型（6GB+ RAM）
    ollama pull moondream        # 軽量（4GB+ RAM）
"""

import requests
import base64
import json
from pathlib import Path
from typing import Optional, List, Dict, Any
from dataclasses import dataclass


@dataclass
class VisionOCRResult:
    """Vision OCRの結果"""
    text: str
    model: str
    confidence: float = 1.0  # Vision AIは信頼度を返さないため常に1.0


class VisionOCR:
    """Ollama Vision AIを使用したOCRエンジン"""
    
    SUPPORTED_MODELS = {
        'llama3.2-vision': {
            'name': 'Llama 3.2 Vision',
            'ram': '8GB+',
            'description': '高精度、日本語対応',
            'prompt_ja': 'この画像に表示されている日本語のテキストを正確に読み取ってください。テキストのみを出力し、説明は不要です。',
            'prompt_en': 'Read all text shown in this image accurately. Output only the text, no explanations.'
        },
        'llava:7b': {
            'name': 'LLaVA 7B',
            'ram': '6GB+',
            'description': 'バランス型、汎用',
            'prompt_ja': 'この画像のテキストを読んでください。テキストのみ出力してください。',
            'prompt_en': 'Read the text in this image. Output only the text.'
        },
        'llava:13b': {
            'name': 'LLaVA 13B',
            'ram': '10GB+',
            'description': '高精度版LLaVA',
            'prompt_ja': 'この画像に表示されている日本語のテキストを正確に読み取ってください。テキストのみを出力してください。',
            'prompt_en': 'Read all text shown in this image accurately. Output only the text.'
        },
        'moondream': {
            'name': 'Moondream',
            'ram': '4GB+',
            'description': '軽量、高速',
            'prompt_ja': 'What Japanese text is shown in this image? Output only the text.',
            'prompt_en': 'What text is shown in this image? Output only the text.'
        }
    }
    
    def __init__(self, model: str = 'llama3.2-vision', 
                 ollama_url: str = 'http://localhost:11434',
                 language: str = 'ja'):
        """
        Args:
            model: 使用するモデル名
            ollama_url: OllamaサーバーのURL
            language: 言語 ('ja' or 'en')
        """
        self.model = model
        self.ollama_url = ollama_url
        self.language = language
        
        if model not in self.SUPPORTED_MODELS:
            available = ', '.join(self.SUPPORTED_MODELS.keys())
            raise ValueError(f"サポートされていないモデル: {model}. 利用可能: {available}")
    
    def _encode_image(self, image_path: str) -> str:
        """画像をBase64エンコード"""
        with open(image_path, 'rb') as f:
            return base64.b64encode(f.read()).decode('utf-8')
    
    def _get_prompt(self) -> str:
        """言語に応じたプロンプトを取得"""
        model_info = self.SUPPORTED_MODELS[self.model]
        if self.language == 'ja':
            return model_info['prompt_ja']
        return model_info['prompt_en']
    
    def check_model_available(self) -> bool:
        """モデルが利用可能か確認"""
        try:
            response = requests.get(f"{self.ollama_url}/api/tags", timeout=5)
            if response.status_code == 200:
                models = response.json().get('models', [])
                model_names = [m['name'] for m in models]
                # モデル名の部分一致でチェック
                return any(self.model in name or name in self.model for name in model_names)
            return False
        except:
            return False
    
    def get_available_models(self) -> List[str]:
        """インストール済みのVisionモデル一覧を取得"""
        try:
            response = requests.get(f"{self.ollama_url}/api/tags", timeout=5)
            if response.status_code == 200:
                models = response.json().get('models', [])
                available = []
                for m in models:
                    name = m['name']
                    for supported in self.SUPPORTED_MODELS.keys():
                        if supported in name or name.startswith(supported.split(':')[0]):
                            available.append(name)
                            break
                return available
            return []
        except:
            return []
    
    def recognize(self, image_path: str, custom_prompt: Optional[str] = None) -> VisionOCRResult:
        """
        画像からテキストを認識
        
        Args:
            image_path: 画像ファイルのパス
            custom_prompt: カスタムプロンプト（オプション）
            
        Returns:
            VisionOCRResult: 認識結果
        """
        if not Path(image_path).exists():
            raise FileNotFoundError(f"画像が見つかりません: {image_path}")
        
        # 画像をBase64エンコード
        image_base64 = self._encode_image(image_path)
        
        # プロンプトを設定
        prompt = custom_prompt or self._get_prompt()
        
        # Ollama APIリクエスト
        payload = {
            "model": self.model,
            "prompt": prompt,
            "images": [image_base64],
            "stream": False,
            "options": {
                "temperature": 0.1,  # 低温度で一貫性のある出力
                "num_predict": 500   # 最大トークン数
            }
        }
        
        try:
            response = requests.post(
                f"{self.ollama_url}/api/generate",
                json=payload,
                timeout=120  # Vision AIは時間がかかる
            )
            
            if response.status_code == 200:
                result = response.json()
                text = result.get('response', '').strip()
                
                # 余分な説明を除去
                text = self._clean_response(text)
                
                return VisionOCRResult(
                    text=text,
                    model=self.model
                )
            else:
                error_msg = response.text
                raise RuntimeError(f"Ollama APIエラー: {error_msg}")
                
        except requests.exceptions.ConnectionError:
            raise RuntimeError("Ollamaサーバーに接続できません。'ollama serve'を実行してください。")
        except requests.exceptions.Timeout:
            raise RuntimeError("Ollama APIがタイムアウトしました。")
    
    def _clean_response(self, text: str) -> str:
        """AIの応答から余分な説明を除去"""
        # よくある前置きを除去
        prefixes_to_remove = [
            "The text in the image says:",
            "The text reads:",
            "The image shows:",
            "The Japanese text says:",
            "画像のテキスト:",
            "テキスト:",
        ]
        
        for prefix in prefixes_to_remove:
            if text.lower().startswith(prefix.lower()):
                text = text[len(prefix):].strip()
        
        # 引用符を除去
        if text.startswith('"') and text.endswith('"'):
            text = text[1:-1]
        if text.startswith("'") and text.endswith("'"):
            text = text[1:-1]
        if text.startswith("「") and text.endswith("」"):
            text = text[1:-1]
            
        return text.strip()
    
    def recognize_with_context(self, image_path: str, 
                               previous_text: Optional[str] = None,
                               next_text: Optional[str] = None) -> VisionOCRResult:
        """
        前後の文脈を考慮してテキストを認識（スクロール字幕向け）
        
        Args:
            image_path: 画像ファイルのパス
            previous_text: 前のフレームのテキスト
            next_text: 次のフレームのテキスト
            
        Returns:
            VisionOCRResult: 認識結果
        """
        context_prompt = self._get_prompt()
        
        if previous_text:
            context_prompt += f"\n\n参考: 前のフレームのテキストは「{previous_text}」でした。"
        
        return self.recognize(image_path, custom_prompt=context_prompt)


def list_supported_models() -> Dict[str, Dict[str, str]]:
    """サポートされているモデルの情報を取得"""
    return VisionOCR.SUPPORTED_MODELS


def check_ollama_running(url: str = 'http://localhost:11434') -> bool:
    """Ollamaサーバーが起動しているか確認"""
    try:
        response = requests.get(f"{url}/api/tags", timeout=5)
        return response.status_code == 200
    except:
        return False


# テスト用
if __name__ == '__main__':
    print("=== Vision OCR Module ===\n")
    
    # Ollamaの状態確認
    if check_ollama_running():
        print("✓ Ollamaサーバーが起動しています")
        
        # 利用可能なモデルを表示
        ocr = VisionOCR()
        available = ocr.get_available_models()
        print(f"\n利用可能なVisionモデル: {available}")
    else:
        print("✗ Ollamaサーバーが起動していません")
        print("  'ollama serve' を実行してください")
    
    print("\n=== サポートされているモデル ===")
    for model_id, info in list_supported_models().items():
        print(f"\n{info['name']} ({model_id})")
        print(f"  必要RAM: {info['ram']}")
        print(f"  説明: {info['description']}")
