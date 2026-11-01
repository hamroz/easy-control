# EasyControl M4 — Touch & Smooth — Design Spec

- **Date:** 2026-11-01 · **Status:** draft, awaiting review
- **Parent spec:** `2026-10-29-easycontrol-design.md` (this replaces its §3.3–3.4 command/cursor split for v1)
- **Followed by:** M5 "First run" (onboarding, tutorial, on-device personalization, settings) and M6 "Release" (DMG, GitHub Actions releases, Sparkle updates) — separate specs.

## 1. Intent

### What the user asked for (2026-11-01)
- "Works fine, but not smooth." All four were felt: steppy scrolling, laggy three-finger drag, poses dropping out, gestures hard to trigger.
- A pointer that follows the hand, where touching thumb and index **acts like touching the screen**: a quick pinch clicks, pinch-and-move scrolls up/down — "very intuitive and easy for humans to grasp", like the reference demo the idea came from.
- The best experience for regular people (onboarding and distribution follow in M5/M6).

### Decisions
| Decision | Choice |
|---|---|
| Pinch model | **Pinch = touch**: tap = click, pinch + move = scroll (content follows the hand, momentum), pinch + hold 0.4 s then move = drag |
| Pointer mapping | **Like a trackpad**: relative movement with acceleration; hand out of view = "lift" |
| Kept | Three-finger finger-following Spaces / Mission Control |
| Removed from the default gesture set | Open-palm discrete swipes (they conflict with pointer movement) and two-finger scroll (pinch-scroll replaces it) |

### Measured facts this design rests on
- FaceTime HD camera: every format is 15–30 fps (no 60 fps). The built-in display runs at 120 Hz. So one camera frame spans four display frames.
- The capture currently delivers 1920×1080 although 640×480 is requested (recordings show aspect 16:9).

### Success criteria
- Pointer, scroll and Dock output change **every display frame** (120 Hz), never in camera-frame jumps; no single-frame pointer step larger than the distance the hand-model predicts for that frame.
- Perceived pointer latency (hand motion → cursor) ≤ 60 ms p95, measured with the debug overlay's latency readout; raw pipeline latency must not regress from M3.5.
- Pinch detection: ≥ 98 % of frames in the user's `pinch` recording read as pinched once the pose is formed; ≤ 0.5 % of frames in `none`/`normal-use` recordings read as pinched (thresholds calibrated on aggregates of the user's recordings, never committed as raw data).
- 0 clicks in the held-out normal-use replay; no stuck mouse button or open scroll in any exit path (tested).

### Non-goals (M4)
Onboarding, tutorial, personalization UI, settings window, launch at login, DMG/updates (M5/M6). Custom poses, two-hand zoom.

## 2. Interaction model

### 2.1 States
```
idle ──raise open hand 0.3 s──► hover ──pinch──► pressed ──┬─ release < 0.25 s, moved < slop ─► click (→ hover)
  ▲                               │  ▲                     ├─ moved ≥ slop before 0.4 s ──────► scrolling ─release─► momentum (→ hover)
  └──── standby 15 s ◄── hand lost/idle                     └─ held still 0.4 s ──────────────► dragging ─release─► mouse up (→ hover)
three fingers in hover ─► Dock swipe (M3.5) ─► hover
```
- **hover:** pointer follows the hand; overlay ring visible.
- **pressed:** pointer frozen at the **click anchor** (see 2.3); nothing emitted until the gesture is classified.
- **click:** left click at the anchor. A second tap within 0.35 s and 0.02 frame-heights of the first gives `clickCount = 2`. Thumb + **middle** pinch tap = right click.
- **scrolling:** content follows the hand (natural), both axes; release coasts with momentum (existing `ScrollInjector`).
- **dragging:** mouse down at the anchor, `leftMouseDragged` with pointer motion, mouse up on release.
- **Engagement** changes from M3.5 only in its triggers: an open palm held **0.3 s** (was 0.4 s) or three fingers held 0.3 s; two-finger direct engagement is removed along with two-finger scroll. Standby (15 s, debounced resume), typing suppression and the continuous-gesture exclusive lock from M3.5 still apply; in standby, a hand returning in hover or pinch-ready pose resumes. Clicks, scrolls and drags only happen while engaged.

