# M0 Spike Results

Date: 2026-10-29 · Machine: MacBook Pro, Apple M1 Pro, 16 GB · macOS 27.0.1 · Xcode 27.1 / Swift 6.4

Spike sources (throwaway, kept for reproducibility): `tools/spikes/`.

## 1. Space switching via synthetic keystrokes

`tools/spikes/space_switch.swift` posts key events to `.cghidEventTap` and reads the active Space with the private `CGSGetActiveSpace` (spike only).

| Variant | Right | Left |
|---|---|---|
| Ctrl + ←/→ (`maskControl` only) | did not switch | did not switch |
| Ctrl + ←/→ with `maskControl \| maskSecondaryFn \| maskNumericPad` | **switched** | (returned) |

**Decision:** `ControlArrowStrategy` posts keycodes 123/124 with flags `maskControl | maskSecondaryFn | maskNumericPad` (real arrow keys carry the Fn and NumPad flags; the Space hotkey only matches with them). Ctrl+digit and private CGS strategies are not needed for v1. The user's "Move left/right a space" (symbolic hotkeys 79–82) and Mission Control / App windows (32/33) shortcuts are enabled on this Mac; onboarding must check these on other Macs.

## 2. Vision hand-pose latency

`tools/spikes/vision_bench.swift` on 60 HaGRID 512px images (palm, peace, fist, one × 15; 512×683), 5 timed runs each after warm-up, `maximumHandCount = 2`.

| API | p50 | p95 | CPU per image | Detected (≥15 joints > 0.3) |
|---|---|---|---|---|
| `VNDetectHumanHandPoseRequest` | 18.3 ms | 28.8 ms | 6.8 ms | 59/60 |
| `DetectHumanHandPoseRequest` (Swift API) | 18.7 ms | 29.1 ms | 6.8 ms | 59/60 |

Per class (legacy): fist 15/15, one 14/15, palm 15/15, peace 15/15. Chirality reported for every detection (46 right, 33 left).

**Decision:** use `VNDetectHumanHandPoseRequest`, performed synchronously on the capture queue — identical performance, and a synchronous call keeps the whole per-frame pipeline on one serial queue without async hops.

**Latency budget check:** camera ≤ 33 ms + Vision p95 29 ms + engine/injection ~3 ms ≈ 65 ms → inside the 70 ms p95 target, with little headroom. Live camera numbers must confirm.

**CPU:** 6.8 ms CPU per frame ⇒ ~20 % of one core at 30 fps, ~7 % at the 10 fps idle rate. That is ~2 % / ~0.7 % of the whole 10-core machine. The spec's "≤ 15 % engaged" target is read as Activity Monitor's per-process figure (100 % = one core); 30 fps tracking alone is ~20 %, so the target needs either 24 fps while engaged or a revised target — to be decided with live measurements.

## 3. Pending live checks (need the user at the camera)

- Vision `chirality` vs the user's actual hand after our mirroring (raise right hand → overlay shows "right" on the right).
- End-to-end latency p50/p95 from the debug window.
- Real CPU % in Activity Monitor while idle (10 fps) and engaged (30 fps).
- Mission Control / App Exposé via Ctrl+↑/↓ with the same flags: posted by `ec-probe`, but opening could not be confirmed headlessly (window list shows no change without Screen Recording permission) — confirm visually.
- Scroll direction/feel of `ec-probe scroll-demo down|up` in a real app (events are posted with phases and momentum; 45 momentum ticks after a 400 px drag).

## 4. Live checks through the real Actions layer (Task 10, `ec-probe`)

| Check | Result |
|---|---|
| `ec-probe space right` / `left` | Space 262 → 2720 → 262 ✔ |
| `ec-probe monitor-selftest` | own (marked) events ignored ✔, unmarked events seen ✔ |
| `ec-probe scroll-demo down/up` | posted 400 px + 45 momentum ticks each; visual check pending |
| `ec-probe mission-control` | posted; visual check pending |

Finding: events posted immediately before a process exits can be dropped — `ec-probe` now waits 0.3 s after posting. Not an issue for the long-running app.

## 5. Finger-following Dock swipes (2026-10-30, `tools/spikes/dock_swipe.swift`)

Recipe from Grabby's research notes (MIT, https://github.com/govindup63/grabby, `specs/001-mouse-action-button/research.md`): an `IOHIDEvent` of type 23 (Dock Swipe) with motion / flavor / progress fields and phase in the options (`phase << 24`), attached to a type-30 `CGEvent` with SkyLight's `SLEventSetIOHIDEvent`, posted at the session tap; on end, a child Velocity event (type 9).

| Flavor | Progress sign | Result |
|---|---|---|
| 3 | + (0 → 1.2 over 0.5 s) | Space 262 → 7 (one to the **left**, i.e. natural direction: hand right shows the left Space) ✔ |
| 3 | − | 7 → 262 ✔ |
| 1 | ± | no change |

**Decision:** flavor 3; progress sign = hand's horizontal travel (natural). All symbols (`IOHIDEventCreate`, `IOHIDEventSetIntegerValue`, `IOHIDEventSetFloatValue`, `IOHIDEventSetEventFlags`, `IOHIDEventAppendEvent`, `SLEventSetIOHIDEvent`) resolve via `dlsym` on macOS 27.0.1. Vertical (Mission Control) motion = 2, to be confirmed visually.
