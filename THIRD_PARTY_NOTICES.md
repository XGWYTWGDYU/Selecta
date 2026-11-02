# Third-party notices

Selecta is distributed under GPL-3.0. See [LICENSE](LICENSE).

## Easydict

- Source: https://github.com/tisfeng/Easydict
- Reference revision: `8c120ff57ac141bc91006177f449cc8e48592893` (dev)
- Copyright © 2023–2026 izual and Easydict contributors.
- License: GPL-3.0.
- Selecta's Google GTX request/response handling, DeepL anonymous oneshot client profile,
  and AX-first selection/copy fallback workflow were adapted or reimplemented from this code.
- The Mini popup window behavior, dimensions, query/result layout and colors are ported to Swift
  from `EZMiniQueryWindow`, `EZBaseQueryWindow`, `EZTitlebar`, `EZQueryView`, `EZSelectLanguageCell`
  and `EZResultView`. The five retained service icon image sets are copied from Easydict's assets.
- Easydict acknowledges Bob (GPL-3.0) as the foundation of its original implementation.
- Selecta modifies these components into a Swift application with reduced translation providers,
  rewritten settings, no TTS/dictionaries, and local PaddleOCR inference.
- Modifications: Selecta contributors, 2026. The complete modified source and build instructions
  are supplied in this repository; upstream attribution is retained in the relevant source files.

## Optional local OCR runtime

The native application uses Apple's AppKit, SwiftUI, UserNotifications, ServiceManagement and NaturalLanguage frameworks.
It bundles no CocoaPods, TTS engines, dictionaries or third-party AI SDKs.

The in-app installer separately downloads uv (MIT/Apache-2.0), managed CPython,
PaddleOCR and PaddlePaddle, and downloads
PP-OCRv5 mobile detection/recognition model files, developed by Baidu/PaddlePaddle.
PaddleOCR and PaddlePaddle are licensed under Apache-2.0. Their package distributions
and model downloads retain their respective licenses/notices. Python dependencies
have their own licenses; do not assume GPL-3.0 replaces those notices.

- https://github.com/PaddlePaddle/PaddleOCR
- https://github.com/PaddlePaddle/Paddle

- uv: https://github.com/astral-sh/uv (MIT OR Apache-2.0).
- Managed Python: https://github.com/astral-sh/python-build-standalone; see installed runtime license files.