### 2.2 Pointer mapping (relative, accelerated)
- Anchor point: the **index MCP** (it barely moves when fingers pinch), smoothed.
- Per display frame, hand displacement `d` (isotropic frame heights) → pointer pixels `gain(|v|) · d · screenHeight`, where `v` is hand speed (frame heights/s):
  - precision zone: `|v| < 0.15` → gain 0.6
  - linear ramp to gain 2.5 at `|v| = 1.2`, flat above (constants in one config struct, tuned live).
- Pointer clamped to the union of all display frames. Hand leaving the view or pressed state = no movement (natural "lift").
- Pointer speed multiplier stored in config (exposed in M5 settings).

### 2.3 Pinch detection (geometry, not the classifier)
- `pinchRatio = |thumbTip − indexTip| / palmSize` in isotropic units; `middleRatio` likewise with the middle tip.
- Hysteresis: closed when `pinchRatio < closeThreshold`, open when `> openThreshold` (initial 0.22 / 0.35; calibrated in M4 from the distributions of the user's `pinch` vs `none`/`normal-use` recordings, aggregate statistics only).
- Valid only when thumb tip, index tip (and middle tip for right click) have confidence ≥ 0.3; otherwise the last state holds for up to 0.2 s, then the touch is cancelled (no click; an active drag gets mouse-up, a scroll ends).
- **Click anchor:** fingers start closing before the threshold is crossed, dragging the anchor point. The pointer position used for press is the one from when `pinchRatio` first started falling steadily (looked up in a 150 ms history), capped at 120 ms before the close.
- **Slop:** 0.015 frame heights of anchor travel separates tap from scroll.

### 2.4 Pose robustness (three fingers)
`three` uses temporal evidence: the mean probability over the last 150 ms must exceed 0.7 (instead of 3 consecutive frames ≥ 0.85), with the same exit hysteresis. Pinch and pointer no longer depend on the classifier at all.

### 2.5 Feedback overlay
A borderless, click-through, non-activating panel that follows the cursor at display rate:
- hover: thin ring · pinch closing: ring shrinks with `pinchRatio` · pressed: filled dot · dragging: bold ring · scrolling: ring with direction ticks · Dock swipe: hidden (the Dock itself is the feedback).
- Hidden when idle/paused, honors Reduce Motion, never takes focus or clicks.

## 3. Architecture

```
capture queue (30 Hz)                                       output thread (display link, 120 Hz)
camera → Vision → Signal → GestureEngine ──intents──► IntentStore (Mutex) ──► OutputLoop ──► CGEvents / Dock
                     (PinchDetector, TouchRecognizer,                      ▲ MotionPredictor
                      DockSwipeRecognizer, engagement)                     └ overlay position/state
```

### 3.1 New / changed units
| Unit | Module | Responsibility |
|---|---|---|
| `MotionPredictor` | Signal | Constant-velocity model per 2D signal, updated at camera rate; `sample(at:)` interpolates/extrapolates for a display timestamp, horizon ≤ 33 ms, velocity decays to 0 below a speed floor (no overshoot on stop), resets on frame gaps > 0.25 s. |
| `PinchDetector` | GestureEngine | Ratios, hysteresis, confidence hold, press history for the click anchor. |
| `TouchRecognizer` | GestureEngine | The 2.1 state machine; emits touch intents. Replaces `SwipeRecognizer` and the two-finger `ScrollRecognizer` path in the default engine (both deleted once unused). |
| `PointerMapper` | GestureEngine | Gain curve, display clamping (display frames injected, testable). |
| `GestureEvent` | GestureEngine | Adds `.pointer(delta:)`, `.button(MouseButton, phase: down/up, clickCount:)`; scroll keeps `.continuous(.scroll, …)` but is produced by pinch. |
| `IntentStore` | Actions | Thread-safe latest intents (pointer velocity/target, scroll velocity, Dock progress target, overlay state) written at camera rate, read at display rate. |
| `OutputLoop` | Actions | On each display frame: advance predictors, emit `mouseMoved`/`leftMouseDragged` deltas, per-frame scroll pixels (phase-correct), Dock progress steps; owns all "smoothing in time". Discrete events (click, mouse down/up) pass straight through, ordered after any pending motion. |
| `CGEventSink` | Actions | Adds mouse move/down/up/dragged with click count; every event keeps the synthetic marker. |
| `CameraCapture` | Capture | Selects a 1280×720 30 fps `activeFormat` explicitly (falls back to the closest), instead of the session preset. |
| `CursorOverlay` | App | The 2.5 panel. |
| `Pipeline` | App | Starts/stops the display link with engagement (no 120 Hz work while idle); feeds `IntentStore`. |

### 3.2 Concurrency
Engine stays single-queue (capture queue). The output thread only reads `IntentStore` snapshots and owns the injectors' per-frame state; injectors move to the output thread (`ScrollInjector`, `DockSwipeInjector`), their tick timers are replaced by the display link. Cancellation (pause, typing, quit, stall watchdog) writes a cancel intent that the output loop applies on its next frame, plus the synchronous quit path from M3.5.

## 4. Error handling and edge cases
| Case | Behavior |
|---|---|
| Hand lost mid-drag / mid-scroll | 0.2 s grace, then mouse-up / scroll end (never a stuck button) |
| Pinch misread for 1–2 frames | Hysteresis + confidence hold; no click |
| Talking with hands | Clicks need engagement + a deliberate pinch (thresholds, max tap 0.25 s); replay-gated (0 clicks in normal-use) |
| Real mouse / trackpad / typing | Suppression (0.5 s) freezes the pointer and blocks presses; an active drag is released |
| Prediction overshoot when the hand stops | Velocity floor + decay; horizon ≤ 1 camera frame |
| Camera at 15 fps (idle mode) | Engaging restores 30 fps; predictor handles the longer frame interval |
| Multiple displays | Relative motion, clamped to the union of display frames |
| Accessibility revoked mid-drag | Cannot post mouse-up; next launch/grant starts clean (documented) |
| Display link unavailable | Fall back to a 120 Hz `DispatchSourceTimer` |

## 5. Testing
- **Unit (Swift Testing):** `MotionPredictor` (interpolation, extrapolation cap, stop decay, gap reset), `PinchDetector` (hysteresis, confidence hold, anchor lookup), `TouchRecognizer` (tap, double tap, right tap, scroll with momentum, hold-to-drag, cancel paths, slop), `PointerMapper` (gain curve, clamping), `OutputLoop` with a fake display clock (per-frame deltas sum to the camera-rate totals; no frame step above the predicted bound; discrete events ordered after motion).
- **Integration:** engine → dispatcher/output loop → `RecordingEventSink` for click, double click, right click, drag (mouse down/up pairing), scroll + momentum, and every exit path (hand lost, typing, pause, quit) — no unpaired mouse-down, no open scroll/Dock phase.
- **Replay:** user recordings through the new engine (`ec-replay`): pinch recording → pinch-closed share; normal-use held-out segment → 0 clicks, 0 drags.
- **Live (ec-probe):** pointer motion and overlay only; no live clicks without the user present.

## 6. Risks
| Risk | Mitigation |
|---|---|
| Prediction feels floaty | Short horizon, decay on stop, constants in one place, tuned live |
| Pinch thresholds vary by hand/camera distance | Ratio normalized by palm size; M5 adds per-user calibration in onboarding |
| Removing palm swipes surprises the user | Three-finger swipes cover Spaces/Mission Control with better feel; documented in release notes |
| Overlay window interferes with apps | `ignoresMouseEvents`, non-activating, `canJoinAllSpaces`, screen-saver level only while engaged |
