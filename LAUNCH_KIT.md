# Launch Kit

This file keeps the first public-facing marketing materials in one place so release pages, Product Hunt, Reddit posts, and README updates stay consistent.

## One-Line Pitch

Caption Studio is a macOS app that extracts hardcoded subtitles from video, translates them locally, and exports clean subtitle files or burned-in video.

## Short Release Description

Caption Studio helps creators pull subtitles from existing videos, translate them on-device, and export `SRT`, `FCPXML`, `MP4`, or `MOV` without sending source footage to a cloud service.

## GitHub Release Summary

Use this at the top of a public release:

```md
Caption Studio is a macOS-native tool for extracting hardcoded subtitles, translating them locally, and exporting clean subtitle files or burned-in videos.

Best for:
- VTuber clips and stream highlights
- multilingual subtitle workflows
- Final Cut Pro pipelines using FCPXML
- creators who need local, privacy-friendly processing
```

## Product Hunt Draft

```md
Caption Studio is a Mac app for extracting hardcoded subtitles from video, translating them locally with Ollama, and exporting SRT, FCPXML, MP4, or MOV.

Why I built it:
- existing tools were too cloud-heavy
- macOS options for OCR subtitle extraction were limited
- I wanted a workflow that fits clip editors and Final Cut Pro users

What makes it different:
- local-first translation
- hardcoded subtitle OCR
- FCPXML export for pro workflows
- notarized macOS release builds
```

## Reddit / Hacker News Draft

```md
I built a macOS app called Caption Studio.

It extracts hardcoded subtitles from videos, translates them locally, and exports SRT, FCPXML, MP4, or MOV.

The main goal was to help clip editors and creators who want multilingual subtitles without uploading their source videos to a cloud service.

Current strengths:
- local-first translation with Ollama
- OCR extraction from already-burned-in subtitles
- Final Cut Pro friendly export
- native macOS UI
```

## Screenshot Checklist

Capture these before the next wider launch:

1. Main editor with a loaded video, subtitle list, and extraction region visible.
2. Translation in progress with progress UI visible.
3. Settings panel showing update controls and tutorial access.
4. Burn-in preview with overlay layout visible.
5. Finder view showing `.subtitleproject` handling or installer package.

## Demo Clip Checklist

For the first demo GIF or short video:

1. Open a sample video.
2. Drag the subtitle extraction region.
3. Run extraction.
4. Run translation.
5. Show export options or FCPXML / MP4 output.

Keep the clip under 20 seconds and make sure the before/after change is visible without audio.

## Thumbnail Guidance

- Use a real app screenshot instead of a mockup
- Keep the app window large and readable
- Show a subtitle extraction rectangle or translated subtitle list
- Avoid too much surrounding desktop clutter

## Publishing Order

1. Update `README.md` and `README_EN.md`
2. Prepare screenshots / demo clip
3. Publish GitHub Release
4. Post to Product Hunt / Reddit / Hacker News
5. Watch user feedback and support requests for the first 48 hours
