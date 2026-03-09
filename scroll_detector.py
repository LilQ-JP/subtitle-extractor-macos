"""
スクロール字幕検出モジュール
横からスクロールして表示される字幕の完全表示フレームを検出

機能:
1. 連続フレームの字幕テキストを比較
2. 文字数が増加中（スクロール中）のフレームを検出
3. 文字数が安定した（完全表示）フレームのみを採用
4. 同じ字幕の複数認識から最も長いテキストを選択
"""

from dataclasses import dataclass, field
from typing import List, Optional, Tuple
from difflib import SequenceMatcher
import re


@dataclass
class SubtitleCandidate:
    """字幕候補"""
    text: str
    start_time: float
    end_time: float
    frame_count: int = 1
    is_complete: bool = False
    confidence: float = 1.0
    
    def merge_with(self, other: 'SubtitleCandidate') -> 'SubtitleCandidate':
        """別の候補とマージ（より長いテキストを採用）"""
        if len(other.text) > len(self.text):
            best_text = other.text
        else:
            best_text = self.text
            
        return SubtitleCandidate(
            text=best_text,
            start_time=min(self.start_time, other.start_time),
            end_time=max(self.end_time, other.end_time),
            frame_count=self.frame_count + other.frame_count,
            is_complete=True,
            confidence=max(self.confidence, other.confidence)
        )


@dataclass
class ScrollDetectionResult:
    """スクロール検出結果"""
    subtitles: List[SubtitleCandidate]
    total_frames_processed: int
    scroll_frames_skipped: int
    complete_frames_used: int


class ScrollSubtitleDetector:
    """スクロール字幕検出器"""

    DUPLICATE_MERGE_GAP = 1.0
    
    def __init__(self, 
                 similarity_threshold: float = 0.6,
                 min_text_length: int = 2,
                 stability_frames: int = 2):
        """
        Args:
            similarity_threshold: 同じ字幕と判定する類似度閾値
            min_text_length: 最小テキスト長
            stability_frames: 完全表示と判定するための安定フレーム数
        """
        self.similarity_threshold = similarity_threshold
        self.min_text_length = min_text_length
        self.stability_frames = stability_frames
    
    def _calculate_similarity(self, text1: str, text2: str) -> float:
        """2つのテキストの類似度を計算"""
        if not text1 or not text2:
            return 0.0
        return SequenceMatcher(None, text1, text2).ratio()
    
    def _is_scrolling(self, prev_text: str, curr_text: str) -> bool:
        """
        スクロール中かどうかを判定
        
        スクロール中の特徴:
        - 前のテキストが現在のテキストの部分文字列
        - 文字数が増加している
        - 類似度が高いが完全一致ではない
        """
        if not prev_text or not curr_text:
            return False
        
        # 前のテキストが現在のテキストの先頭部分と一致
        if curr_text.startswith(prev_text) and len(curr_text) > len(prev_text):
            return True
        
        # 前のテキストが現在のテキストの部分文字列
        if prev_text in curr_text and len(curr_text) > len(prev_text):
            return True
        
        # 高い類似度だが文字数が増加
        similarity = self._calculate_similarity(prev_text, curr_text)
        if similarity > 0.7 and len(curr_text) > len(prev_text):
            return True
        
        return False
    
    def _is_same_subtitle(self, text1: str, text2: str) -> bool:
        """同じ字幕かどうかを判定"""
        if not text1 or not text2:
            return False
        
        # 完全一致
        if text1 == text2:
            return True
        
        # 一方が他方の部分文字列
        if text1 in text2 or text2 in text1:
            return True
        
        # 類似度が閾値以上
        similarity = self._calculate_similarity(text1, text2)
        return similarity >= self.similarity_threshold
    
    def _clean_text(self, text: str) -> str:
        """テキストをクリーニング"""
        if not text:
            return ""
        
        # 空白を正規化
        text = ' '.join(text.split())
        
        # 制御文字を除去
        text = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', text)
        
        return text.strip()
    
    def process_frames(self, 
                       frame_texts: List[Tuple[float, str]]) -> ScrollDetectionResult:
        """
        フレームのテキストリストを処理してスクロール字幕を検出
        
        Args:
            frame_texts: [(timestamp, text), ...] のリスト
            
        Returns:
            ScrollDetectionResult: 検出結果
        """
        if not frame_texts:
            return ScrollDetectionResult(
                subtitles=[],
                total_frames_processed=0,
                scroll_frames_skipped=0,
                complete_frames_used=0
            )
        
        subtitles: List[SubtitleCandidate] = []
        current_candidate: Optional[SubtitleCandidate] = None
        prev_text = ""
        scroll_frames = 0
        complete_frames = 0
        stable_count = 0
        
        for timestamp, raw_text in frame_texts:
            text = self._clean_text(raw_text)
            
            # 空テキストはスキップ
            if len(text) < self.min_text_length:
                # 現在の候補があれば確定
                if current_candidate and current_candidate.frame_count >= self.stability_frames:
                    current_candidate.is_complete = True
                    subtitles.append(current_candidate)
                current_candidate = None
                prev_text = ""
                continue
            
            # スクロール中かチェック
            if self._is_scrolling(prev_text, text):
                scroll_frames += 1
                # スクロール中は候補を更新するが確定しない
                if current_candidate:
                    current_candidate.text = text
                    current_candidate.end_time = timestamp
                    current_candidate.frame_count += 1
                else:
                    current_candidate = SubtitleCandidate(
                        text=text,
                        start_time=timestamp,
                        end_time=timestamp
                    )
                prev_text = text
                stable_count = 0
                continue
            
            # 同じ字幕が続いているかチェック
            if current_candidate and self._is_same_subtitle(current_candidate.text, text):
                # より長いテキストを採用
                if len(text) >= len(current_candidate.text):
                    current_candidate.text = text
                current_candidate.end_time = timestamp
                current_candidate.frame_count += 1
                stable_count += 1
                
                # 安定フレーム数に達したら完全表示と判定
                if stable_count >= self.stability_frames:
                    current_candidate.is_complete = True
                    complete_frames += 1
            else:
                # 新しい字幕
                # 前の候補があれば確定
                if current_candidate and current_candidate.frame_count >= 1:
                    if current_candidate.is_complete or current_candidate.frame_count >= self.stability_frames:
                        subtitles.append(current_candidate)
                        complete_frames += 1
                
                # 新しい候補を開始
                current_candidate = SubtitleCandidate(
                    text=text,
                    start_time=timestamp,
                    end_time=timestamp
                )
                stable_count = 1
            
            prev_text = text
        
        # 最後の候補を処理
        if current_candidate and current_candidate.frame_count >= 1:
            subtitles.append(current_candidate)
            if current_candidate.is_complete:
                complete_frames += 1
        
        # 重複を除去してマージ
        merged_subtitles = self._merge_duplicates(subtitles)
        
        return ScrollDetectionResult(
            subtitles=merged_subtitles,
            total_frames_processed=len(frame_texts),
            scroll_frames_skipped=scroll_frames,
            complete_frames_used=complete_frames
        )
    
    def _merge_duplicates(self, 
                          subtitles: List[SubtitleCandidate]) -> List[SubtitleCandidate]:
        """重複する字幕をマージ"""
        if not subtitles:
            return []

        sorted_subtitles = sorted(subtitles, key=lambda x: x.start_time)
        merged: List[SubtitleCandidate] = [sorted_subtitles[0]]

        for sub in sorted_subtitles[1:]:
            previous = merged[-1]
            gap = sub.start_time - previous.end_time

            # 隣接した同一字幕のみマージし、別シーンの同文字幕が連結されるのを防ぐ
            if gap >= 0 and gap <= self.DUPLICATE_MERGE_GAP and self._is_same_subtitle(previous.text, sub.text):
                merged[-1] = previous.merge_with(sub)
            else:
                merged.append(sub)

        return merged
    
    def filter_incomplete(self, 
                          subtitles: List[SubtitleCandidate],
                          keep_all: bool = False) -> List[SubtitleCandidate]:
        """
        不完全な字幕をフィルタリング
        
        Args:
            subtitles: 字幕リスト
            keep_all: Trueの場合、すべての字幕を保持
            
        Returns:
            フィルタリングされた字幕リスト
        """
        if keep_all:
            return subtitles
        
        return [s for s in subtitles if s.is_complete or s.frame_count >= self.stability_frames]


