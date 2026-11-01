# EasyControl M4 — Touch & Smooth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hand-driven pointer where pinch acts like touch (tap = click, pinch-move = scroll, pinch-hold = drag), with all output rendered at the display's refresh rate so it feels smooth.

**Architecture:** The engine (capture queue, 30 Hz) emits *intents*: hand-anchor positions for the pointer, button events with a click-anchor time, scroll deltas, Dock deltas. A new `OutputLoop` (display link, 120 Hz) owns all smoothing in time — a `MotionPredictor` + exponential follower for the pointer, a rate smoother for scroll and Dock deltas — and posts CGEvents. Pinch is geometric (`PinchDetector`), the interaction state machine is `TouchRecognizer`, and `OutputLoop` replaces `ActionDispatcher`.

**Tech Stack:** Swift 6, Vision, CoreGraphics CGEvent, CADisplayLink (`NSScreen.displayLink`), SwiftUI/AppKit overlay panel, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-01-easycontrol-m4-touch-smooth-design.md`

## Global Constraints

- macOS 15+, Swift 6 strict concurrency; engine single-queue (capture queue); `OutputLoop` single-thread (output thread); cross-thread only through `Mutex`-guarded inboxes/snapshots.
- Camera: explicit 1280×720 `activeFormat` at 30 fps (fallback: closest ≥ 640×480).
- Pinch: `ratio = |thumbTip − indexTip| / palmSize` (isotropic); close < 0.22, open > 0.35 (calibrated in Task 8); tip confidence ≥ 0.3; confidence hold 0.2 s.
- Touch: tap ≤ 0.25 s and anchor travel < slop 0.015; hold 0.4 s → drag; double tap within 0.35 s and 0.02; right click = thumb+middle tap; click anchor look-back ≤ 0.12 s within a 0.15 s history.
- Pointer: relative, gain 0.6 below 0.15 frame-heights/s, linear to 2.5 at 1.2, flat above; anchor = index MCP; clamped to the union of display frames (CGEvent global coordinates, origin top-left of the main display, y down).
- Predictor horizon ≤ 0.033 s; follower τ = 0.025 s; rate smoother τ = 0.025 s.
- Engagement: open palm 0.3 s or three fingers 0.3 s; two-finger engage, open-palm swipes and two-finger scroll removed.
- Every synthetic event keeps `eventSourceUserData = 0x45430001`. No live clicks from tools without the user present.

## Review Focus

1. **Stuck mouse button** — any exit (hand lost, typing, pause, disengage, quit, stall) after a mouse-down must post mouse-up. Tests in Task 4 and Task 6.
2. **Accidental clicks** — pinch-like contact while talking or touching the face must not click when not engaged; replay gate on normal-use. Tests in Task 4 and Task 8.
3. **Pointer creep when the hand is still** — tremor must not drift the pointer. Test in Task 6.
4. **Click lands where aimed** — finger-closing motion must not move the click. Tests in Task 4 and Task 6.
5. **Multi-display coordinates** — clamping across displays with negative origins. Test in Task 3.

---

### Task 1: Capture format + motion predictor

**Files:** Modify `Sources/Capture/CameraCapture.swift`; create `Sources/Signal/MotionPredictor.swift`; tests `Tests/CaptureTests/CaptureTests.swift`, `Tests/SignalTests/MotionPredictorTests.swift`.

**Interfaces — Produces:**
- `CameraCapture.chooseFormat(_ formats: [(width: Int32, height: Int32, maxFPS: Double)], target: (Int32, Int32) = (1280, 720)) -> Int?` — exact target at ≥ 30 fps, else the smallest format ≥ 640×480 with ≥ 30 fps, else nil. `configure()` sets `activeFormat` from it (session preset `.inputPriority`).
- `public struct MotionPredictor: Sendable { init(horizon: Double = 0.033, speedFloor: Float = 0.02, resetGap: Double = 0.25); mutating func update(_ p: SIMD2<Float>, at t: Double); func sample(at t: Double) -> SIMD2<Float>?; mutating func reset() }` — constant velocity from the last two samples; extrapolation capped at `horizon`; below `speedFloor` returns the last sample; a gap > `resetGap` drops velocity.

- [ ] Tests: `formatPrefers720p`, `formatFallsBackToSmallest30fps`, `formatNilWhenNothing30fps`; `predictorExtrapolatesWithinHorizon` (p 0→0.1 over 1/30 s, sample at +0.01 ≈ 0.13), `predictorCapsAtHorizon`, `predictorHoldsWhenSlow`, `predictorResetsAfterGap`, `predictorNilBeforeFirstUpdate`.
- [ ] Fail → implement → pass (`scripts/test-core.sh`) → commit `feat: 720p capture format and motion predictor`.

### Task 2: Pinch detector + synthetic pinch hands

**Files:** Create `Sources/GestureEngine/TouchConfig.swift`, `Sources/GestureEngine/PinchDetector.swift`; modify `Sources/TestSupport/SyntheticHand.swift`; test `Tests/GestureEngineTests/PinchDetectorTests.swift`.

**Interfaces — Produces:**
- `public struct TouchConfig: Sendable` with the Global Constraints values: `closeRatio 0.22, openRatio 0.35, tipConfidence 0.3, confidenceHold 0.2, tapMax 0.25, holdTime 0.4, slop 0.015, doubleTapWindow 0.35, doubleTapDistance 0.02, anchorLookback 0.12, historyWindow 0.15`; `static let default`.
- `public struct PinchReading: Sendable, Equatable { var index: Bool; var middle: Bool; var ratio: Float }`
- `public struct PinchDetector { init(config: TouchConfig); mutating func update(_ hand: Hand, at t: Double) -> PinchReading? }` — hysteresis per finger; low tip confidence holds the last reading for `confidenceHold`, then nil.
- TestSupport: `SyntheticPose.pinch` (thumb tip on index tip, other fingers extended) and `.pinchMiddle`; `SyntheticHand.make(_:pinchOpenness:)` interpolating thumb tip from touching (0) to open (1).
- [ ] Tests: `pinchClosesAndOpensWithHysteresis` (openness 1 → 0.1 closes; back to 0.5 stays closed; 1 opens), `middlePinchIsSeparate`, `lowTipConfidenceHoldsThenCancels`, `ratioIsScaleInvariant`.
- [ ] Fail → implement → pass → commit `feat: geometric pinch detector`.

### Task 3: Pointer mapper

**Files:** Create `Sources/GestureEngine/PointerMapper.swift`; test `Tests/GestureEngineTests/PointerMapperTests.swift`.

**Interfaces — Produces:**
- `public struct PointerMapper: Sendable { init(speedMultiplier: Double = 1); func gain(speed: Double) -> Double; func pixels(handDelta: SIMD2<Float>, speed: Double, screenHeight: Double) -> SIMD2<Double>; static func clamp(_ p: CGPoint, to displays: [CGRect]) -> CGPoint }` — clamp to the nearest point inside any display.
- [ ] Tests: `gainCurve` (0.1 → 0.6, 1.2 → 2.5, 3 → 2.5, 0.675 ≈ midpoint 1.55), `pixelsScaleWithScreenHeight`, `clampAcrossDisplays` (main 0,0,1728×1117; second at −1920,−200,1920×1080; point (−2500, 500) → (−1920, 500); point between gaps → nearest display edge).
- [ ] Fail → implement → pass → commit `feat: accelerated relative pointer mapping`.

### Task 4: Touch recognizer + engine integration

**Files:** Create `Sources/GestureEngine/TouchRecognizer.swift`; modify `GestureEvent.swift`, `GestureEngine.swift`, `GestureConfig.swift`, `EngagementController.swift`; delete `SwipeRecognizer.swift`, `ScrollRecognizer.swift` and their tests (rewrite affected engine/integration tests to pinch); tests `Tests/GestureEngineTests/TouchRecognizerTests.swift`, `Tests/GestureEngineTests/GestureEngineTests.swift`.

**Interfaces — Produces:**
- `public enum MouseButton: Sendable { case left, right }`; `public enum ButtonAction: Sendable, Equatable { case click(count: Int), down, up }`.
- `GestureEvent` adds `.pointerTrack(position: SIMD2<Float>, at: Double)` (index MCP, isotropic), `.pointerLift`, `.button(MouseButton, ButtonAction, anchorTime: Double)`; scroll stays `.continuous(.scroll, phase, delta)` (delta isotropic, produced by pinch-move); `.discrete` remains for future use.
- `public struct TouchRecognizer { init(config: TouchConfig, gesture: GestureConfig); mutating func update(anchor: SIMD2<Float>?, pinch: PinchReading?, at t: Double) -> [GestureEvent]; mutating func cancel(at t: Double) -> [GestureEvent]; var isBusy: Bool /* pressed, scrolling or dragging */ }` — states hover/pressed/scrolling/dragging per spec §2.1; anchor time = start of the steady ratio fall before close, ≤ `anchorLookback`; scrolling uses `GestureHold` (0.2 s untracked → cancel); hand lost while dragging → `.button(.left, .up, …)`.
- Engine: in command mode, `three` (temporal evidence: mean prob over 150 ms > 0.7) drives `DockSwipeRecognizer`; otherwise `TouchRecognizer` gets the engaged hand's anchor and pinch; exclusive lock between touch-busy and Dock; `endGestures()` also calls `touch.cancel`. `GestureConfig.wakeHold = 0.3`; engagement direct poses = `[.three]`; standby resume poses = `[.openPalm, .three, .ok, .pinch]`.
- [ ] Tests (TouchRecognizer): `tapClicksAtAnchor` (anchor moves 0.01 while closing; event `.button(.left, .click(count: 1), anchorTime:)` with anchorTime at fall start), `doubleTapCountsTwo`, `middleTapRightClicks`, `pinchMoveScrollsThenEnds` (began/changed…/ended), `holdThenMoveDrags` (down, pointerTrack…, up), `handLostWhileDraggingReleasesButton`, `handLostWhileScrollingCancels`, `slowPinchHeldIsNotTap` (> 0.25 s still, < 0.4 s → no click), `hoverEmitsPointerTrack`, `pressFreezesPointer` (no pointerTrack while pressed).
- [ ] Tests (engine): `pinchTapAfterEngageClicks`, `pinchWhileNotEngagedDoesNothing`, `typingDuringDragReleasesButton`, `threeFingerDragStillWorks`, `pinchScrollBlocksDockSwipe`.
- [ ] Fail → implement → pass (whole suite, rewritten tests included) → commit `feat: pinch-as-touch recognizer in the engine`.

### Task 5: Mouse events in the sink

**Files:** Modify `Sources/Actions/SyntheticEvent.swift`, `CGEventSink.swift`; test `Tests/ActionsTests/MouseEventTests.swift`.

**Interfaces — Produces:**
- `public enum MouseKind: Sendable { case moved, leftDown, leftUp, leftDragged, rightDown, rightUp }`; `SyntheticEvent.mouse(MouseKind, x: Double, y: Double, clickCount: Int)`.
- `CGEventSink` builds `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)`, sets `.mouseEventClickState`, keeps the marker.
- [ ] Tests: `mouseEventsCarryPositionAndClickCount` (via `CGEventSink.makeEvent` returning a CGEvent: type, location, click state), `recordingSinkRecordsMouse`.
- [ ] Fail → implement → pass → commit `feat: synthetic mouse events`.

### Task 6: Output loop

**Files:** Create `Sources/Actions/OutputLoop.swift`, `Sources/Actions/RateSmoother.swift`, `Sources/Actions/PointerEnvironment.swift`; delete `ActionDispatcher.swift`, `Bindings.swift` (+ their tests; update `ec-probe`); tests `Tests/ActionsTests/OutputLoopTests.swift`, rewrite `PipelineIntegrationTests.swift`.

**Interfaces — Produces:**
- `public protocol PointerEnvironment: Sendable { func cursorLocation() -> CGPoint; func displayFrames() -> [CGRect]; func screenHeight() -> Double }`; `SystemPointerEnvironment` (CGEvent location, `CGGetActiveDisplayList`/`CGDisplayBounds`).
- `struct RateSmoother { init(tau: Double = 0.025); mutating func add(_ v: SIMD2<Double>); mutating func take(dt: Double) -> SIMD2<Double>; var pending: SIMD2<Double> }`.
- `public enum OverlayMode: Sendable { case hidden, hover, pressed, dragging, scrolling }`; `public struct OverlayState: Sendable, Equatable { var mode: OverlayMode; var position: CGPoint; var pinchRatio: Float }`.
- `public final class OutputLoop { init(sink: any EventSink, environment: any PointerEnvironment, spaces: any SpaceSwitchStrategy, mapper: PointerMapper = .init()); func receive(_ events: [GestureEvent], at t: Double); func step(at now: Double); func cancelAll(at t: Double); var needsFrames: Bool; var overlay: OverlayState }` — pointer: predictor ← `.pointerTrack`, follower (τ) per step, mapper → `.mouse(.moved/.leftDragged)` deltas at display rate, history of (t, position) for 0.3 s; `.pointerLift` resets predictor/follower; buttons: move to the anchor position (history lookup) then post down/up (click count); scroll: isotropic deltas → pixels into `RateSmoother`, emitted per step as scroll `.changed`, ended → momentum via `ScrollInjector` ticked by `step`; Dock deltas through a second `RateSmoother` into `DockSwipeInjector`; `cancelAll` posts mouse-up if down, cancels scroll and Dock.
- `OutputInbox` (Mutex) for cross-thread `receive`.
- [ ] Tests: `pointerMovesEveryFrameBetweenCameraSamples` (camera samples at 30 Hz, steps at 120 Hz → every step moves, total ≈ mapped total), `stillHandWithTremorDoesNotCreep` (±0.002 noise for 1 s → < 2 px), `clickLandsAtAnchorPosition` (pointer moved after anchor time; click posted at historical position), `dragPostsDraggedBetweenDownAndUp`, `scrollIsSpreadAcrossFrames` (one 18 px camera delta → several smaller frame deltas summing to 18), `dockDeltasSpreadAcrossFrames`, `cancelAllReleasesHeldButton`, `needsFramesFalseWhenIdle`.
- [ ] Integration (rewrite): engine → `OutputLoop` → `RecordingEventSink`: `pinchFlickCoastsWithMomentum`, `typingMidPinchScrollPostsNoMomentum`, `pauseDuringDragReleasesButton`.
- [ ] Fail → implement → pass → commit `feat: display-rate output loop`.

### Task 7: App — display link, overlay, wiring

**Files:** Create `App/CursorOverlay.swift`, `App/DisplayLinkDriver.swift`; modify `App/Pipeline.swift`, `App/Views/DebugView.swift`.

**Interfaces — Produces:**
- `DisplayLinkDriver` — dedicated thread with a run loop hosting `NSScreen.main?.displayLink(target:selector:)` (fallback `DispatchSourceTimer` at 120 Hz); `start()`/`stop()`; calls `onFrame(timestamp)`.
- Pipeline: engine events → `OutputInbox`; driver frame → drain inbox → `OutputLoop.step`; driver runs while engaged or `needsFrames`; overlay snapshot published (Mutex) for the UI; pause/typing/quit/watchdog call `cancelAll` on the output thread (quit synchronously).
- `CursorOverlay` — borderless non-activating `NSPanel`, `ignoresMouseEvents`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, level `.statusBar`; CAShapeLayer ring drawn per spec §2.5, follows `NSEvent.mouseLocation` via main-thread display link; hidden when mode `.hidden`; honors Reduce Motion.
- [ ] `scripts/build-app.sh` succeeds; smoke run (process stays up 8 s); commit `feat(app): display-link output, cursor overlay`.

### Task 8: Calibration and replay gate

**Files:** Modify `Sources/GestureEngine/ReplayBenchmark.swift`, `Sources/ec-replay/main.swift`; create `Sources/ec-replay/PinchStats.swift` (or a `--pinch-stats` mode); test `Tests/GestureEngineTests/ReplayBenchmarkTests.swift`.

**Interfaces — Produces:**
- `ReplayStats` gains `clicks`, `drags`; `actionsPerHour` counts clicks + drags + scrolls + Dock swipes.
- `ec-replay --pinch-stats <files>` prints per file the distribution (p5/p50/p95) of the pinch ratio and the closed share — aggregates only.
- [ ] Test: `statsCountClicksAndDrags` (scripted tap and hold-drag).
- [ ] Run pinch stats on the user's recordings; set `closeRatio`/`openRatio` so the `pinch` recording's formed frames read closed ≥ 98 % and `none`/`normal-use` ≤ 0.5 %; record the numbers (aggregates) in `docs/eval/m4-pinch-calibration.md`; replay normal-use test segment → 0 clicks, 0 drags.
- [ ] Commit `feat: pinch calibration and replay gate`.

### Task 9: Docs, verification

- README gesture table (pinch = touch, three fingers), QA checklist §M4 (tap, double, right, scroll + momentum, drag text, overlay, smoothness at 120 Hz), memory; full suites, app build, CI green; final review → fixes; commit `docs: M4 touch & smooth`.
