import argparse
from contextlib import redirect_stdout
import json
import os
import sys

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)

from ollama_processor import OllamaProcessor


def str_to_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def emit_progress(processed: int, total: int, timestamp: float):
    print(
        json.dumps(
            {
                "event": "extract_progress",
                "processed": int(processed),
                "total": max(1, int(total)),
                "timestamp": float(timestamp),
            },
            ensure_ascii=False,
        ),
        file=sys.stderr,
        flush=True,
    )


def emit_translation_progress(processed: int, total: int, current_text: str):
    print(
        json.dumps(
            {
                "event": "translate_progress",
                "processed": int(processed),
                "total": max(1, int(total)),
                "current_text": str(current_text or ""),
            },
            ensure_ascii=False,
        ),
        file=sys.stderr,
        flush=True,
    )


def read_json_stdin() -> dict:
    payload = sys.stdin.read().strip()
    if not payload:
        return {}
    return json.loads(payload)


def load_subtitle_backend():
    from subtitle_backend import (
        normalize_subtitle_timings,
        probe_video,
        subtitle_from_dict,
        subtitles_to_json,
        write_export,
    )

    return {
        "normalize_subtitle_timings": normalize_subtitle_timings,
        "probe_video": probe_video,
        "subtitle_from_dict": subtitle_from_dict,
        "subtitles_to_json": subtitles_to_json,
        "write_export": write_export,
    }


def extract_command(args: argparse.Namespace):
    backend = load_subtitle_backend()
    from unified_ocr import OCREngine, SubtitleRegion, UnifiedOCR

    metadata = backend["probe_video"](args.video)
    region = None
    if args.region_json:
        region_payload = json.loads(args.region_json)
        region = SubtitleRegion(
            x=float(region_payload["x"]),
            y=float(region_payload["y"]),
            width=float(region_payload["width"]),
            height=float(region_payload["height"]),
        )

    try:
        ocr = UnifiedOCR(
            engine=OCREngine.MEIKI_OCR,
            language="ja",
            enable_scroll_detection=str_to_bool(args.detect_scroll),
        )
        ocr._init_meiki_ocr()
    except ModuleNotFoundError as error:
        raise RuntimeError(
            "日本語向け追加 OCR が入っていないため、このバックエンド単体では抽出できません。"
        ) from error

    with redirect_stdout(sys.stderr):
        entries = ocr.extract_from_video(
            args.video,
            region=region,
            fps_sample=float(args.fps_sample),
            progress_callback=emit_progress,
        )

    subtitles = [
        backend["subtitle_from_dict"](
            {
                "index": index + 1,
                "start_time": entry.start_time,
                "end_time": entry.end_time,
                "text": entry.text,
                "translated": entry.translated,
                "confidence": entry.confidence,
                "is_complete": entry.is_complete,
            }
        )
        for index, entry in enumerate(entries)
        if str(entry.text).strip()
    ]

    backend["normalize_subtitle_timings"](
        subtitles=subtitles,
        min_duration=float(args.min_duration),
        max_duration=float(args.max_duration),
        timeline_end=metadata.duration,
    )

    payload = {
        "subtitles": backend["subtitles_to_json"](subtitles),
        "video": {
            "path": metadata.path,
            "width": metadata.width,
            "height": metadata.height,
            "fps": metadata.fps,
            "duration": metadata.duration,
        },
    }
    print(json.dumps(payload, ensure_ascii=False))


def translate_command(args: argparse.Namespace):
    backend = load_subtitle_backend()
    payload = read_json_stdin()
    subtitles = [backend["subtitle_from_dict"](item) for item in payload.get("subtitles", [])]

    processor = OllamaProcessor(
        model=args.model,
        custom_dictionary=args.custom_dictionary or "",
    )

    if not processor.check_available():
        raise RuntimeError("Ollamaが起動していません。'ollama serve' を実行してください。")

    source_texts = [subtitle.text.strip() for subtitle in subtitles]
    translated_texts = processor.translate_batch(
        source_texts,
        source_lang=args.source_lang,
        target_lang=args.target_lang,
        use_context=str_to_bool(args.use_context),
        context_window=max(0, int(args.context_window)),
        preserve_slang=str_to_bool(args.preserve_slang),
        progress_callback=emit_translation_progress,
    )

    translated_subtitles = []
    for subtitle, translated_text in zip(subtitles, translated_texts):
        if translated_text:
            subtitle.translated = translated_text
        translated_subtitles.append(subtitle)

    print(json.dumps({"subtitles": backend["subtitles_to_json"](translated_subtitles)}, ensure_ascii=False))


