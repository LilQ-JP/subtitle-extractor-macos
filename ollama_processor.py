"""
Ollama統合モジュール
AI校正と翻訳機能を提供
"""

import requests
import json
from typing import Optional, List, Dict
from dataclasses import dataclass


@dataclass
class ProcessResult:
    """処理結果"""
    original: str
    processed: str
    success: bool
    error: Optional[str] = None


class OllamaProcessor:
    """Ollamaを使用したテキスト処理"""
    
    def __init__(self, 
                 model: str = 'gemma3:4b',
                 ollama_url: str = 'http://localhost:11434',
                 timeout: int = 120,
                 custom_dictionary: str = ''):
        self.model = model
        self.ollama_url = ollama_url
        self.timeout = timeout
        self.custom_dictionary = custom_dictionary
        self._dict_entries: Dict[str, str] = self._parse_dictionary(custom_dictionary)
    
    def _parse_dictionary(self, dict_text: str) -> Dict[str, str]:
        """カスタム辞書をパース"""
        entries = {}
        if not dict_text:
            return entries
        for line in dict_text.strip().split('\n'):
            line = line.strip()
            if '=' in line:
                parts = line.split('=', 1)
                if len(parts) == 2 and parts[0].strip() and parts[1].strip():
                    entries[parts[0].strip()] = parts[1].strip()
        return entries
    
    def _get_dict_prompt(self) -> str:
        """辞書情報をプロンプテキストに変換"""
        if not self._dict_entries:
            return ""
        lines = []
        for src, dst in self._dict_entries.items():
            lines.append(f"  {src} → {dst}")
        return "\n※ 以下の用語は必ず指定された翻訳を使ってください:\n" + "\n".join(lines) + "\n"
    
    def check_available(self) -> bool:
        """Ollamaが利用可能か確認"""
        try:
            response = requests.get(f"{self.ollama_url}/api/tags", timeout=5)
            return response.status_code == 200
        except:
            return False
    
    def get_available_models(self) -> List[str]:
        """利用可能なモデル一覧を取得"""
        try:
            response = requests.get(f"{self.ollama_url}/api/tags", timeout=5)
            if response.status_code == 200:
                models = response.json().get('models', [])
                return [m['name'] for m in models]
            return []
        except:
            return []
    
    def _generate(self, prompt: str) -> str:
        """Ollamaでテキスト生成"""
        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.3,
                "num_predict": 500
            }
        }
        
        response = requests.post(
            f"{self.ollama_url}/api/generate",
            json=payload,
            timeout=self.timeout
        )
        
        if response.status_code == 200:
            return response.json().get('response', '').strip()
        else:
            raise RuntimeError(f"Ollama APIエラー: {response.text}")
    
    def correct_ocr(self, text: str) -> ProcessResult:
        """OCR誤認識を校正"""
        if not text.strip():
            return ProcessResult(original=text, processed=text, success=True)
        
        dict_section = self._get_dict_prompt()
        prompt = f"""以下はOCRで読み取った日本語テキストです。誤認識を修正して正しい日本語に直してください。

入力: {text}

ルール:
- 誤字脱字を修正
- 意味が通るように修正
- 元の意味を変えない
- 修正後のテキストのみを出力（説明不要）{dict_section}
出力:"""
        
        try:
            result = self._generate(prompt)
            result = self._clean_response(result)
            return ProcessResult(original=text, processed=result, success=True)
        except Exception as e:
            return ProcessResult(original=text, processed=text, success=False, error=str(e))
    
    def translate_to_english(self, text: str) -> ProcessResult:
        """日本語を英語に翻訳"""
        if not text.strip():
            return ProcessResult(original=text, processed=text, success=True)
        
        dict_section = self._get_dict_prompt()
        prompt = f"""Translate the following Japanese text to English. Output only the translation.{dict_section}
Japanese: {text}

English:"""
        
        try:
            result = self._generate(prompt)
            result = self._clean_response(result)
            return ProcessResult(original=text, processed=result, success=True)
        except Exception as e:
            return ProcessResult(original=text, processed=text, success=False, error=str(e))
    
    def translate(self, text: str, source_lang: str = "ja", target_lang: str = "en") -> str:
        """テキストを翻訳
        
        Args:
            text: 翻訳するテキスト
            source_lang: 翻訳元言語 (ja, en, zh, ko)
            target_lang: 翻訳先言語 (en, ja, zh, ko)
        
        Returns:
            翻訳されたテキスト
        """
        if not text.strip():
            return text
        
        lang_names = {
            "ja": "Japanese",
            "en": "English",
            "zh": "Chinese",
            "ko": "Korean"
        }
        
        source_name = lang_names.get(source_lang, "Japanese")
        target_name = lang_names.get(target_lang, "English")
        
        dict_section = self._get_dict_prompt()
        prompt = f"""Translate the following {source_name} text to {target_name}. Output only the translation, nothing else.{dict_section}
{source_name}: {text}

{target_name}:"""
        
        try:
            result = self._generate(prompt)
            result = self._clean_response(result)
            return result
        except Exception as e:
            raise RuntimeError(f"翻訳エラー: {e}")
    
    def _clean_response(self, text: str) -> str:
        """応答をクリーニング"""
        text = text.strip()
        if text.startswith('"') and text.endswith('"'):
            text = text[1:-1]
        if text.startswith("'") and text.endswith("'"):
            text = text[1:-1]
        if text.startswith("「") and text.endswith("」"):
            text = text[1:-1]
        lines = text.split('\n')
        if lines:
            text = lines[0].strip()
        return text
    
    def process_subtitles(self, 
                          subtitles: List[dict],
                          correct: bool = True,
                          translate: bool = False,
                          progress_callback=None) -> List[dict]:
        """字幕リストを一括処理"""
        results = []
        total = len(subtitles)
        
        for i, sub in enumerate(subtitles):
            text = sub.get('text', '')
            processed = text
            translated = ''
            
            if correct and text:
                result = self.correct_ocr(text)
                if result.success:
                    processed = result.processed
            
            if translate and processed:
                result = self.translate_to_english(processed)
                if result.success:
                    translated = result.processed
            
            new_sub = sub.copy()
            new_sub['text'] = processed
            new_sub['translated'] = translated
            results.append(new_sub)
            
            if progress_callback:
                progress_callback(i + 1, total)
        
        return results


if __name__ == '__main__':
    print("=== Ollama Processor ===")
    processor = OllamaProcessor()
    if processor.check_available():
        print("Ollama is available")
        print(f"Models: {processor.get_available_models()}")
    else:
        print("Ollama is not available")
