# EasyControl M0–M2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the first daily-usable EasyControl build: a menu-bar app that sees your hand, engages on an open palm, scrolls with a two-finger pose, and switches Spaces / opens Mission Control with palm swipes.

**Architecture:** A SwiftPM package `EasyControlCore` holds pure, testable modules (`HandTracking` types → `Signal` → `GestureEngine` → `Actions`) plus Apple-only `Capture` (AVFoundation + Vision). A thin SwiftUI menu-bar app (generated with XcodeGen) wires camera → Vision → engine → CGEvent injection on one serial capture queue. M2 uses a rule-based pose classifier; M3 (separate plan) replaces it with Core ML.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AVFoundation, Vision, CoreGraphics `CGEvent`, Swift Testing, XcodeGen, Python 3 + uv (spike data fetch only), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-29-easycontrol-design.md` (milestones M0, M1, M2 in §9).

## Global Constraints

- Deployment target: **macOS 15.0**; Apple Silicon; built-in front camera.
- Package `swift-tools-version: 6.0`, Swift 6 language mode, no third-party Swift dependencies.
- No network calls from the app. Frames are never written to disk. The landmark recorder writes landmarks only.
- Not sandboxed; hardened runtime on; entitlement `com.apple.security.device.camera`; `LSUIElement = YES`; `NSCameraUsageDescription` set.
- Normalized coordinate convention everywhere after `HandTracking`: origin **top-left**, x **mirrored** so +x is the *user's* right, +y is down, range 0…1.
- Every synthetic `CGEvent` we post sets `eventSourceUserData = 0x45430001` ("EC") so our own listen-only tap ignores it.
- Latency target p95 < 70 ms motion→event; engagement defaults from spec §3.1: wake hold 0.4 s, idle timeout 3 s, hand-lost 1 s, input suppression 0.5 s, discrete cooldown 0.4 s, pose hysteresis enter ≥ 0.85 / exit < 0.60.
- Commit after every task; push to `origin main` at the end of each task.

## Review Focus

1. **Hand lost mid-scroll** — a scroll in progress must emit `.ended` (and momentum must start/stop cleanly), never leave a scroll "open". Test in Task 8.
2. **A second hand / another person appears while engaged** — events come only from the engaged `HandID`; the other hand can neither scroll nor swipe. Test in Task 8.
3. **Typing with a hand visible** — any real keyboard/mouse input within 0.5 s suppresses all gesture events, including mid-gesture (scroll ends). Test in Task 8.
4. **Frame gaps (dropped frames, sleep/wake, low-fps mode)** — a gap > 0.25 s resets filters/velocity so no phantom swipe fires from the jump. Tests in Task 3 and Task 7.
5. **Low-confidence or partial hands** — frames whose wrist or required joints are below 0.3 confidence produce no pose and no events. Test in Task 4 and Task 8.

---

## File Structure

```
project.yml                                   XcodeGen spec for the app
scripts/build-app.sh                          xcodegen + xcodebuild, picks signing identity
.github/workflows/ci.yml                      swift test + app build
App/
  EasyControlApp.swift                        @main, MenuBarExtra, windows
  AppModel.swift                              @MainActor @Observable UI state
  Pipeline.swift                              camera→vision→engine→dispatcher on capture queue
  Permissions.swift                           camera/accessibility status + requests
  AutoPause.swift                             lock/sleep observers
  Views/MenuContent.swift
  Views/PermissionsView.swift
  Views/DebugView.swift                       preview + skeleton overlay + stats + recorder
  Resources/Info.plist, EasyControl.entitlements, Assets.xcassets
Packages/EasyControlCore/
  Package.swift
  Sources/HandTracking/   JointName.swift, HandFrame.swift, HandFrameRecording.swift
  Sources/Signal/         OneEuroFilter.swift, HandIdentityTracker.swift, HandNormalizer.swift, HandFeatures.swift
  Sources/GestureEngine/  GestureConfig.swift, PoseClass.swift, RuleBasedPoseClassifier.swift, PoseStabilizer.swift,
                          EngagementController.swift, ScrollRecognizer.swift, SwipeRecognizer.swift,
                          GestureEvent.swift, GestureEngine.swift
  Sources/Actions/        SyntheticEvent.swift, EventSink.swift, CGEventSink.swift, ScrollInjector.swift,
                          SpaceSwitcher.swift, Bindings.swift, ActionDispatcher.swift, InputActivityMonitor.swift
  Sources/Capture/        CameraCapture.swift, VisionHandDetector.swift, RollingPercentiles.swift
  Sources/TestSupport/    SyntheticHand.swift, FrameScript.swift
  Sources/ec-probe/       main.swift   (live-injection CLI for QA)
  Tests/{HandTrackingTests,SignalTests,GestureEngineTests,ActionsTests,CaptureTests}/