def correct_ocr_command(args: argparse.Namespace):
    payload = read_json_stdin()
    text = str(payload.get("text", "") or "")

    processor = OllamaProcessor(
        model=args.model,
        custom_dictionary=args.custom_dictionary or "",
    )

    if not processor.check_available():
        raise RuntimeError("Ollamaが起動していません。'ollama serve' を実行してください。")

    result = processor.correct_ocr(text, source_lang=args.source_lang)
    if not result.success:
        raise RuntimeError(result.error or "OCR補正に失敗しました。")

    print(json.dumps({"text": result.processed}, ensure_ascii=False))


def vision_rerecognize_command(args: argparse.Namespace):
    payload = read_json_stdin()
    images = list(payload.get("images", []) or [])
    source_lang = str(payload.get("source_language", "ja") or "ja")
    hint_text = str(payload.get("hint_text", "") or "")

    processor = OllamaProcessor(
        model=args.model,
    )

    if not processor.check_available():
        raise RuntimeError("Ollamaが起動していません。'ollama serve' を実行してください。")

    result = processor.recognize_subtitle_images(
        images=images,
        source_lang=source_lang,
        hint_text=hint_text,
    )
    if not result.success:
        raise RuntimeError(result.error or "画像からの再認識に失敗しました。")

    print(json.dumps({"text": result.processed}, ensure_ascii=False))


def models_command(args: argparse.Namespace):
    processor = OllamaProcessor()
    available = processor.check_available()
    models = processor.get_available_models() if available else []
    print(json.dumps({"available": available, "models": models}, ensure_ascii=False))


def export_command(args: argparse.Namespace):
    backend = load_subtitle_backend()
    payload = read_json_stdin()
    subtitles = [backend["subtitle_from_dict"](item) for item in payload.get("subtitles", [])]
    video = payload.get("video", {})

    backend["normalize_subtitle_timings"](
        subtitles=subtitles,
        min_duration=float(args.min_duration),
        max_duration=float(args.max_duration),
        timeline_end=float(video.get("duration", 0.0) or 0.0) or None,
    )

    backend["write_export"](
        subtitles=subtitles,
        output_path=args.output,
        export_format=args.format.lower(),
        translated=str_to_bool(args.translated),
        wrap_width_ratio=float(args.wrap_width_ratio),
        wrap_timing_mode=str(args.wrap_timing_mode),
        preferred_line_count=int(args.preferred_line_count),
        video_width=int(video.get("width", args.width)),
        video_height=int(video.get("height", args.height)),
        fps=float(video.get("fps", args.fps)),
        font_size=int(args.font_size),
        font_name=args.font_name,
        outline_width=float(args.outline_width),
    )

    print(json.dumps({"success": True, "output": args.output}, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    extract = subparsers.add_parser("extract")
    extract.add_argument("--video", required=True)
    extract.add_argument("--fps-sample", default="2.0")
    extract.add_argument("--detect-scroll", default="true")
    extract.add_argument("--min-duration", default="0.5")
    extract.add_argument("--max-duration", default="10.0")
    extract.add_argument("--region-json")
    extract.set_defaults(handler=extract_command)

    translate = subparsers.add_parser("translate")
    translate.add_argument("--model", default="gemma3:4b")
    translate.add_argument("--custom-dictionary", default="")
    translate.add_argument("--source-lang", default="ja")
    translate.add_argument("--target-lang", default="en")
    translate.add_argument("--use-context", default="true")
    translate.add_argument("--context-window", default="2")
    translate.add_argument("--preserve-slang", default="true")
    translate.set_defaults(handler=translate_command)

    correct_ocr = subparsers.add_parser("correct-ocr")
    correct_ocr.add_argument("--model", default="gemma3:4b")
    correct_ocr.add_argument("--custom-dictionary", default="")
    correct_ocr.add_argument("--source-lang", default="ja")
    correct_ocr.set_defaults(handler=correct_ocr_command)

    vision_rerecognize = subparsers.add_parser("vision-rerecognize")
    vision_rerecognize.add_argument("--model", default="gemma3:4b")
    vision_rerecognize.set_defaults(handler=vision_rerecognize_command)

    models = subparsers.add_parser("models")
    models.set_defaults(handler=models_command)

    export = subparsers.add_parser("export")
    export.add_argument("--output", required=True)
    export.add_argument("--format", required=True)
    export.add_argument("--translated", default="false")
    export.add_argument("--wrap-width-ratio", default="0.68")
    export.add_argument("--wrap-timing-mode", default="balanced")
    export.add_argument("--preferred-line-count", default="0")
    export.add_argument("--font-size", default="24")
    export.add_argument("--font-name", default="Hiragino Sans")
    export.add_argument("--outline-width", default="4.0")
    export.add_argument("--width", default="1920")
    export.add_argument("--height", default="1080")
    export.add_argument("--fps", default="30.0")
    export.add_argument("--min-duration", default="0.5")
    export.add_argument("--max-duration", default="10.0")
    export.set_defaults(handler=export_command)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    try:
        args.handler(args)
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
