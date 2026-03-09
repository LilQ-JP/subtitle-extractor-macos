import json
import os
import sys
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from fractions import Fraction
from typing import List, Optional

import cv2
from PIL import ImageFont


@dataclass
class SubtitleRecord:
    index: int
    start_time: float
    end_time: float
    text: str
    translated: str = ""
    confidence: float = 1.0
    is_complete: bool = True


@dataclass
class VideoMetadata:
    path: str
    width: int
    height: int
    fps: float
    duration: float


def subtitle_from_dict(data: dict) -> SubtitleRecord:
    return SubtitleRecord(
        index=int(data.get("index", 0)),
        start_time=float(data.get("start_time", 0.0)),
        end_time=float(data.get("end_time", 0.0)),
        text=str(data.get("text", "")),
        translated=str(data.get("translated", "")),
        confidence=float(data.get("confidence", 1.0)),
        is_complete=bool(data.get("is_complete", True)),
    )


def subtitles_to_json(subtitles: List[SubtitleRecord]) -> List[dict]:
    return [asdict(subtitle) for subtitle in subtitles]


def probe_video(video_path: str) -> VideoMetadata:
    capture = cv2.VideoCapture(video_path)
    if not capture.isOpened():
        raise RuntimeError(f"動画を開けません: {video_path}")

    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
    fps = float(capture.get(cv2.CAP_PROP_FPS) or 30.0)
    total_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    duration = total_frames / fps if fps > 0 else 0.0
    capture.release()

    return VideoMetadata(
        path=video_path,
        width=width,
        height=height,
        fps=fps,
        duration=duration,
    )


def _normalized_font_token(value: str) -> str:
    return "".join(char.lower() for char in value if char.isalnum())


def _font_name_candidates(font_name: str) -> List[str]:
    if not font_name.strip():
        return []

    normalized_name = _normalized_font_token(font_name)
    font_paths: List[str] = []
    search_roots: List[str] = []

    if sys.platform == "darwin":
        search_roots = [
            "/System/Library/Fonts",
            "/System/Library/Fonts/Supplemental",
            "/Library/Fonts",
            os.path.expanduser("~/Library/Fonts"),
        ]
    elif sys.platform == "win32":
        search_roots = [r"C:\Windows\Fonts"]
    else:
        search_roots = ["/usr/share/fonts", "/usr/local/share/fonts", os.path.expanduser("~/.fonts")]

    for root in search_roots:
        if not os.path.isdir(root):
            continue
        for current_root, _, files in os.walk(root):
            for filename in files:
                if not filename.lower().endswith((".ttf", ".ttc", ".otf")):
                    continue
                if normalized_name in _normalized_font_token(filename):
                    font_paths.append(os.path.join(current_root, filename))

    return font_paths


def load_subtitle_font(font_size: int, font_name: Optional[str] = None):
    candidates: List[str] = []
    if font_name:
        candidates.extend(_font_name_candidates(font_name))

    if sys.platform == "darwin":
        candidates.extend([
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            "/System/Library/Fonts/AppleSDGothicNeo.ttc",
            "/Library/Fonts/Arial Unicode.ttf",
        ])
    elif sys.platform == "win32":
        candidates.extend(["msgothic.ttc", "C:\\Windows\\Fonts\\msgothic.ttc"])
    else:
        candidates.extend(["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"])

    for candidate in dict.fromkeys(candidates):
        try:
            if candidate == "msgothic.ttc" or os.path.exists(candidate):
                return ImageFont.truetype(candidate, font_size)
        except Exception:
            continue

    return ImageFont.load_default()


def measure_text_width(text: str, font) -> float:
    if not text:
        return 0.0
    if hasattr(font, "getlength"):
        return float(font.getlength(text))
    bbox = font.getbbox(text)
    return float(bbox[2] - bbox[0])


