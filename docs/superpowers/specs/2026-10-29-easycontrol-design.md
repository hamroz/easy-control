# EasyControl — Design Spec

- **Date:** 2026-10-29
- **Status:** Draft, awaiting review
- **Platform (v1):** macOS 15+ on Apple Silicon MacBooks (built-in front camera). Intel Macs and external cameras are not targeted in v1 but are not deliberately blocked.

## 1. Intent

### What the owner asked for
- A standalone macOS app that uses the front camera to recognize hand gestures and control the system: scrolling, switching Spaces, Mission Control, and similar.
- Everything runs on-device at runtime. No LLMs, no cloud services, no network calls.
- Free, openly licensed models and datasets may be used, but the product must be the owner's own work (portfolio project), not a wrapper around an existing gesture app.
- "Advanced": edge cases thought through, not a toy demo.
- v1 assumes five fingers per hand. Accessibility for other hand configurations, and Linux/other OSes, are later phases.

### Decisions made during brainstorming
| Decision | Choice |
|---|---|
| Core experience | **Both** command gestures and full cursor control ("air trackpad") in v1 |
| Engagement | **Wake pose + guards** (open palm hold to engage, idle disengage, typing suppression, hotkey override) |
| Customization | **Remap any gesture to any action + record custom static poses** on-device |
| Architecture | **Native Swift + Apple Vision landmarks + own gesture engine** |
| Licence | Open source: code MIT; model weights trained with HaGRID data CC BY-SA 4.0 |

### Success criteria
- p95 latency from hand motion to injected system event **< 70 ms** on an M1 Pro.
- Built-in pose classifier **≥ 97 %** accuracy on held-out subjects.
- **< 1 false action per hour** of normal computer use (typing, talking, gesturing while speaking) in the replay benchmark.
- Idle CPU **≤ 5 %**, engaged CPU **≤ 15 %** on M1 (to be validated in M0; adjust targets with evidence).
- Zero frames or images persisted or transmitted during normal operation.

### Non-goals (v1)
- Custom *motion* gestures (custom gestures are static poses only).
- Mac App Store distribution (sandbox forbids event injection).
- Windows/Linux, external/iPhone Continuity cameras as first-class targets.
- Hand configurations other than five fingers per hand.
- Face/eye tracking, voice control.

## 2. Architecture

One menu-bar `.app` built from Swift packages with single responsibilities. Swift 6 strict concurrency throughout. No heavy work on the main thread.

```
Camera ──► Capture ──► HandTracking ──► Signal ──► GestureEngine ──► Actions ──► macOS
 (AVF)    (frames)    (HandFrame)     (features)  (GestureEvent)   (CGEvent etc.)
                                                        ▲
                                         Bindings / Settings (App)
```

### 2.1 Modules

**Capture** — AVFoundation front camera.
- 640×480 @ 30 fps nominal; drops to ~10 fps after 5 s with no hand detected; restores on first detection.
- Handles: camera unavailable/busy, lid closed, system sleep/wake, device disconnect. Emits a `CaptureState` stream the App observes.

**HandTracking** — Apple Vision `DetectHumanHandPoseRequest`, max 2 hands.
- Output type (pure value, no Vision types leak out):
  ```swift
  struct HandFrame { let timestamp: TimeInterval; let hands: [Hand] }
  struct Hand { let chirality: Chirality; let joints: [JointName: Joint] } // 21 joints
  struct Joint { let x: Float; let y: Float; let confidence: Float }     // normalized image coords
  ```
- Behind `protocol HandLandmarkSource: AsyncSequence<HandFrame>` so a MediaPipe/Linux source or a file replay source can be substituted.

**Signal** — turns raw landmarks into stable features.
- One Euro filter per joint (tunable min-cutoff / beta).
- Hand identity tracking across frames (nearest-centroid + chirality), producing stable `HandID`s.
- Normalization: translate to wrist, scale by palm size (wrist→middle MCP), rotate to canonical orientation; left hands mirrored to right.
- Features: 42 normalized coordinates, finger joint angles, fingertip-to-fingertip and fingertip-to-palm distances, per-finger extension flags, palm-facing estimate, hand scale (proxy for distance), velocity of palm centre.

