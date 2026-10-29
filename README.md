# EasyControl

Control your Mac with hand gestures through the built-in camera. Everything runs on-device: Apple Vision finds 21 hand landmarks per hand, and EasyControl's own gesture engine turns them into scrolling, Space switching and Mission Control — no cloud, no LLM, no frames ever stored.

> **Status: M2 (first usable build).** Engage with an open palm, scroll with two fingers, swipe an open palm to switch Spaces or open Mission Control. A trained Core ML pose classifier (M3), cursor mode (M4) and custom gestures (M5) are next. See the [design spec](docs/superpowers/specs/2026-10-29-easycontrol-design.md).

## How it works

```
Camera ─► Vision hand pose ─► Signal (One Euro smoothing, normalization, features)
       ─► GestureEngine (pose hysteresis, engagement, scroll/swipe recognizers, arbitration)
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
```

| Path | What |
|---|---|
| `Packages/EasyControlCore` | `HandTracking`, `Signal`, `GestureEngine`, `Actions`, `Capture` modules + tests |
| `App/` | SwiftUI menu-bar app, permissions, debug window, landmark recorder |
| `tools/spikes/` | M0 measurements (throwaway) |
| `docs/` | spec, plans, spike results, QA checklist |

## License

Code: MIT (to be added with the first release). Models trained on HaGRID data will carry its CC BY-SA–based licence.