def wrap_subtitle_text(text: str, max_width_px: float, font) -> str:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not normalized or max_width_px <= 0:
        return normalized

    def split_long_token(token: str) -> List[str]:
        parts: List[str] = []
        current = ""
        for char in token:
            candidate = current + char
            if current and measure_text_width(candidate, font) > max_width_px:
                parts.append(current)
                current = char
            else:
                current = candidate
        if current:
            parts.append(current)
        return parts

    def is_space_separated(line: str) -> bool:
        ascii_chars = sum(1 for char in line if ord(char) < 128)
        return " " in line and ascii_chars >= len(line) * 0.45

    wrapped: List[str] = []
    for raw_line in normalized.split("\n"):
        line = raw_line.strip()
        if not line:
            if wrapped and wrapped[-1] != "":
                wrapped.append("")
            continue

        if measure_text_width(line, font) <= max_width_px:
            wrapped.append(line)
            continue

        if is_space_separated(line):
            current = ""
            for word in line.split():
                if measure_text_width(word, font) > max_width_px:
                    if current:
                        wrapped.append(current)
                        current = ""
                    pieces = split_long_token(word)
                    wrapped.extend(pieces[:-1])
                    current = pieces[-1]
                    continue

                candidate = word if not current else f"{current} {word}"
                if current and measure_text_width(candidate, font) > max_width_px:
                    wrapped.append(current)
                    current = word
                else:
                    current = candidate

            if current:
                wrapped.append(current)
            continue

        current = ""
        for char in line:
            candidate = current + char
            if current and measure_text_width(candidate, font) > max_width_px:
                wrapped.append(current)
                current = char
            else:
                current = candidate
        if current:
            wrapped.append(current)

    return "\n".join(wrapped).strip()


def normalize_subtitle_timings(
    subtitles: List[SubtitleRecord],
    min_duration: float,
    max_duration: float,
    timeline_end: Optional[float] = None,
) -> List[SubtitleRecord]:
    if not subtitles:
        return subtitles

    epsilon = 0.01
    subtitles.sort(key=lambda item: (item.start_time, item.end_time, item.index))
    previous_end = 0.0

    for index, subtitle in enumerate(subtitles):
        subtitle.start_time = max(0.0, float(subtitle.start_time), previous_end if index > 0 else 0.0)
        if timeline_end is not None:
            subtitle.start_time = min(subtitle.start_time, max(0.0, float(timeline_end) - epsilon))
        subtitle.end_time = max(subtitle.start_time + epsilon, float(subtitle.end_time))

        if max_duration > 0:
            subtitle.end_time = min(subtitle.end_time, subtitle.start_time + max_duration)

        next_start = None
        if index + 1 < len(subtitles):
            next_start = max(0.0, float(subtitles[index + 1].start_time))
            next_start = max(next_start, subtitle.start_time + epsilon)
        elif timeline_end is not None:
            next_start = max(subtitle.start_time + epsilon, float(timeline_end))

        if min_duration > 0:
            desired_end = subtitle.start_time + min_duration
            if next_start is not None:
                desired_end = min(desired_end, next_start - epsilon)
            subtitle.end_time = max(subtitle.end_time, max(subtitle.start_time + epsilon, desired_end))

        if next_start is not None:
            if max_duration > 0:
                bridged_end = min(next_start - epsilon, subtitle.start_time + max_duration)
            else:
                bridged_end = next_start - epsilon
            subtitle.end_time = max(subtitle.end_time, max(subtitle.start_time + epsilon, bridged_end))
        elif timeline_end is not None:
            if max_duration > 0:
                trailing_end = min(float(timeline_end), subtitle.start_time + max_duration)
            else:
                trailing_end = float(timeline_end)
            subtitle.end_time = max(subtitle.end_time, max(subtitle.start_time + epsilon, trailing_end))

        if next_start is not None:
            subtitle.end_time = min(subtitle.end_time, max(subtitle.start_time + epsilon, next_start - epsilon))

        if timeline_end is not None:
            subtitle.end_time = min(subtitle.end_time, float(timeline_end))

        if subtitle.end_time <= subtitle.start_time:
            subtitle.end_time = subtitle.start_time + epsilon

        subtitle.index = index + 1
        previous_end = subtitle.end_time

    return subtitles


def format_srt_time(seconds: float) -> str:
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    milliseconds = int(round((seconds - int(seconds)) * 1000))
    if milliseconds >= 1000:
        secs += 1
        milliseconds -= 1000
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{milliseconds:03d}"


def seconds_to_fcpx_time(seconds: float, fps: float) -> str:
    safe_seconds = max(0.0, seconds)
    if safe_seconds == 0:
        return "0s"
    safe_fps = fps if fps and fps > 0 else 30.0
    fraction = Fraction(safe_seconds).limit_denominator(int(safe_fps * 1000))
    return f"{fraction.numerator}/{fraction.denominator}s"


def _formatted_text(
    subtitle: SubtitleRecord,
    translated: bool,
    wrap_width_ratio: float,
    video_width: int,
    font_size: int,
    font_name: str,
) -> str:
    base_text = subtitle.translated if translated and subtitle.translated else subtitle.text
    font = load_subtitle_font(font_size, font_name=font_name)
    max_width = max(120.0, float(video_width) * max(0.3, min(wrap_width_ratio, 0.95)))
    return wrap_subtitle_text(base_text, max_width, font)