**GestureEngine** — pure Swift (Core ML is the only framework dependency), fully testable from landmark sequences.
- `PoseClassifier` — Core ML MLP over features → per-frame class probabilities; temporal hysteresis (enter ≥ 0.85 over N frames, exit < 0.60).
- `CustomPoseMatcher` — k-NN over normalized feature vectors with a per-pose distance threshold.
- `MotionRecognizers` — state machines: `SwipeRecognizer`, `ScrollRecognizer`, `PinchRecognizer` (tap/double/hold-drag), `CursorTracker`, `TwoHandZoomRecognizer`.
- `EngagementController` — state machine (§3.1).
- `Arbiter` — resolves conflicts by priority; a running continuous gesture holds an exclusive lock until it ends.
- Output:
  ```swift
  enum GestureEvent {
    case discrete(GestureID)
    case continuous(GestureID, phase: Phase, delta: SIMD2<Float>)   // began / changed / ended
    case cursor(position: SIMD2<Float>)
    case engagement(EngagementState)
  }
  ```

**Actions** — maps `GestureEvent` → system effect via the bindings table.
- `protocol EventSink` with a real `CGEventSink` and a `RecordingEventSink` for tests.
- Executors: `ScrollInjector`, `PointerInjector`, `KeyShortcutInjector`, `SystemKeyInjector` (media/volume/Mission Control), `SpaceSwitcher` (strategy, §4.1), `AppLauncher`, `ShellCommandRunner`.

**App (SwiftUI)**
- Menu-bar extra with state icon (paused / idle / engaged / cursor mode / warning).
- Onboarding: permissions, Mission Control shortcut check, dominant-hand choice, quick tutorial.
- Settings: bindings editor, sensitivity sliders, auto-pause app list, hotkey.
- Custom pose recorder.
- HUD: short on-screen toast naming each recognized gesture / action.
- Debug window: live camera preview with skeleton overlay, per-class probabilities, engagement state, latency readout. Also the landmark recorder for training data.

**tools/ (Python, managed with uv)** — never shipped. Data conversion, training, Core ML export, evaluation report. Includes a small Swift CLI (`tools/vision-extract`) that runs Apple Vision over image datasets to extract landmarks.

### 2.2 Latency budget (p95)
| Stage | Budget |
|---|---|
| Camera capture | ≤ 33 ms |
| Vision inference | ~10–20 ms (measure in M0) |
| Signal + GestureEngine | < 2 ms |
| Event injection | < 1 ms |
| **Total target** | **< 70 ms** |

Instrumented with `os_signpost` per stage; the debug window shows a live p50/p95.

## 3. Interaction design

### 3.1 Engagement
States: `paused → idle → engaged(command | cursor) → idle`.

- **Engage:** open palm facing camera, held ~400 ms, hand scale above a distance threshold (~arm's length). Confirmed by HUD + menu-bar icon (optional sound).
- **Disengage:** 3 s with no recognized gesture, engaged hand lost > 1 s, or hotkey.
- **Guards (always active):**
  - Suppress all gestures for ~500 ms after any keyboard or trackpad/mouse input (observed via a listen-only event tap).
  - Ignore joints / hands below confidence thresholds.
  - Lock to the engaged `HandID`; ignore other hands and people (except the second hand in a two-hand gesture, which must also pass the scale threshold).
  - ~400 ms cooldown after each discrete action.
- **Hotkey:** user-configurable global hotkey toggles force-engage / pause.

### 3.2 Built-in pose classes
`open_palm, fist, point, two (V), three, pinch, ok, thumbs_up, thumbs_down, none`. The `none` class is trained on everyday hand activity and is the main defence against false triggers.

### 3.3 Command mode (default when engaged) — all bindings remappable
| Gesture | Default action |
|---|---|
| `two` pose + move up/down/left/right | Continuous scroll with phases; momentum on release |
| `open_palm` fast swipe left / right | Switch Space left / right |
| `open_palm` swipe up / down | Mission Control / App Exposé |
| `fist` hold 0.5 s | Play/Pause |
| `thumbs_up` / `thumbs_down` hold | Volume up / down, auto-repeat while held |
| Both hands `pinch`, spread / close | Zoom in / out (⌘= / ⌘−) |
| `point` hold 0.6 s | Enter cursor mode |
| Custom pose hold 0.4 s | User-bound action |

### 3.4 Cursor mode
- Pointer follows the **index MCP** (knuckle), not the fingertip, for stability during pinches.
- Absolute mapping from a configurable "comfort box" in camera space to the display under the pointer (option: span all displays). One Euro smoothing + small dead zone.
- **Click anchoring:** pointer position freezes when a pinch begins closing, so the click lands where aimed.
- Thumb+index pinch tap → left click; double pinch → double-click (correct click count); pinch hold + move → drag; thumb+middle pinch → right click.
- `two` pose scroll still works.
- `open_palm` or idle timeout returns to command mode.
- If tracking is lost mid-drag, a mouse-up is injected so no button stays stuck.

### 3.5 Custom poses
- Recorder: hold the pose ~3 s; ~10 feature-vector samples captured with slight variations.
- Stored locally (Application Support, JSON). k-NN match with per-pose threshold derived from sample spread.
- Recorder warns when the new pose is too close to a built-in or existing custom pose.

### 3.6 Handedness
Either hand works. Left hands are mirrored before classification so one model serves both. Dominant hand is a setting. Directions are expressed from the user's mirrored perspective (swipe left = user's left).