tools/spikes/             M0 throwaway: space_switch.swift, vision_bench.swift, fetch_sample.py
docs/spikes/m0-results.md
docs/qa/m2-checklist.md
```

---

### Task 1: Package scaffold + HandTracking value types + recording codec + CI

**Files:**
- Create: `Packages/EasyControlCore/Package.swift`, `Sources/HandTracking/{JointName,HandFrame,HandFrameRecording}.swift`, `Sources/TestSupport/{SyntheticHand,FrameScript}.swift`, `Tests/HandTrackingTests/HandFrameTests.swift`, `.github/workflows/ci.yml`

**Interfaces:**
- Produces:
  - `public enum JointName: Int, CaseIterable, Codable, Sendable` — 21 cases in this order: `wrist, thumbCMC, thumbMP, thumbIP, thumbTip, indexMCP, indexPIP, indexDIP, indexTip, middleMCP, middlePIP, middleDIP, middleTip, ringMCP, ringPIP, ringDIP, ringTip, littleMCP, littlePIP, littleDIP, littleTip`. Static `fingers: [[JointName]]` (thumb…little, base→tip).
  - `public enum Chirality: String, Codable, Sendable { case left, right, unknown }`
  - `public struct Joint: Codable, Sendable, Equatable { var position: SIMD2<Float>; var confidence: Float }`
  - `public struct Hand: Codable, Sendable, Equatable { var chirality: Chirality; var joints: [Joint] /* count 21, indexed by JointName.rawValue */; subscript(_: JointName) -> Joint }`
  - `public struct HandFrame: Codable, Sendable, Equatable { var timestamp: TimeInterval; var hands: [Hand] }`
  - `public protocol HandLandmarkSource: Sendable { var frames: AsyncStream<HandFrame> { get } }`
  - `public enum HandFrameRecording { static func encode(_ frames: [HandFrame]) throws -> Data /* JSON Lines */; static func decode(_ data: Data) throws -> [HandFrame] }`
  - TestSupport: `public enum SyntheticPose { case openPalm, fist, point, two, three }`; `public enum SyntheticHand { static func make(_ pose: SyntheticPose, center: SIMD2<Float> = [0.5, 0.5], palmSize: Float = 0.12, chirality: Chirality = .right, confidence: Float = 1) -> Hand }`; `public struct FrameScript` — builder producing `[HandFrame]` at a given fps: `init(fps: Double = 30, start: TimeInterval = 0)`, `mutating func hold(_ pose: SyntheticPose, at center: SIMD2<Float>, for seconds: Double, palmSize: Float = 0.12)`, `mutating func move(_ pose: SyntheticPose, from: SIMD2<Float>, to: SIMD2<Float>, over seconds: Double)`, `mutating func empty(for seconds: Double)`, `mutating func gap(_ seconds: Double)`, `var frames: [HandFrame]`. Multi-hand variant: `mutating func append(_ hands: [Hand], for seconds: Double)`.

Package targets: `HandTracking`, `Signal`(→HandTracking), `GestureEngine`(→Signal), `Actions`(→GestureEngine), `Capture`(→HandTracking), `TestSupport`(→HandTracking), executable `ec-probe`(→Actions); test targets per module depending on their module + `TestSupport`. Products: library `EasyControlCore` exposing HandTracking, Signal, GestureEngine, Actions, Capture.

SyntheticHand geometry: wrist at `center + [0, palmSize]`; MCPs spaced across `center.y`, x from `center.x - 0.4·palmSize` (index) to `+0.4·palmSize` (little) for a right hand seen mirrored (flip for left); extended finger = 3 segments of `0.35·palmSize` straight up (−y); folded finger = PIP up `0.2·palmSize`, DIP and tip curled back down toward the wrist ending ~`0.15·palmSize` below MCP; thumb extended points outward-left at 45°, folded rests across the palm.

- [ ] **Step 1: Write failing tests** in `HandFrameTests.swift`:
  - `jointOrderMatchesVision`: `JointName.allCases.count == 21`, `JointName.indexTip.rawValue == 8`, `JointName.fingers[1] == [.indexMCP, .indexPIP, .indexDIP, .indexTip]`.
  - `recordingRoundTrip`: 3 frames from `FrameScript` → `encode` → `decode` equals original; encoded data has exactly 3 newline-separated lines.
  - `syntheticOpenPalmFingertipsAboveMCPs`: for `.openPalm`, every fingertip y < its MCP y; for `.fist`, index/middle/ring/little tip y > PIP y.
  - `frameScriptTiming`: `hold(.openPalm, for: 1.0)` at 30 fps yields 30 frames with timestamps `i/30`; `gap(0.5)` advances the next timestamp by 0.5 s without frames.
- [ ] **Step 2: Run** `swift test --package-path Packages/EasyControlCore` → fails (types missing).
- [ ] **Step 3: Implement** the types above, `HandFrameRecording` with `JSONEncoder` (sorted keys) per line, TestSupport builders, and empty placeholder source files so every declared target compiles.
- [ ] **Step 4: Run** `swift test --package-path Packages/EasyControlCore` → all pass.
- [ ] **Step 5: CI** — `.github/workflows/ci.yml` on `push`/`pull_request`, `runs-on: macos-latest`, steps: checkout, `swift test --package-path Packages/EasyControlCore`. (App build job added in Task 12.)
- [ ] **Step 6: Commit** `feat(core): package scaffold, hand frame types, recording codec, CI` and push.

---

### Task 2: M0 spike — Space switching and Vision latency (throwaway, answer recorded)

**Files:**
- Create: `tools/spikes/space_switch.swift`, `tools/spikes/vision_bench.swift`, `tools/spikes/fetch_sample.py`, `tools/spikes/pyproject.toml`, `docs/spikes/m0-results.md`

**Interfaces:**
- Produces: the decisions recorded in `docs/spikes/m0-results.md` that Task 10 and Task 11 consume — (a) which Space-switch strategy fires on macOS 27 and with which `CGEventFlags`; (b) which Vision API (`VNDetectHumanHandPoseRequest` vs `DetectHumanHandPoseRequest`) and its measured per-image latency/CPU on this Mac; (c) whether Vision `chirality` matches the user's hand in the mirrored convention (left open until the live session; mark "pending user").

- [ ] **Step 1: Space switch probe.** `space_switch.swift` (compiled with `swiftc`): read active space via `dlsym` of `CGSMainConnectionID` + `CGSGetActiveSpace`, post a key event (keycode 124 → right, 123 → left, 126 → up/Mission Control) with modifier variants: (i) `.maskControl`; (ii) `.maskControl | .maskSecondaryFn | .maskNumericPad`. After each post wait 1 s, read active space, then post the opposite to return. Print a table `variant | before | after | switched`.
- [ ] **Step 2: Run** it; restore the user's original Space at the end (assert final == initial). Expected: at least one variant switches; record which.
- [ ] **Step 3: Sample images.** `fetch_sample.py` (uv project with `remotezip`): open `https://rndml-team-cv.obs.ru-moscow-1.hc.sbercloud.ru/datasets/hagrid_v2/hagridv2_512.zip` via HTTP range, list members, extract `--per-class N` images for `--classes` (default `palm,peace,fist,one` N=15) into `data/hagrid-sample/<class>/`. Run `uv run fetch_sample.py`. Expected: ~60 JPEGs.
- [ ] **Step 4: Vision bench.** `vision_bench.swift`: for each image, time 5 runs of each API (warm-up excluded), report p50/p95 ms, detection rate, and process CPU time per image. Run it.
- [ ] **Step 5: Record** results, the chosen strategy/flags/API, and the "pending live" items in `docs/spikes/m0-results.md`.
- [ ] **Step 6: Commit** `docs: M0 spike results (space switching, vision latency)` and push (spike sources included, labelled throwaway in a header comment; `data/` stays git-ignored).