def write_srt(
    subtitles: List[SubtitleRecord],
    output_path: str,
    translated: bool,
    wrap_width_ratio: float,
    video_width: int,
    font_size: int,
    font_name: str,
):
    with open(output_path, "w", encoding="utf-8") as handle:
        for subtitle in subtitles:
            handle.write(f"{subtitle.index}\n")
            handle.write(f"{format_srt_time(subtitle.start_time)} --> {format_srt_time(subtitle.end_time)}\n")
            handle.write(
                f"{_formatted_text(subtitle, translated, wrap_width_ratio, video_width, font_size, font_name)}\n\n"
            )


def write_fcpxml(
    subtitles: List[SubtitleRecord],
    output_path: str,
    translated: bool,
    wrap_width_ratio: float,
    video_width: int,
    video_height: int,
    fps: float,
    font_size: int,
    font_name: str,
    outline_width: float,
):
    total_duration = max((subtitle.end_time for subtitle in subtitles), default=0.0)
    title_font_size = max(36, int(font_size * 1.8))

    root = ET.Element("fcpxml", version="1.11")
    resources = ET.SubElement(root, "resources")
    ET.SubElement(
        resources,
        "format",
        id="r1",
        name=f"SubtitleFormat{video_height}p",
        frameDuration=seconds_to_fcpx_time(1.0 / fps, fps),
        width=str(video_width),
        height=str(video_height),
        colorSpace="1-1-1 (Rec. 709)",
    )
    ET.SubElement(
        resources,
        "effect",
        id="r2",
        name="Basic Title",
        uid=".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti",
    )

    library = ET.SubElement(root, "library")
    event = ET.SubElement(library, "event", name="Subtitle Export")
    project = ET.SubElement(event, "project", name=os.path.splitext(os.path.basename(output_path))[0])
    sequence = ET.SubElement(
        project,
        "sequence",
        format="r1",
        duration=seconds_to_fcpx_time(total_duration, fps),
        tcStart="0s",
        tcFormat="NDF",
        audioLayout="stereo",
        audioRate="48k",
    )
    spine = ET.SubElement(sequence, "spine")
    gap = ET.SubElement(
        spine,
        "gap",
        name="Gap",
        offset="0s",
        start="0s",
        duration=seconds_to_fcpx_time(total_duration, fps),
    )

    for subtitle in subtitles:
        title = ET.SubElement(
            gap,
            "title",
            ref="r2",
            name=f"Subtitle {subtitle.index}",
            lane="1",
            offset=seconds_to_fcpx_time(subtitle.start_time, fps),
            start="0s",
            duration=seconds_to_fcpx_time(subtitle.end_time - subtitle.start_time, fps),
        )
        text = ET.SubElement(title, "text")
        style_id = f"ts{subtitle.index}"
        text_style = ET.SubElement(text, "text-style", ref=style_id)
        text_style.text = _formatted_text(
            subtitle,
            translated,
            wrap_width_ratio,
            video_width,
            title_font_size,
            font_name,
        )
        style_def = ET.SubElement(title, "text-style-def", id=style_id)
        ET.SubElement(
            style_def,
            "text-style",
            font=font_name or "Hiragino Sans",
            fontSize=str(title_font_size),
            fontFace="Regular",
            fontColor="1 1 1 1",
            strokeColor="0 0 0 1",
            strokeWidth=str(max(0.0, float(outline_width))),
            alignment="center",
        )

    tree = ET.ElementTree(root)
    ET.indent(tree, space="  ")
    tree.write(output_path, encoding="utf-8", xml_declaration=True)


def write_export(
    subtitles: List[SubtitleRecord],
    output_path: str,
    export_format: str,
    translated: bool,
    wrap_width_ratio: float,
    video_width: int,
    video_height: int,
    fps: float,
    font_size: int,
    font_name: str,
    outline_width: float,
):
    if export_format == "fcpxml":
        write_fcpxml(
            subtitles=subtitles,
            output_path=output_path,
            translated=translated,
            wrap_width_ratio=wrap_width_ratio,
            video_width=video_width,
            video_height=video_height,
            fps=fps,
            font_size=font_size,
            font_name=font_name,
            outline_width=outline_width,
        )
        return

    write_srt(
        subtitles=subtitles,
        output_path=output_path,
        translated=translated,
        wrap_width_ratio=wrap_width_ratio,
        video_width=video_width,
        font_size=font_size,
        font_name=font_name,
    )


def read_json_stdin() -> dict:
    payload = sys.stdin.read().strip()
    if not payload:
        return {}
    return json.loads(payload)
