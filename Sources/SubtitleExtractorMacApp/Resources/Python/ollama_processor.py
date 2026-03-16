"""
Ollama統合モジュール
AI校正と翻訳機能を提供
"""

import json
import os
import re
from typing import Optional, List, Dict, Tuple
from dataclasses import dataclass
from urllib import error as urllib_error
from urllib import request as urllib_request


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
                 ollama_url: Optional[str] = None,
                 timeout: int = 300,
                 custom_dictionary: str = ''):
        self.model = model
        self.ollama_url = self._normalize_ollama_url(
            ollama_url or os.environ.get("OLLAMA_HOST") or 'http://127.0.0.1:11434'
        )
        self.timeout = timeout
        self.custom_dictionary = custom_dictionary
        self._dict_entries: Dict[str, str] = self._parse_dictionary(custom_dictionary)

    def _normalize_ollama_url(self, url: str) -> str:
        normalized = str(url).strip()
        if not normalized:
            normalized = 'http://127.0.0.1:11434'
        if not normalized.startswith(('http://', 'https://')):
            normalized = f'http://{normalized}'
        return normalized.rstrip('/')
    
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

    def _request_json(
        self,
        path: str,
        payload: Optional[dict] = None,
        timeout: Optional[int] = None,
    ) -> dict:
        url = f"{self.ollama_url}{path}"
        body = None
        headers = {
            "Accept": "application/json",
        }

        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"

        request = urllib_request.Request(
            url,
            data=body,
            headers=headers,
            method="POST" if payload is not None else "GET",
        )

        try:
            with urllib_request.urlopen(request, timeout=timeout or self.timeout) as response:
                status_code = getattr(response, "status", response.getcode())
                response_text = response.read().decode("utf-8", errors="replace")
        except urllib_error.HTTPError as error:
            response_text = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"Ollama APIエラー ({error.code}): {response_text}") from error
        except urllib_error.URLError as error:
            reason = getattr(error, "reason", error)
            raise RuntimeError(f"Ollamaへの接続に失敗しました: {reason}") from error

        if status_code != 200:
            raise RuntimeError(f"Ollama APIエラー ({status_code}): {response_text}")

        try:
            return json.loads(response_text or "{}")
        except json.JSONDecodeError as error:
            raise RuntimeError(f"Ollamaの応答を解釈できませんでした: {response_text}") from error
    
    def check_available(self) -> bool:
        """Ollamaが利用可能か確認"""
        try:
            self._request_json("/api/tags", timeout=10)
            return True
        except Exception:
            return False
    
    def get_available_models(self) -> List[str]:
        """利用可能なモデル一覧を取得"""
        try:
            payload = self._request_json("/api/tags", timeout=10)
            models = payload.get('models', [])
            return [m['name'] for m in models]
        except Exception:
            return []

    def _generate(
        self,
        prompt: str,
        num_predict: int = 500,
        response_format: Optional[str] = None,
        stop: Optional[List[str]] = None,
        request_timeout: Optional[int] = None,
        images: Optional[List[str]] = None,
    ) -> str:
        """Ollamaでテキスト生成"""
        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "keep_alive": "15m",
            "options": {
                "temperature": 0.1,
                "num_predict": num_predict,
                "num_ctx": 4096,
            }
        }
        if stop:
            payload["options"]["stop"] = stop
        if response_format:
            payload["format"] = response_format
        if images:
            payload["images"] = images

        response = self._request_json(
            "/api/generate",
            payload=payload,
            timeout=request_timeout or self.timeout,
        )
        return str(response.get('response', '')).strip()

    def _language_name(self, language_code: str) -> str:
        return {
            "ja": "Japanese",
            "en": "English",
            "zh": "Chinese",
            "ko": "Korean",
        }.get(language_code, "Japanese")

    def _compact_context_text(self, text: str, max_length: int = 96) -> str:
        normalized = " ".join(str(text or "").strip().split())
        if len(normalized) <= max_length:
            return normalized
        return normalized[: max_length - 1].rstrip() + "…"

    def _context_timeout(
        self,
        text: str,
        previous_context: Optional[List[Tuple[str, str]]] = None,
        next_context: Optional[List[str]] = None,
    ) -> int:
        previous_context = previous_context or []
        next_context = next_context or []
        payload_length = len(str(text).strip())
        payload_length += sum(len(source) + len(translated) for source, translated in previous_context)
        payload_length += sum(len(item) for item in next_context)
        timeout = int(8 + (payload_length / 70))
        return max(10, min(self.timeout, timeout))

    def _build_translation_prompt(
        self,
        text: str,
        source_lang: str,
        target_lang: str,
        previous_context: Optional[List[Tuple[str, str]]] = None,
        next_context: Optional[List[str]] = None,
        preserve_slang: bool = True,
    ) -> str:
        source_name = self._language_name(source_lang)
        target_name = self._language_name(target_lang)
        dict_section = self._get_dict_prompt()
        previous_context = previous_context or []
        next_context = next_context or []

        prompt_parts = [
            f"You are translating one subtitle line from {source_name} to {target_name}.",
            "Translate ONLY the CURRENT line.",
            "Use nearby lines only to understand omitted subjects, jokes, slang, and story flow.",
            "Keep the translation concise and natural for subtitles.",
        ]
        if preserve_slang:
            prompt_parts.extend([
                f"Preserve slang, teasing, gamer talk, memes, and casual tone naturally in {target_name}.",
                "Keep the same character voice and emotional flow.",
            ])
        else:
            prompt_parts.append(f"Favor clear, natural subtitle phrasing in {target_name}.")
        prompt_parts.extend([
            "Never explain the translation.",
            f"Output only the final {target_name} subtitle line.",
        ])

        if dict_section:
            prompt_parts.append(dict_section.strip())

        if previous_context:
            previous_lines = []
            for index, (source, translated) in enumerate(previous_context, start=1):
                previous_lines.append(
                    f"{index}. Source: {self._compact_context_text(source)}\n"
                    f"   Translation: {self._compact_context_text(translated)}"
                )
            prompt_parts.append("Previous lines:\n" + "\n".join(previous_lines))

        if next_context:
            next_lines = []
            for index, source in enumerate(next_context, start=1):
                next_lines.append(f"{index}. Source: {self._compact_context_text(source)}")
            prompt_parts.append("Upcoming lines:\n" + "\n".join(next_lines))

        prompt_parts.append(f"CURRENT {source_name}: {text}")
        prompt_parts.append(f"{target_name}:")
        return "\n\n".join(prompt_parts)

    def _translate_with_retry(
        self,
        text: str,
        source_lang: str,
        target_lang: str,
        retries: int = 1,
        request_timeout: Optional[int] = None,
        previous_context: Optional[List[Tuple[str, str]]] = None,
        next_context: Optional[List[str]] = None,
        preserve_slang: bool = True,
    ) -> str:
        normalized = str(text).strip()
        if not normalized:
            return ""

        last_error: Optional[Exception] = None
        for _ in range(max(1, retries)):
            try:
                return self.translate(
                    normalized,
                    source_lang=source_lang,
                    target_lang=target_lang,
                    request_timeout=request_timeout,
                    previous_context=previous_context,
                    next_context=next_context,
                    preserve_slang=preserve_slang,
                )
            except Exception as error:
                last_error = error
        if last_error is not None:
            return normalized
        return normalized

    def _single_timeout(self, text: str) -> int:
        normalized = str(text).strip()
        timeout = int(6 + (len(normalized) / 48))
        return max(8, min(self.timeout, timeout))

    def _contains_language_script(self, text: str, language_code: str) -> bool:
        if not text:
            return False
        patterns = {
            "ja": r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]",
            "zh": r"[\u3400-\u4dbf\u4e00-\u9fff]",
            "ko": r"[\u1100-\u11ff\u3130-\u318f\uac00-\ud7af]",
            "en": r"[A-Za-z]",
        }
        pattern = patterns.get(language_code)
        if not pattern:
            return False
        return re.search(pattern, text) is not None

    def _needs_translation_retry(
        self,
        source_text: str,
        translated_text: str,
        source_lang: str,
        target_lang: str,
    ) -> bool:
        source_clean = str(source_text or "").strip()
        translated_clean = str(translated_text or "").strip()
        if source_lang == target_lang:
            return False
        if not translated_clean or translated_clean == source_clean:
            return True
        if source_lang in {"ja", "zh", "ko"} and self._contains_language_script(translated_clean, source_lang):
            return True
        return False

    def translate_batch(
        self,
        texts: List[str],
        source_lang: str = "ja",
        target_lang: str = "en",
        use_context: bool = True,
        context_window: int = 2,
        preserve_slang: bool = True,
        progress_callback=None,
    ) -> List[str]:
        if not texts:
            return []

        total = len(texts)
        normalized_texts = [str(text or "").strip() for text in texts]
        translated_texts: List[str] = []
        translation_cache: Dict[Tuple, str] = {}
        completed = 0

        for index, normalized_text in enumerate(normalized_texts):
            if progress_callback:
                progress_callback(completed, total, normalized_text)

            previous_context: List[Tuple[str, str]] = []
            next_context: List[str] = []
            if use_context and context_window > 0:
                previous_context = [
                    (normalized_texts[context_index], translated_texts[context_index])
                    for context_index in range(max(0, index - context_window), index)
                    if normalized_texts[context_index]
                ]
                next_context = [
                    normalized_texts[context_index]
                    for context_index in range(index + 1, min(total, index + 1 + context_window))
                    if normalized_texts[context_index]
                ]

            cache_key = (
                normalized_text,
                tuple(previous_context),
                tuple(next_context),
                source_lang,
                target_lang,
                use_context,
                preserve_slang,
            )
            cached = translation_cache.get(cache_key)
            if cached is None:
                if normalized_text:
                    cached = self._translate_with_retry(
                        normalized_text,
                        source_lang=source_lang,
                        target_lang=target_lang,
                        retries=1,
                        request_timeout=self._context_timeout(
                            normalized_text,
                            previous_context=previous_context,
                            next_context=next_context,
                        ) if use_context else self._single_timeout(normalized_text),
                        previous_context=previous_context,
                        next_context=next_context,
                        preserve_slang=preserve_slang,
                    )
                else:
                    cached = ""
                translation_cache[cache_key] = cached

            translated_texts.append(cached)
            completed += 1
            if progress_callback:
                progress_callback(completed, total, normalized_text)

        return translated_texts
    
    def correct_ocr(self, text: str, source_lang: str = "ja") -> ProcessResult:
        """OCR誤認識を校正"""
        if not text.strip():
            return ProcessResult(original=text, processed=text, success=True)

        source_name = self._language_name(source_lang)
        dict_section = self._get_dict_prompt()
        prompt = f"""You are cleaning OCR subtitle text in {source_name}.
Return only corrected {source_name} subtitle text.

Rules:
- Keep the same language: {source_name}
- Remove emoji, decorative symbols, UI scraps, and obvious OCR garbage
- Fix spacing and obvious OCR mistakes
- Preserve the original meaning
- Do not translate
- Output only the corrected subtitle text{dict_section}

Input: {text}
Output:"""
        
        try:
            result = self._generate(
                prompt,
                num_predict=96,
                stop=[
                    "\n\n",
                    "\nInput:",
                    "\nOutput:",
                    "\nJapanese:",
                    "\nEnglish:",
                    "\nChinese:",
                    "\nKorean:",
                ],
                request_timeout=self._single_timeout(text),
            )
            result = self._clean_response(result, preserve_multiline=True)
            return ProcessResult(original=text, processed=result, success=True)
        except Exception as e:
            return ProcessResult(original=text, processed=text, success=False, error=str(e))

    def recognize_subtitle_images(
        self,
        images: List[str],
        source_lang: str = "ja",
        hint_text: str = "",
    ) -> ProcessResult:
        valid_images = [image for image in images if str(image).strip()]
        if not valid_images:
            return ProcessResult(original="", processed="", success=False, error="画像が渡されていません。")

        source_name = self._language_name(source_lang)
        hint_section = ""
        normalized_hint = str(hint_text or "").strip()
        if normalized_hint:
            hint_section = (
                "\nPossible previous OCR draft (use only as a hint if the image matches): "
                f"{normalized_hint}\n"
            )

        language_specific_rule = ""
        if source_lang == "ko":
            language_specific_rule = (
                "\n- Prefer natural Hangul spelling and spacing"
                "\n- Remove stray Latin letters or symbols unless they are clearly part of the subtitle"
            )
        elif source_lang == "zh":
            language_specific_rule = (
                "\n- Prefer clear Chinese characters and natural punctuation"
                "\n- Remove UI scraps, kana, or stray Hangul unless they are clearly part of the subtitle"
            )
        elif source_lang == "en":
            language_specific_rule = (
                "\n- Prefer readable English words with normal spacing"
                "\n- Remove decorative symbols or isolated non-Latin characters unless they clearly belong to the subtitle"
            )

        prompt = f"""Read the subtitle text that appears in these cropped subtitle images.
Return only the subtitle text in {source_name}.

Rules:
- Use the images as the source of truth
- Compare all images and keep the text that appears consistently
- Ignore emoji, icons, UI scraps, buttons, and decorative marks
- Fix obvious OCR mistakes only if the image clearly supports it
- Keep the original language: {source_name}
- Output only the final subtitle text{language_specific_rule}{hint_section}"""

        try:
            result = self._generate(
                prompt,
                num_predict=96,
                stop=[
                    "\n\n",
                    "\nPossible previous OCR draft:",
                    "\nSubtitle:",
                    "\nOutput:",
                    "\nJapanese:",
                    "\nEnglish:",
                    "\nChinese:",
                    "\nKorean:",
                ],
                request_timeout=max(18, min(self.timeout, 60)),
                images=valid_images,
            )
            result = self._clean_response(result, preserve_multiline=True)
            return ProcessResult(original=normalized_hint, processed=result, success=bool(result))
        except Exception as e:
            return ProcessResult(original=normalized_hint, processed=normalized_hint, success=False, error=str(e))
    
    def translate_to_english(self, text: str, request_timeout: Optional[int] = None) -> ProcessResult:
        """日本語を英語に翻訳"""
        if not text.strip():
            return ProcessResult(original=text, processed=text, success=True)
        
        dict_section = self._get_dict_prompt()
        prompt = f"""Translate the following Japanese text to English. Output only the translation.{dict_section}
Japanese: {text}

English:"""
        
        try:
            result = self._generate(
                prompt,
                num_predict=64,
                stop=["\n\n", "\nJapanese:", "\nEnglish:"],
                request_timeout=request_timeout,
            )
            result = self._clean_response(result, preserve_multiline=True)
            return ProcessResult(original=text, processed=result, success=True)
        except Exception as e:
            return ProcessResult(original=text, processed=text, success=False, error=str(e))
    
    def translate(
        self,
        text: str,
        source_lang: str = "ja",
        target_lang: str = "en",
        request_timeout: Optional[int] = None,
        previous_context: Optional[List[Tuple[str, str]]] = None,
        next_context: Optional[List[str]] = None,
        preserve_slang: bool = True,
    ) -> str:
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

        source_name = self._language_name(source_lang)
        target_name = self._language_name(target_lang)
        prompt = self._build_translation_prompt(
            text=text,
            source_lang=source_lang,
            target_lang=target_lang,
            previous_context=previous_context,
            next_context=next_context,
            preserve_slang=preserve_slang,
        )

        try:
            result = self._generate(
                prompt,
                num_predict=72,
                stop=[
                    "\n\n",
                    "\nJapanese:",
                    "\nEnglish:",
                    "\nChinese:",
                    "\nKorean:",
                ],
                request_timeout=request_timeout,
            )
            result = self._clean_response(result, preserve_multiline=True)
            if self._needs_translation_retry(text, result, source_lang, target_lang):
                strict_prompt = self._build_translation_prompt(
                    text=text,
                    source_lang=source_lang,
                    target_lang=target_lang,
                    previous_context=previous_context,
                    next_context=next_context,
                    preserve_slang=preserve_slang,
                ) + "\n\nRules:\n- Do not repeat the original line.\n- Use the surrounding lines to resolve implied meaning.\n- Return only the translated current subtitle."
                result = self._generate(
                    strict_prompt,
                    num_predict=72,
                    stop=[
                        "\n\n",
                        "\nJapanese:",
                        "\nEnglish:",
                        "\nChinese:",
                        "\nKorean:",
                    ],
                    request_timeout=request_timeout,
                )
                result = self._clean_response(result, preserve_multiline=True)
            if self._needs_translation_retry(text, result, source_lang, target_lang):
                hard_prompt = f"""Translate this subtitle from {source_name} to {target_name}.

Rules:
- Output only {target_name}
- Do not leave any {source_name} words or characters
- Use nearby lines to resolve slang and implied meaning
- Keep it short like a subtitle

Subtitle: {text}
Translation:"""
                result = self._generate(
                    hard_prompt,
                    num_predict=72,
                    stop=[
                        "\n\n",
                        "\nSubtitle:",
                        "\nTranslation:",
                        "\nJapanese:",
                        "\nEnglish:",
                        "\nChinese:",
                        "\nKorean:",
                    ],
                    request_timeout=request_timeout,
                )
                result = self._clean_response(result, preserve_multiline=True)
            return result
        except Exception as e:
            raise RuntimeError(f"翻訳エラー: {e}")

    def _clean_response(self, text: str, preserve_multiline: bool = False) -> str:
        """応答をクリーニング"""
        text = text.strip()
        if text.startswith("```"):
            lines = [line for line in text.splitlines() if not line.strip().startswith("```")]
            text = "\n".join(lines).strip()
        if text.startswith('"') and text.endswith('"'):
            text = text[1:-1]
        if text.startswith("'") and text.endswith("'"):
            text = text[1:-1]
        if text.startswith("「") and text.endswith("」"):
            text = text[1:-1]
        lines = [line.rstrip() for line in text.split('\n')]
        if preserve_multiline:
            text = "\n".join(line for line in lines if line.strip()).strip()
        elif lines:
            text = next((line.strip() for line in lines if line.strip()), "").strip()
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
                result = self.correct_ocr(text, source_lang="ja")
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