class SmartSubtitleMerger:
    """
    スマート字幕マージャー
    OCRの誤認識を考慮して、複数の認識結果から最適なテキストを選択
    """
    
    def __init__(self, min_confidence: float = 0.5):
        self.min_confidence = min_confidence
    
    def select_best_text(self, candidates: List[str]) -> str:
        """
        複数の候補から最適なテキストを選択
        
        選択基準:
        1. 最も長いテキスト（完全表示の可能性が高い）
        2. 最も頻出するテキスト（認識が安定している）
        """
        if not candidates:
            return ""
        
        if len(candidates) == 1:
            return candidates[0]
        
        # 文字数でソート（降順）
        sorted_by_length = sorted(candidates, key=len, reverse=True)
        
        # 最長のテキストを返す
        return sorted_by_length[0]
    
    def merge_similar_texts(self, texts: List[str], 
                           threshold: float = 0.8) -> List[str]:
        """類似テキストをマージ"""
        if not texts:
            return []
        
        merged = []
        used = set()
        
        for i, text in enumerate(texts):
            if i in used:
                continue
            
            similar_group = [text]
            
            for j, other in enumerate(texts[i+1:], start=i+1):
                if j in used:
                    continue
                
                similarity = SequenceMatcher(None, text, other).ratio()
                if similarity >= threshold:
                    similar_group.append(other)
                    used.add(j)
            
            # グループから最適なテキストを選択
            best = self.select_best_text(similar_group)
            merged.append(best)
            used.add(i)
        
        return merged


# テスト用
if __name__ == '__main__':
    print("=== スクロール字幕検出テスト ===\n")
    
    # テストデータ（スクロール字幕をシミュレート）
    test_frames = [
        (0.0, "この"),
        (0.5, "この世の"),
        (1.0, "この世の中、"),
        (1.5, "この世の中、もう"),
        (2.0, "この世の中、もう何も"),
        (2.5, "この世の中、もう何も信じ"),
        (3.0, "この世の中、もう何も信じられない"),
        (3.5, "この世の中、もう何も信じられない"),
        (4.0, "この世の中、もう何も信じられない"),
        (4.5, ""),
        (5.0, "次の"),
        (5.5, "次のセリフ"),
        (6.0, "次のセリフです"),
        (6.5, "次のセリフです"),
    ]
    
    detector = ScrollSubtitleDetector(
        similarity_threshold=0.6,
        stability_frames=2
    )
    
    result = detector.process_frames(test_frames)
    
    print(f"処理フレーム数: {result.total_frames_processed}")
    print(f"スクロールフレーム: {result.scroll_frames_skipped}")
    print(f"完全表示フレーム: {result.complete_frames_used}")
    print(f"\n検出された字幕:")
    
    for sub in result.subtitles:
        status = "✓ 完全" if sub.is_complete else "△ 部分"
        print(f"  [{sub.start_time:.1f}s - {sub.end_time:.1f}s] {status}")
        print(f"    テキスト: {sub.text}")
        print(f"    フレーム数: {sub.frame_count}")