## 4. System integration

### 4.1 Event injection
- **Scroll:** `CGEvent` scroll-wheel events in pixel units with `scrollPhase` / `momentumPhase` populated to mimic a trackpad (smooth scrolling, rubber-banding).
- **Pointer:** `CGEvent` mouse move / down / up / dragged, with `mouseEventClickState` for multi-clicks.
- **Spaces** — `SpaceSwitcher` with ordered strategies, chosen by the M0 spike on macOS 27:
  1. Synthesized Ctrl+←/→.
  2. Ctrl+N ("Switch to Desktop N" shortcuts) with tracked current-Space index.
  3. Private CoreGraphics (CGS) Space APIs as last resort — permitted outside the App Store; isolated behind the strategy interface because it can break on OS updates.
  Onboarding checks the required Mission Control shortcuts are enabled and guides the user if not.
- **Mission Control / media / volume:** NX system-defined key events (as sent by the F-row).
- **Secure Event Input:** detect via `IsSecureEventInputEnabled()`; when active, keystroke-based actions show a HUD notice instead of silently failing.

### 4.2 Permissions
- **Camera** (TCC) and **Accessibility** (event posting + listen-only tap).
- Onboarding explains each, deep-links to the right System Settings pane, and polls for grant (no relaunch).
- Revocation at runtime → app pauses and surfaces a clear menu-bar warning.

### 4.3 Privacy
- Frames processed in memory only; never written to disk, never transmitted. The app makes no network requests.
- Landmark recording for training is a separate, explicit opt-in tool in the debug window and stores landmarks only, never images.
- **Auto-pause** on: screen lock, display sleep, lid close, system sleep, or when a user-listed app is frontmost. One-click pause in the menu bar. The camera indicator light is off whenever paused.

### 4.4 Distribution
Developer ID–signed, hardened runtime, notarized DMG. Not sandboxed (required for event injection).

## 5. Error handling and edge cases

| Case | Handling |
|---|---|
| Low light / strong backlight | Low-confidence frames ignored; persistent low confidence → "Low light" menu-bar warning |
| Other people in frame | Locked to engaged hand; small (distant) hands ignored |
| Hand partially out of frame | Require wrist + key joints above confidence threshold |
| Typing / trackpad use | Suppression window (§3.1) |
| Competing gestures | Arbiter priority; continuous gestures hold an exclusive lock |
| Secure input (password fields) | Detected; HUD notice |
| Camera busy / disconnected / lid closed | Pause, retry with backoff, auto-resume |
| Multiple displays | Cursor maps to display under pointer; optional span-all |
| Tracking lost mid-drag | Inject mouse-up |
| Thermal / CPU pressure | Reduce frame rate before degrading quality; observe `ProcessInfo.thermalState` |
| Permission revoked | Pause + warning; resume automatically when re-granted |
| Space-switch strategy fails | Fall back to next strategy; surface a one-time diagnostic in settings |

## 6. ML pipeline (`tools/`)

1. **Data sources**
   - Owner recordings via the in-app landmark recorder: multiple sessions, lighting conditions, distances, both hands.
   - `none`-class recordings during normal use (typing, talking, drinking, face touching).
   - HaGRID images run through Apple Vision offline (`tools/vision-extract`) so training landmarks come from the same detector as runtime.
2. **Features** — identical code path to the Swift `Signal` module; parity enforced by a shared fixture test (same input → same feature vector in Swift and Python, within tolerance).
3. **Model** — small MLP (~2 hidden layers) in PyTorch, exported with `coremltools`. Create ML hand pose classifier trained as a comparison baseline; results documented in the README.
4. **Evaluation report** — per-class precision/recall, confusion matrix on **held-out subjects**, and the false-trigger replay benchmark (false actions per hour on recorded normal-use sessions).
5. **Targets** — ≥ 97 % held-out accuracy; < 1 false action per hour.

## 7. Testing

