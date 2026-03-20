# Third-Party Notices

Caption Studio depends on platform frameworks, optional local AI runtimes, and Python packages.
This file is the GitHub-facing summary of what should be disclosed when you publish the app or a release.

## 1. This Repository's Own License

As of this file's addition, the repository does not yet include a top-level `LICENSE` file for Caption Studio itself.

If you want other people to legally reuse, modify, or redistribute the source code, add a repository license separately.
This file does not choose that license for you.

## 2. Apple Platform Frameworks

Caption Studio uses Apple-provided macOS frameworks such as:

- `Vision`
- `AVFoundation`
- `AVKit`
- `SwiftUI`
- `AppKit`

These are platform frameworks provided by Apple as part of macOS / Xcode tooling, not third-party open source libraries redistributed by this repository.
Their use is governed by Apple's platform and developer tool terms.

## 3. Optional Local AI Runtime

Translation and AI rerecognition can use the user's local Ollama runtime.

- Component: `Ollama`
- Upstream: <https://github.com/ollama/ollama>
- Upstream license: `MIT`
- Important note: the Ollama runtime license is separate from the license terms of each model the user downloads

## 4. Python Dependencies Installed by `requirements.txt`

Current direct Python dependencies declared by this repository:

- `numpy`
- `Pillow`
- `opencv-python`

At release time, confirm the exact versions actually bundled or installed in the managed backend environment.
If these versions change, update this notice file as well.

### Dependency License Summary

- `numpy`
  - Project page: <https://pypi.org/project/numpy/>
  - License expression shown by PyPI: `BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0`
- `Pillow`
  - Project page: <https://github.com/python-pillow/Pillow>
  - License: `MIT-CMU`
- `opencv-python`
  - Project page: <https://pypi.org/project/opencv-python/>
  - Package metadata shown by PyPI: `Apache 2.0`
  - Note: the `opencv-python` package wraps OpenCV and may include additional third-party notices depending on the wheel contents

## 5. Recommended Ollama Models

Caption Studio recommends models such as `gemma3`, `translategemma`, `qwen2.5`, `qwen2.5vl`, and `exaone3.5`.

Those model weights are not included in this repository by default.
Users download them separately through Ollama, and each model may have its own license, acceptable use policy, or commercial-use restriction.

Before commercial distribution or business use, verify the license terms of every model you recommend or document.

## 6. What To Show On GitHub

For GitHub distribution, keep at least these items visible:

1. A top-level project `LICENSE` for Caption Studio itself
2. A link to this `THIRD_PARTY_NOTICES.md`
3. Release notes or a changelog for each published version
4. A note that Ollama is optional and model licenses are separate from the app
