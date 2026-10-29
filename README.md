# EasyControl

Control your Mac with hand gestures through the built-in camera. Everything runs on-device: Apple Vision finds 21 hand landmarks per hand, and EasyControl's own gesture engine turns them into scrolling, Space switching and Mission Control — no cloud, no LLM, no frames ever stored.

> **Status: M3.** Engage with an open palm, scroll with two fingers, swipe an open palm to switch Spaces or open Mission Control. Poses are recognized by EasyControl's own Core ML classifier (97.8 % on people it has never seen). Cursor mode (M4) and custom gestures (M5) are next. See the [design spec](docs/superpowers/specs/2026-10-29-easycontrol-design.md).

## How it works

```
Camera ─► Vision hand pose ─► Signal (One Euro smoothing, normalization, features)
       ─► GestureEngine (Core ML pose classifier, hysteresis, engagement, scroll/swipe recognizers, arbitration)
       ─► Actions (CGEvent scroll with momentum, Ctrl+Arrow Space switching)
```

- **Engagement gate:** gestures only count after you hold an open palm for 0.4 s; it disengages after 3 s idle or when your hand leaves. Any keyboard/mouse input pauses gestures for 0.5 s.
- **Deterministic core:** the engine takes landmark sequences and timestamps only, so recorded sessions replay in unit tests.
- **Privacy:** frames are processed in memory; pausing (or locking the screen / sleeping) stops the camera.

| Gesture (after engaging) | Action |
|---|---|
| Two fingers up + move | Scroll (with momentum) |
| Open palm swipe left / right | Previous / next Space |
| Open palm swipe up / down | Mission Control / App Exposé |

## The pose classifier

EasyControl trains its own model rather than using an off-the-shelf gesture recognizer:

1. `tools/dataset` picks ~22 k images from [HaGRID](https://github.com/hukenovs/hagrid) using its **subject-disjoint** train/val/test splits.
2. `ec-extract` runs the *app's own* Vision detector and feature code on every image, so training features are exactly what the app computes live.
3. `tools/training` trains a small MLP (52 → 256 → 128 → 9) with standardization folded in and exports Core ML.

| Classifier | Accuracy on held-out people | Macro F1 |
|---|---|---|
| **EasyControl Core ML model** | **97.8 %** | **0.973** |
| Hand-written rules (M2) | 41.7 % | 0.314 |

Full results, per-class metrics, confusion matrix and model selection: [docs/eval/m3-report.md](docs/eval/m3-report.md). The model is 196 KB, runs on the CPU in well under a millisecond, and is licensed CC BY-SA 4.0 ([App/Resources/MODEL_LICENSE.md](App/Resources/MODEL_LICENSE.md)).

`ec-replay` replays landmark recordings through the engine to measure false actions per hour (target < 1 on normal use).

## Requirements

macOS 15+, Apple Silicon, Xcode 16+ with Swift 6, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Build and run

```bash
scripts/build-app.sh
open build/EasyControl.app
```

Grant **Camera** and **Accessibility** when asked. For permissions to survive rebuilds, add an Apple ID in Xcode → Settings → Accounts (a free account works); the build script then signs with your *Apple Development* identity automatically.

## Develop

```bash
scripts/test-core.sh                                   # core package tests
swift run --package-path Packages/EasyControlCore ec-probe space right   # live input probes
swift run --package-path Packages/EasyControlCore ec-replay --model App/Resources/PoseClassifier.mlpackage ~/Library/Application\ Support/EasyControl/recordings/*.jsonl
```

Retrain the classifier (downloads ~2.6 GB of HaGRID images into the git-ignored `data/`):

```bash
cd tools/dataset && uv run fetch.py
swift run -c release --package-path ../../Packages/EasyControlCore ec-extract --manifest ../../data/hagrid/manifest.jsonl --images ../../data/hagrid/images --out ../../data/hagrid/features.jsonl
cd ../training && uv run train.py
```

| Path | What |
|---|---|
| `Packages/EasyControlCore` | `HandTracking`, `Signal`, `GestureEngine`, `Actions`, `Capture` modules + tests |
| `App/` | SwiftUI menu-bar app, permissions, debug window, landmark recorder |
| `tools/dataset/`, `tools/training/` | HaGRID subset selection, training, Core ML export, evaluation |
| `tools/spikes/` | M0 measurements (throwaway) |
| `docs/` | spec, plans, spike results, QA checklist |

## License

Code: MIT (to be added with the first release). The bundled pose model is CC BY-SA 4.0, trained on HaGRID — see [App/Resources/MODEL_LICENSE.md](App/Resources/MODEL_LICENSE.md).