- **Unit (Swift Testing):** One Euro filter, normalization/mirroring, feature extraction, `EngagementController`, each motion recognizer, `Arbiter`, `CustomPoseMatcher` — driven by synthetic landmark sequences.
- **Replay tests:** recorded `HandFrame` sessions + golden expected `GestureEvent` logs; a `ReplayLandmarkSource` feeds the full engine.
- **Actions:** `RecordingEventSink` asserts the exact CGEvents that would be posted. Real-injection manual QA checklist: Safari, Chrome, Finder, Xcode, a fullscreen app, multi-display.
- **Feature parity:** Swift ↔ Python feature-extraction fixture test.
- **Performance:** signpost-based latency checks; Instruments profiling per milestone.
- **CI:** GitHub Actions macOS runner — build + all tests (no camera required).

## 8. Repository layout

```
easy-control/
  App/                         Xcode app target (SwiftUI, menu bar, onboarding, settings, debug)
  Packages/EasyControlCore/
    Sources/Capture/
    Sources/HandTracking/
    Sources/Signal/
    Sources/GestureEngine/
    Sources/Actions/
    Tests/…
  tools/                       Python (uv): training, export, evaluation; vision-extract Swift CLI
  docs/                        specs, plans, evaluation reports
```

## 9. Milestones

Each milestone ends in something runnable.

| # | Scope | Exit criteria |
|---|---|---|
| **M0** | Spike (throwaway): Vision latency/CPU on M1 Pro; which Space-switch strategy works on macOS 27 | Measured numbers + chosen strategy recorded in `docs/` |
| **M1** | Capture + HandTracking + debug window with skeleton overlay | Live skeleton at ≥ 25 fps |
| **M2** | Signal, engagement, rule-based bootstrap poses, scroll + Space swipe actions, menu bar, permissions | First daily-usable build |
| **M3** | Landmark recorder, training pipeline, Core ML classifier replaces rules, evaluation report | Report meets accuracy / false-trigger targets |
| **M4** | Cursor mode (move, click anchoring, click/double/right/drag) | QA checklist passes |
| **M5** | Bindings editor, custom pose recorder + matcher, two-hand zoom | Custom pose bound and working end to end |
| **M6** | Onboarding polish, auto-pause rules, HUD, signed + notarized DMG, README with demo GIF | Fresh-Mac install works from DMG |

## 10. Risks

| Risk | Mitigation |
|---|---|
| Vision accuracy/latency insufficient for cursor precision | Measured in M0; One Euro tuning; MediaPipe→Core ML source can be added behind `HandLandmarkSource` |
| No synthesized Space-switch method works on macOS 27 | Strategy chain incl. private CGS fallback; verified in M0 |
| False triggers make it annoying | Engagement gate, typing suppression, `none` class, replay benchmark as a release gate |
| Private APIs break on OS update | Isolated in one strategy; graceful fallback + diagnostic |
| HaGRID share-alike licence | Weights licensed CC BY-SA 4.0; option to train on owner data only |

## 11. Later phases (out of scope for v1)
- Accessibility: configurable pose sets for different hand configurations, one-handed modes, dwell-click.
- Custom motion gestures.
- Linux (and possibly Windows) via a MediaPipe `HandLandmarkSource` and platform-specific `EventSink`s.
- External / Continuity Camera support as first-class.

## 12. Addendum (2026-10-30): trackpad feel, after the first live session

Findings from the user's recordings (10 min normal use, one ~35 s recording per pose): 0 false actions; left/right swipes needed ~1.8× the hand travel of up/down because the camera is 16:9 and motion was measured in frame fractions; the HaGRID-trained model often misread the user's two-finger, point, three and fist poses.

Decisions (user, 2026-10-30):
- **Three fingers = the trackpad's three-finger swipe.** Holding the `three` pose and moving drags the Spaces strip (horizontal) or Mission Control / App Exposé (vertical) *with the hand*, using the Dock's own swipe events (private Dock Swipe IOHIDEvent via SkyLight, verified on macOS 27 in `docs/spikes/m0-results.md` §5). Releasing the pose lets the Dock commit or snap back by velocity, as on a trackpad. If the private symbols are unavailable, the gesture falls back to the existing Ctrl+Arrow / Mission Control keys on release. Open-palm quick swipes stay as a secondary gesture.
- **Re-engagement — both:** after engagement ends because the hand left or went idle, the session waits in **standby for 15 s**; in standby a hand moving *into* a gesture pose (open palm, two, three) resumes instantly, with no hold. From idle, holding two or three fingers for 0.3 s engages directly, as does the 0.4 s open palm.
- Motion (swipes, scroll, Dock swipes) is measured in aspect-corrected units.
- The pose model is personalized with the user's recordings (added as an extra subject, evaluated on held-out time segments), which also adds the `pinch` class.