---

### Task 3: Signal — One Euro filter and hand identity tracking

**Files:**
- Create: `Sources/Signal/OneEuroFilter.swift`, `Sources/Signal/HandIdentityTracker.swift`, `Tests/SignalTests/OneEuroFilterTests.swift`, `Tests/SignalTests/HandIdentityTrackerTests.swift`

**Interfaces:**
- Consumes: `Hand`, `HandFrame` (Task 1).
- Produces:
  - `public struct OneEuroFilter: Sendable { init(minCutoff: Float = 1.7, beta: Float = 0.3, dCutoff: Float = 1.0); mutating func filter(_ x: SIMD2<Float>, at t: TimeInterval) -> SIMD2<Float>; mutating func reset() }` — resets itself when `t - lastT > 0.25` or `t <= lastT`.
  - `public typealias HandID = Int`
  - `public struct TrackedHand: Sendable { var id: HandID; var hand: Hand /* filtered */; var raw: Hand; var firstSeen: TimeInterval }`
  - `public final class HandIdentityTracker { init(maxMatchDistance: Float = 0.15, filterParams: (Float, Float, Float) = (1.7, 0.3, 1.0)); func update(_ frame: HandFrame) -> [TrackedHand] }` — greedy nearest palm-centre matching (centre = mean of wrist + 4 MCPs), chirality must match unless either is `.unknown`; unmatched hands get a new increasing id; per-hand, per-joint `OneEuroFilter`; a hand missing for > 0.25 s is dropped (its id never reused).

- [ ] **Step 1: Write failing tests:**
  - `firstSamplePassesThrough`: first `filter` returns input exactly.
  - `constantInputStaysConstant`: 30 samples of `[0.3,0.7]` → last output equals input within 1e-6.
  - `stepConvergesWithinHalfSecond`: step 0→1 at 30 fps; output > 0.95 by t = 0.5 s and is monotonic.
  - `gapResetsFilter` (Review Focus 4): after converging at 0, a sample of 1 arriving 0.5 s later returns exactly 1.
  - `stableIDsAcrossFrames`: one hand moving 0.01/frame for 30 frames keeps the same id.
  - `twoHandsKeepDistinctIDs`: left at x 0.3 and right at x 0.7 for 30 frames → two stable distinct ids.
  - `reappearingHandGetsNewID`: hand, 0.5 s empty, hand again → new id.
- [ ] **Step 2: Run** `swift test --package-path Packages/EasyControlCore --filter SignalTests` → fails.
- [ ] **Step 3: Implement** both types (standard One Euro: α from cutoff and dt; cutoff = minCutoff + beta·|dx̂|).
- [ ] **Step 4: Run** the filter again → pass.
- [ ] **Step 5: Commit** `feat(signal): one euro filter and hand identity tracking` and push.

---

### Task 4: Signal — normalization and features

**Files:**
- Create: `Sources/Signal/HandNormalizer.swift`, `Sources/Signal/HandFeatures.swift`, `Tests/SignalTests/HandFeaturesTests.swift`

**Interfaces:**
- Consumes: `Hand`, `JointName`, `SyntheticHand`.
- Produces:
  - `public struct HandFeatures: Sendable { var normalized: [SIMD2<Float>] /* 21, wrist-origin, palm-size-scaled, rotated so wrist→middleMCP points −y, left hands mirrored */; var fingerExtended: [Bool] /* 5, thumb…little */; var palmCenter: SIMD2<Float> /* image coords */; var palmSize: Float /* |wrist−middleMCP| in image coords */; var isReliable: Bool; var vector: [Float] /* 42 normalized coords + 5 extension flags as 0/1 + 5 PIP angles (rad) */ }`
  - `public enum HandFeatureExtractor { static func extract(_ hand: Hand, minConfidence: Float = 0.3) -> HandFeatures }`
  - `isReliable` is false if wrist or any MCP is below `minConfidence`, or palmSize < 0.02.
  - Finger extended (non-thumb): `|tip−wrist| > 1.15·|pip−wrist|` **and** PIP angle > 2.4 rad. Thumb extended: `|thumbTip−indexMCP| > 0.55·palmSize` (normalized space).

- [ ] **Step 1: Write failing tests:**
  - `normalizationIsTranslationAndScaleInvariant`: open palm at (0.3,0.4, size 0.1) and (0.7,0.6, size 0.2) → `normalized` equal within 1e-3.
  - `normalizationIsRotationInvariant`: open palm rotated 30° (rotate all joints about wrist) → equal within 1e-3.
  - `leftHandMirrorsToRight`: `.two` with chirality `.left` (geometry mirrored) yields same `normalized` as `.right` within 1e-3.
  - `extensionFlagsPerPose`: openPalm → all true; fist → all false for index…little; two → [_, true, true, false, false]; point → [_, true, false, false, false].
  - `lowConfidenceIsUnreliable` (Review Focus 5): wrist confidence 0.1 → `isReliable == false`.
  - `vectorLengthIs52`.
