# EasyControl

Control your Mac with hand gestures through the built-in camera. Everything runs on-device: Apple Vision finds 21 hand landmarks per hand, and EasyControl's own gesture engine turns them into scrolling, Space switching and Mission Control — no cloud, no LLM, no frames ever stored.

> **Status: M3.5.** Engage with an open palm (or two/three fingers), scroll with two fingers, and drag three fingers to move between Spaces or pull open Mission Control — the Dock follows your hand like a trackpad. Poses are recognized by EasyControl's own Core ML classifier (94.3 % end to end on people it has never seen; when it acts on a gesture it is right 97.8 % of the time). Cursor mode (M4) and custom gestures (M5) are next. See the [design spec](docs/superpowers/specs/2026-10-29-easycontrol-design.md).

## How it works

```
Camera ─► Vision hand pose ─► Signal (One Euro smoothing, normalization, features)
       ─► GestureEngine (Core ML pose classifier, hysteresis, engagement, scroll/swipe recognizers, arbitration)
       ─► Actions (CGEvent scroll with momentum, Ctrl+Arrow Space switching)
```

- **Engagement gate:** gestures only count after you hold an open palm for 0.4 s (or two/three fingers for 0.3 s). When your hand leaves or goes quiet, EasyControl waits in standby for 15 s, and any gesture pose resumes instantly. Any keyboard/mouse input pauses gestures for 0.5 s.
- **Deterministic core:** the engine takes landmark sequences and timestamps only, so recorded sessions replay in unit tests.
- **Privacy:** frames are processed in memory; pausing (or locking the screen / sleeping) stops the camera.

| Gesture (after engaging) | Action |
|---|---|
| Two fingers up + move | Scroll (with momentum) |
| **Three fingers + drag left / right** | Spaces strip follows your hand; release to commit or snap back (like the trackpad) |
| **Three fingers + drag up / down** | Mission Control / App Exposé, following your hand |
| Open palm quick swipe left / right / up / down | Space left/right, Mission Control, App Exposé (discrete) |

Finger-following swipes use the Dock's own swipe event (private API, resolved at runtime; see [docs/spikes/m0-results.md](docs/spikes/m0-results.md) §5 and credit to [Grabby](https://github.com/govindup63/grabby)'s research). If it is unavailable on a future macOS, three-finger drags fall back to the keyboard shortcuts on release.

## The pose classifier

EasyControl trains its own model rather than using an off-the-shelf gesture recognizer:

1. `tools/dataset` picks ~22 k images from [HaGRID](https://github.com/hukenovs/hagrid) using its **subject-disjoint** train/val/test splits.
2. `ec-extract` runs the *app's own* Vision detector and feature code on every image, so training features are exactly what the app computes live.
3. `tools/training` trains a small MLP (55 → 256 → 128 → 10) with standardization folded in and exports Core ML. Features are aspect-ratio corrected and include absolute hand orientation; every training hand also appears with its left/right label flipped, so the model doesn't depend on Vision's chirality guess.

Measured end to end on HaGRID's held-out subjects, counting every detected hand the way the app does (hands failing the confidence gate count as `none`; the app only acts at ≥ 0.85 probability):

| Metric | Core ML model | Hand-written rules (M2) |
|---|---|---|
| Accuracy | **94.3 %** | 41.7 %* |
| When it acts on a gesture, it is right | **97.8 %** | — |
| Non-gesture hands turned into a gesture | **1.7 %** | — |

**Personalization:** the debug window's recorder lets you record your own poses; `ec-extract --recordings` adds them to training (temporal 60/15/25 split per recording). On held-out parts of the author's recordings, accuracy went from 76.5 % (HaGRID only) to 84.9 % — 80.7 % → 87.0 % excluding `pinch`, which HaGRID lacks and which went from 0 % to 47 % ([docs/eval/m3-personal-baseline.json](docs/eval/m3-personal-baseline.json)).

False triggers: replaying the held-out 2.5 minutes of the author's normal-use recording through the current engine and model fired **zero** actions (`ec-replay --segment test`, no typing suppression applied). That is too short to establish the < 1 action/hour target; it needs about an hour of normal-use recording.

\* The rules cover only 6 of the 10 classes. The spec's 97 % target is **not yet met** end to end, and the false-trigger target needs a longer normal-use recording, so M3 is code-complete but not exited.

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
# with your own recordings:
swift run -c release --package-path ../../Packages/EasyControlCore ec-extract --recordings ~/Library/Application\ Support/EasyControl/recordings --out ../../data/local/features.jsonl
uv run train.py --sweep-local
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