- [ ] **Step 2: Run** `--filter HandFeaturesTests` → fails.
- [ ] **Step 3: Implement** `HandNormalizer` (translate, scale, rotate, mirror) and `HandFeatureExtractor`.
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `feat(signal): hand normalization and features` and push.

---

### Task 5: GestureEngine — pose classes, rule-based classifier, hysteresis

**Files:**
- Create: `Sources/GestureEngine/{GestureConfig,PoseClass,RuleBasedPoseClassifier,PoseStabilizer}.swift`, `Tests/GestureEngineTests/PoseTests.swift`

**Interfaces:**
- Consumes: `HandFeatures`.
- Produces:
  - `public enum PoseClass: String, CaseIterable, Codable, Sendable { case openPalm, fist, point, two, three, pinch, ok, thumbsUp, thumbsDown, none }`
  - `public protocol PoseClassifying { func classify(_ f: HandFeatures) -> [PoseClass: Float] }` (probabilities sum to 1)
  - `public struct RuleBasedPoseClassifier: PoseClassifying` — one-hot from extension flags: all five → openPalm; index+middle only (thumb ignored) → two; index only → point; index+middle+ring only → three; no index…little → fist; else none. Unreliable features → `[.none: 1]`.
  - `public struct GestureConfig: Sendable` with fields and defaults: `poseEnter 0.85, poseExit 0.60, poseEnterFrames 3, wakeHold 0.4, idleTimeout 3.0, handLostTimeout 1.0, inputSuppression 0.5, discreteCooldown 0.4, minPalmSize 0.06, frameGapReset 0.25, swipeMinSpeed 1.0, swipeMinDistance 0.15, swipeDominance 2.0, swipeWindow 0.25, scrollDeadZone 0.004`; `static let default`.
  - `public struct PoseStabilizer { init(config: GestureConfig); mutating func update(_ probs: [PoseClass: Float]) -> PoseClass /* stable pose, .none initially */ }` — switch to a new pose only after `poseEnterFrames` consecutive frames with p ≥ `poseEnter`; leave the current pose when its p < `poseExit` (→ `.none`, unless another pose simultaneously qualifies).

- [ ] **Step 1: Write failing tests:**
  - `rulesClassifySyntheticPoses`: each of openPalm/fist/point/two/three from `SyntheticHand` → that class with p = 1.
  - `unreliableIsNone`.
  - `stabilizerNeedsThreeFrames`: two frames of openPalm → still none; third → openPalm.
  - `stabilizerIgnoresSingleFrameFlicker`: openPalm stable, one frame of fist(1.0), then openPalm → stays openPalm throughout.
  - `stabilizerExitsBelowThreshold`: openPalm stable, then `[.openPalm: 0.5, .none: 0.5]` → none.
- [ ] **Step 2: Run** `--filter PoseTests` → fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `feat(engine): pose classes, rule-based classifier, hysteresis` and push.

---

### Task 6: GestureEngine — engagement controller

**Files:**
- Create: `Sources/GestureEngine/EngagementController.swift`, `Tests/GestureEngineTests/EngagementTests.swift`

**Interfaces:**
- Consumes: `GestureConfig`, `PoseClass`, `HandID`.
- Produces:
  - `public enum InteractionMode: String, Codable, Sendable { case command, cursor }`
  - `public enum EngagementState: Equatable, Sendable { case paused, idle, engaged(hand: HandID, mode: InteractionMode) }`
  - `public struct HandObservation: Sendable { var id: HandID; var pose: PoseClass; var palmSize: Float; var palmCenter: SIMD2<Float> }`
  - `public struct EngagementController { init(config: GestureConfig); private(set) var state: EngagementState; mutating func update(hands: [HandObservation], at t: TimeInterval) -> EngagementState?` (returns new state only on change) `; mutating func noteActivity(at t: TimeInterval)` (a recognized gesture keeps engagement alive) `; mutating func setPaused(_ p: Bool, at t: TimeInterval) -> EngagementState? }`
  - Rules: idle → engaged(command) when one hand holds `openPalm` with `palmSize ≥ minPalmSize` for `wakeHold` continuously (if several qualify, the largest palm wins). engaged → idle when engaged hand absent > `handLostTimeout`, or no activity for `idleTimeout` (activity = `noteActivity` or the engaged hand's pose changing). paused ignores all hands until unpaused (→ idle).

- [ ] **Step 1: Write failing tests:**
  - `engagesAfterWakeHold`: openPalm 0.3 s → idle; at 0.4 s → engaged(command).
  - `smallDistantHandDoesNotEngage`: palmSize 0.04 for 2 s → idle.
  - `interruptedHoldRestarts`: 0.3 s openPalm, 1 frame fist, 0.3 s openPalm → still idle.
  - `disengagesWhenHandLost`: engaged, then 1.1 s with no hands → idle.
  - `disengagesAfterIdleTimeout`: engaged, hand present with unchanged pose and no activity for 3.1 s → idle; with `noteActivity` at 2 s → still engaged at 3.1 s.
  - `largestPalmWins`: two open palms sizes 0.08 and 0.12 → engaged hand is the 0.12 one.
  - `pausedIgnoresHands`.
- [ ] **Step 2: Run** `--filter EngagementTests` → fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `feat(engine): engagement state machine` and push.

---

### Task 7: GestureEngine — scroll and swipe recognizers

**Files:**
- Create: `Sources/GestureEngine/{GestureEvent,ScrollRecognizer,SwipeRecognizer}.swift`, `Tests/GestureEngineTests/MotionTests.swift`

**Interfaces:**
- Consumes: `GestureConfig`, `PoseClass`.
- Produces:
  - `public struct GestureID: RawRepresentable, Hashable, Codable, Sendable` with statics `scroll = "scroll"`, `swipeLeft = "swipe.left"`, `swipeRight = "swipe.right"`, `swipeUp = "swipe.up"`, `swipeDown = "swipe.down"`.
  - `public enum Phase: String, Codable, Sendable { case began, changed, ended }`
  - `public enum GestureEvent: Equatable, Sendable { case discrete(GestureID); case continuous(GestureID, phase: Phase, delta: SIMD2<Float>); case cursor(position: SIMD2<Float>); case engagement(EngagementState) }`
  - `public struct ScrollRecognizer { init(config: GestureConfig); mutating func update(pose: PoseClass, palmCenter: SIMD2<Float>?, at t: TimeInterval) -> GestureEvent?; mutating func cancel() -> GestureEvent? }` — `began` (delta 0) when pose becomes `two`; `changed` with per-frame palm displacement (components below `scrollDeadZone` zeroed; frames with zero delta emit nothing); `ended` when pose leaves `two` or `palmCenter` is nil; `cancel()` emits `ended` if active.
  - `public struct SwipeRecognizer { init(config: GestureConfig); mutating func update(pose: PoseClass, palmCenter: SIMD2<Float>?, at t: TimeInterval) -> GestureEvent?; mutating func reset() }` — only while pose is `openPalm`; keeps samples within `swipeWindow`; fires when displacement over window ≥ `swipeMinDistance`, mean speed ≥ `swipeMinSpeed`, and dominant-axis/other-axis ≥ `swipeDominance`; direction from the dominant axis in the mirrored convention (−x = left, −y = up); after firing, clears samples and is silent for `discreteCooldown`; a gap > `frameGapReset` clears samples.

- [ ] **Step 1: Write failing tests:**
  - `scrollLifecycle`: `two` held while moving down 0.2 over 0.5 s → events `began`, then `changed` deltas summing to (0, 0.2) ±0.01, then switch to openPalm → `ended`.
  - `scrollDeadZoneSuppressesJitter`: `two` with ±0.001 jitter → only `began`.
  - `scrollEndsWhenHandLost` (Review Focus 1): active scroll, `palmCenter: nil` → `ended`.
  - `fastLeftSwipeFires`: openPalm moving x 0.7→0.45 over 0.2 s → exactly one `.discrete(.swipeLeft)`.
  - `slowDriftDoesNotSwipe`: x 0.7→0.45 over 2 s → none.
  - `diagonalDoesNotSwipe`: (0.7,0.3)→(0.5,0.5) over 0.2 s → none.
  - `upSwipeIsMissionControlDirection`: y 0.7→0.45 → `.swipeUp`.
  - `cooldownPreventsDoubleFire`: two fast left swipes 0.2 s apart → one event.
  - `gapDoesNotCreatePhantomSwipe` (Review Focus 4): openPalm at x 0.7, 0.5 s gap, next frame at x 0.3 → none.
- [ ] **Step 2: Run** `--filter MotionTests` → fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `feat(engine): scroll and swipe recognizers` and push.

---

### Task 8: GestureEngine — engine facade, arbiter, end-to-end replay tests

**Files:**
- Create: `Sources/GestureEngine/GestureEngine.swift`, `Tests/GestureEngineTests/GestureEngineTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 3–7.
- Produces:
  - `public struct HandDebugInfo: Sendable { var id: HandID; var pose: PoseClass; var probabilities: [PoseClass: Float]; var features: HandFeatures; var hand: Hand }`
  - `public struct EngineSnapshot: Sendable { var state: EngagementState; var hands: [HandDebugInfo]; var lastEvent: GestureEvent?; var suppressed: Bool }`
  - `public final class GestureEngine { init(config: GestureConfig = .default, classifier: any PoseClassifying = RuleBasedPoseClassifier()); func process(_ frame: HandFrame, lastUserInput: TimeInterval?) -> [GestureEvent]; func setPaused(_ paused: Bool, at t: TimeInterval) -> [GestureEvent]; private(set) var snapshot: EngineSnapshot }`
  - Per frame: tracker → features → classifier → per-hand `PoseStabilizer` → `EngagementController`. Recognizers run only for the engaged hand in `.command` mode. Arbiter: while a scroll is active, swipe recognizer is not fed; a swipe fires only when no scroll is active. Suppression: if `frame.timestamp - lastUserInput < inputSuppression`, cancel active scroll (emit `ended`), reset swipe, emit nothing else. Any engagement change emits `.engagement(state)`; leaving engaged cancels an active scroll first. Every recognized gesture calls `noteActivity`.

- [ ] **Step 1: Write failing tests** (all built with `FrameScript`):
  - `palmSwipeAfterEngageSwitches`: openPalm hold 0.5 s at centre → `.engagement(.engaged…)`; then fast move left → `.discrete(.swipeLeft)`.
  - `noGesturesWhenIdle`: fast left swipe without the 0.4 s hold first → no `.discrete`.
  - `scrollAfterEngage`: engage, switch to `.two`, move down → `began`, `changed`…, back to openPalm → `ended`.
  - `handLostMidScrollEndsScroll` (Review Focus 1): engage, scroll, then 1.1 s empty → output contains `.continuous(.scroll, .ended, _)` before `.engagement(.idle)`.
  - `secondHandIsIgnored` (Review Focus 2): engage with right hand; a second hand (`.two`, moving) appears at x 0.2 → no `.scroll` events; the engaged hand's swipe still works.
  - `typingSuppressesMidScroll` (Review Focus 3): engage, scroll active, then `lastUserInput` = current t → `ended` emitted, then no events for 0.5 s.
  - `lowConfidenceFramesProduceNothing` (Review Focus 5): engage then frames with wrist confidence 0.1 while moving fast → no `.discrete`, no `.scroll`.
  - `recordingReplayMatchesGolden`: encode a scripted session to JSONL, decode, replay → identical event list to the direct run.
- [ ] **Step 2: Run** `--filter GestureEngineTests` → fails.
- [ ] **Step 3: Implement** `GestureEngine`.
- [ ] **Step 4: Run** full `swift test --package-path Packages/EasyControlCore` → all pass.
- [ ] **Step 5: Commit** `feat(engine): gesture engine facade with arbitration and suppression` and push.

---

### Task 9: Actions — synthetic events, sinks, scroll injector with momentum

**Files:**
- Create: `Sources/Actions/{SyntheticEvent,EventSink,CGEventSink,ScrollInjector}.swift`, `Tests/ActionsTests/ScrollInjectorTests.swift`

**Interfaces:**
- Consumes: `GestureEvent`, `Phase`.
- Produces:
  - `public enum ScrollPhase: Sendable { case began, changed, ended, none }`; `public enum MomentumPhase: Sendable { case none, began, `continue`, ended }`
  - `public enum SyntheticEvent: Equatable, Sendable { case scroll(dx: Int32, dy: Int32, phase: ScrollPhase, momentum: MomentumPhase); case key(code: UInt16, flags: UInt64, down: Bool) }`
  - `public protocol EventSink: Sendable { func post(_ e: SyntheticEvent) }`; `public final class RecordingEventSink: EventSink` (thread-safe `events: [SyntheticEvent]` via `Mutex`); `public struct CGEventSink: EventSink` — scroll via `CGEvent(scrollWheelEvent2Source:units: .pixel, wheelCount: 2, …)` setting `.scrollWheelEventIsContinuous = 1`, `.scrollWheelEventScrollPhase` (began 1, changed 2, ended 4), `.scrollWheelEventMomentumPhase` (begin 1, continue 2, end 3); keys via `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with `flags`; every event sets `.eventSourceUserData = 0x45430001`; posted to `.cghidEventTap`.
  - `public static let syntheticMarker: Int64 = 0x45430001` (on `CGEventSink`).
  - `public final class ScrollInjector { init(sink: any EventSink, pixelsPerUnit: Float = 1800, natural: Bool = true, friction: Float = 0.92, minMomentumSpeed: Float = 20); func handle(phase: Phase, delta: SIMD2<Float>, at t: TimeInterval); func tick(at t: TimeInterval) /* 60 Hz momentum step */; var isMomentumActive: Bool }` — `natural == true`: `dy = Int32(delta.y · pixelsPerUnit)`, `dx = Int32(delta.x · pixelsPerUnit)` (hand moving up, delta.y < 0, gives negative wheel delta = view scrolls down = content moves up, like pushing a page on a trackpad); `natural == false` negates both; verified live in Task 10 Step 5; tracks release velocity as an EMA over the last 100 ms; on `ended`, if speed ≥ `minMomentumSpeed` px/s emits momentum `began` then `continue` each tick with velocity·=friction until below threshold, then momentum `ended`; a new `began` cancels momentum (emits momentum `ended`).

- [ ] **Step 1: Write failing tests:**
  - `phasesMapToScrollEvents`: began → `.scroll(0,0,.began,.none)`; changed (0, 0.01) → `.scroll(0, 18, .changed, .none)` with `natural: true` and `.scroll(0, -18, …)` with `natural: false`; ended → `.scroll(0,0,.ended,.none)`.
  - `fastReleaseStartsMomentumThatDecays`: changes of 0.02/frame at 60 fps then ended; ticks → first momentum event is `.began`, magnitudes strictly decrease, final event `.ended`, total ≤ 120 ticks.
  - `slowReleaseHasNoMomentum`.
  - `newScrollCancelsMomentum`: during momentum, `began` → momentum `.ended` precedes new `.began`.
- [ ] **Step 2: Run** `--filter ScrollInjectorTests` → fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `feat(actions): synthetic events, CGEvent sink, scroll momentum` and push.

---

### Task 10: Actions — Space switcher, bindings, dispatcher, input-activity monitor, ec-probe

**Files:**
- Create: `Sources/Actions/{SpaceSwitcher,Bindings,ActionDispatcher,InputActivityMonitor}.swift`, `Sources/ec-probe/main.swift`, `Tests/ActionsTests/DispatcherTests.swift`

**Interfaces:**
- Consumes: Task 2 results (flags that work), `EventSink`, `ScrollInjector`, `GestureEvent`, `GestureID`.
- Produces:
  - `public enum Direction: String, Codable, Sendable { case left, right, up, down }`
  - `public protocol SpaceSwitchStrategy: Sendable { func switchSpace(_ d: Direction) }`; `public struct ControlArrowStrategy: SpaceSwitchStrategy { init(sink: any EventSink, flags: UInt64) }` — posts keydown+keyup of 123/124 with `flags` (default from Task 2: `maskControl | maskSecondaryFn | maskNumericPad` unless the spike says otherwise). If the spike found Ctrl+arrow unusable, also add `ControlDigitStrategy` per spec §4.1 strategy 2.
  - `public enum Action: Codable, Hashable, Sendable { case scroll, switchSpace(Direction), missionControl, appExpose, none }` — Mission Control = Ctrl+↑ (126), App Exposé = Ctrl+↓ (125), same flags as Space switching (symbolic hotkeys 32/33 are enabled on this Mac).
  - `public struct Bindings: Codable, Sendable { static let defaults /* scroll→.scroll, swipeLeft→switchSpace(.left), swipeRight→switchSpace(.right), swipeUp→missionControl, swipeDown→appExpose */; subscript(_ id: GestureID) -> Action }`
  - `public final class ActionDispatcher { init(sink: any EventSink, bindings: Bindings = .defaults, spaces: any SpaceSwitchStrategy, scroll: ScrollInjector); func handle(_ events: [GestureEvent], at t: TimeInterval); func tick(at t: TimeInterval) }`
  - `public final class InputActivityMonitor: @unchecked Sendable { init(); func start() -> Bool /* false if tap can't be created (no Accessibility) */; func stop(); var lastUserInput: TimeInterval? /* CACurrentMediaTime-based, Mutex-protected */ }` — listen-only `.cgSessionEventTap` for keyDown, flagsChanged, mouse moved/dragged, mouse down, scrollWheel; ignores events whose `eventSourceUserData == CGEventSink.syntheticMarker`; re-enables itself on `tapDisabledByTimeout`.
  - `ec-probe` CLI: `ec-probe space left|right`, `ec-probe mission-control`, `ec-probe scroll-demo` (scroll down 400 px over 0.5 s with momentum), `ec-probe monitor 5` (prints lastUserInput for 5 s) — all using the real `CGEventSink`.

- [ ] **Step 1: Write failing tests** (RecordingEventSink):
  - `swipeRightPostsCtrlRightWithConfiguredFlags`: `.discrete(.swipeRight)` → keydown 124 + keyup 124 with expected flags.
  - `swipeUpPostsMissionControl`: → 126 down/up.
  - `scrollEventsRouteToInjector`: began/changed/ended → three `.scroll` events.
  - `unboundGestureDoesNothing`: bindings with swipeLeft → `.none` → no events.
  - `bindingsRoundTripCodable`.
- [ ] **Step 2: Run** `--filter DispatcherTests` → fails.
- [ ] **Step 3: Implement** the types and `ec-probe`.
- [ ] **Step 4: Run** full test suite → pass.
- [ ] **Step 5: Live check** (user pre-approved live input): `swift run --package-path Packages/EasyControlCore ec-probe space right` then `space left` → the desktop moves right and back (confirm with spike's active-space reader); `ec-probe scroll-demo` with TextEdit frontmost scrolls; `ec-probe mission-control` opens then a second call closes it. Record outcome in `docs/spikes/m0-results.md`.
- [ ] **Step 6: Commit** `feat(actions): space switching, bindings, dispatcher, input monitor, ec-probe` and push.

---

### Task 11: Capture — camera, Vision detector, latency stats

**Files:**
- Create: `Sources/Capture/{CameraCapture,VisionHandDetector,RollingPercentiles}.swift`, `Tests/CaptureTests/CaptureTests.swift`

**Interfaces:**
- Consumes: Task 2 choice of Vision API; `HandFrame`, `Hand`, `Joint`, `JointName`.
- Produces:
  - `public final class CameraCapture: NSObject, @unchecked Sendable { init(); let session: AVCaptureSession; let queue: DispatchQueue /* serial, .userInteractive */; var onFrame: (@Sendable (CVPixelBuffer, TimeInterval) -> Void)?; func start() throws; func stop(); func setFrameRate(_ fps: Double); var onStateChange: (@Sendable (CaptureState) -> Void)? }` — front built-in camera, 640×480, `alwaysDiscardsLateVideoFrames = true`, timestamps = presentation time in seconds (host clock); observes `AVCaptureSession.wasInterrupted`/`runtimeError`.
  - `public enum CaptureState: Sendable, Equatable { case stopped, running, interrupted, noCamera, failed(String) }`
  - `public final class VisionHandDetector: @unchecked Sendable { init(maxHands: Int = 2); func detect(_ buffer: CVPixelBuffer, timestamp: TimeInterval) throws -> HandFrame; static func convert(_ p: CGPoint) -> SIMD2<Float> /* Vision (bottom-left, unmirrored) → ours: (1−x, 1−y) */; static func jointName(for: VNHumanHandPoseObservation.JointName) -> JointName }` — joints Vision doesn't return get confidence 0.
  - `public struct RollingPercentiles { init(capacity: Int = 300); mutating func add(_ v: Double); func percentile(_ p: Double) -> Double? }`
- [ ] **Step 1: Write failing tests:**
  - `convertFlipsBothAxes`: (0.2, 0.9) → (0.8, 0.1).
  - `allVisionJointsMapped`: the 21 Vision joint names map to 21 distinct `JointName`s.
  - `percentiles`: 1…100 → p50 = 50 ±1, p95 = 95 ±1; empty → nil; capacity drops oldest.
  - `detectsHandInSampleImage` (skipped when `data/hagrid-sample` is absent so CI stays green): first `palm` image → ≥ 1 hand with ≥ 15 joints at confidence > 0.3.
- [ ] **Step 2: Run** `--filter CaptureTests` → fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `feat(capture): camera capture, vision hand detector, latency stats` and push.

---

### Task 12: App — XcodeGen project, menu bar, permissions, pipeline, auto-pause

**Files:**
- Create: `project.yml`, `scripts/build-app.sh`, `App/{EasyControlApp,AppModel,Pipeline,Permissions,AutoPause}.swift`, `App/Views/{MenuContent,PermissionsView}.swift`, `App/Resources/{Info.plist,EasyControl.entitlements,Assets.xcassets}`
- Modify: `.github/workflows/ci.yml` (add app build job)

**Interfaces:**
- Consumes: `CameraCapture`, `VisionHandDetector`, `GestureEngine`, `ActionDispatcher`, `InputActivityMonitor`, `RollingPercentiles`, `EngineSnapshot`.
- Produces:
  - `final class Pipeline: @unchecked Sendable { init(); func start(); func stop(); var onSnapshot: (@Sendable (PipelineSnapshot) -> Void)? /* ≤10 Hz */; func setPaused(_: Bool) }` — all work on `CameraCapture.queue`: detect → `engine.process(frame, lastUserInput:)` → `dispatcher.handle` → latency sample `CACurrentMediaTime() − frame.timestamp`; a 60 Hz `DispatchSourceTimer` on the same queue calls `dispatcher.tick` only while momentum is active; frame rate drops to 10 fps after 5 s without hands and returns to 30 fps on the first hand.
  - `struct PipelineSnapshot: Sendable { var engine: EngineSnapshot; var fps: Double; var latencyP50: Double?; var latencyP95: Double?; var captureState: CaptureState; var latestFrame: HandFrame? }`
  - `@MainActor @Observable final class AppModel { var snapshot: PipelineSnapshot?; var isPaused: Bool; var permissions: PermissionStatus; func togglePause(); func start() }`
  - `struct PermissionStatus { var camera: AVAuthorizationStatus; var accessibility: Bool }` with `Permissions.requestCamera() async -> Bool`, `Permissions.openAccessibilitySettings()` (URL `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`), polled every 1 s while the permissions window is open.
  - `AutoPause` — pauses on `com.apple.screenIsLocked` / `NSWorkspace.willSleepNotification` / `screensDidSleepNotification`, resumes on unlock/wake unless the user paused manually.
  - Menu bar icon (SF Symbols): paused `hand.raised.slash`, idle `hand.raised`, engaged `hand.raised.fill`, warning `exclamationmark.triangle`. Menu: state line, Pause/Resume, Debug Window…, Permissions…, Quit.
  - `scripts/build-app.sh`: `xcodegen generate`; if `security find-identity -v -p codesigning` lists "Apple Development", build with it (stable TCC grants), else ad-hoc `CODE_SIGN_IDENTITY=-`; output to `build/EasyControl.app`.
- [ ] **Step 1:** `brew install xcodegen`; write `project.yml` (app target `EasyControl`, bundle id `dev.hamroz.easycontrol`, macOS 15.0, local package dependency `Packages/EasyControlCore`, hardened runtime, Info.plist keys per Global Constraints).
- [ ] **Step 2: Implement** the App files above. Startup: if either permission is missing, open the Permissions window; start the pipeline once the camera is authorized (Accessibility missing → run but show warning icon and skip dispatch).
- [ ] **Step 3: Build** `scripts/build-app.sh` → `BUILD SUCCEEDED`, zero Swift 6 concurrency errors.
- [ ] **Step 4: Smoke run** `open build/EasyControl.app`; confirm via `pgrep EasyControl` it stays alive 10 s and the menu bar extra exists (`osascript` System Events query of menu bar items); then quit it. (Camera grant needs the user; note in QA doc.)
- [ ] **Step 5: CI** — add job `app`: `brew install xcodegen && xcodegen generate && xcodebuild -scheme EasyControl -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
- [ ] **Step 6: Commit** `feat(app): menu bar app, permissions, pipeline, auto-pause` and push.

---

### Task 13: App — debug window with skeleton overlay, stats, landmark recorder

**Files:**
- Create: `App/Views/DebugView.swift`, `App/LandmarkRecorder.swift`
- Modify: `App/EasyControlApp.swift` (Window scene), `App/Pipeline.swift` (recorder tap)

**Interfaces:**
- Consumes: `PipelineSnapshot`, `CameraCapture.session`, `HandFrameRecording`.
- Produces:
  - `DebugView`: `AVCaptureVideoPreviewLayer` (mirrored) via `NSViewRepresentable`, a SwiftUI `Canvas` overlay drawing joints/bones from `latestFrame` (engaged hand highlighted), and a side panel: engagement state, per-hand stable pose + top-3 probabilities, isReliable, palmSize, fps, latency p50/p95, last event.
  - `final class LandmarkRecorder: @unchecked Sendable { func start(label: String); func stop() throws -> URL; func append(_ f: HandFrame) }` — writes JSONL via `HandFrameRecording` to `~/Library/Application Support/EasyControl/recordings/<label>-<ISO8601>.jsonl`; label picker uses `PoseClass.allCases`. Only landmarks are written.
- [ ] **Step 1: Implement** both; recorder called from `Pipeline` when active.
- [ ] **Step 2: Build** `scripts/build-app.sh` → succeeds.
- [ ] **Step 3: Unit check** recorder output path/format with a test in `HandTrackingTests` (`recorderFileDecodes`: write 10 frames via `HandFrameRecording`, decode → 10 frames) — lives in Core since the recorder itself is a thin file wrapper.
- [ ] **Step 4: Commit** `feat(app): debug window with skeleton overlay and landmark recorder` and push.

---

### Task 14: M2 verification pass and QA handoff

**Files:**
- Create: `docs/qa/m2-checklist.md`
- Modify: `docs/spikes/m0-results.md`, `README.md` (create: what it is, build steps, status)

- [ ] **Step 1:** Full `swift test --package-path Packages/EasyControlCore` → all pass; `scripts/build-app.sh` → succeeds; CI green on GitHub (`gh run list --limit 1`).
- [ ] **Step 2:** Re-run `ec-probe` live checks from Task 10 against the final build.
- [ ] **Step 3:** Write `docs/qa/m2-checklist.md` for the live session with the user: grant Camera + Accessibility; verify chirality/mirroring (raise right hand → overlay shows it on the right, labelled right); engage with open palm at typical distance and tune `minPalmSize` from the debug panel; scroll in Safari/Finder/Xcode; swipe left/right/up/down; type while a hand is visible (no triggers); second person/hand in frame; low light; lock screen → camera light off; measure latency p95 in the debug panel against < 70 ms; record a 5-minute "normal use" session with the recorder for the M3 false-trigger benchmark.
- [ ] **Step 4:** README with build instructions and current status.
- [ ] **Step 5: Commit** `docs: M2 QA checklist and README` and push.

---

## Deferred to later plans

- Global hotkey override (spec §3.1) and HUD toasts → M5/M6 plan.
- Core ML pose classifier, full pose set, HaGRID extraction at scale, evaluation report → M3 plan.
- Cursor mode → M4 plan. Bindings editor, custom poses, two-hand zoom, media/volume gestures → M5 plan.
