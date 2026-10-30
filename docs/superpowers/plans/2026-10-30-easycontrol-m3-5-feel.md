# EasyControl M3.5 — Trackpad Feel

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make EasyControl feel like the trackpad: three-finger swipes that move Spaces / Mission Control with the hand, instant re-engagement, left/right swipes that work in 16:9, and a pose model that recognizes the user's hand.

**Architecture:** Recognizers measure motion in isotropic units (x × aspect). `EngagementController` gains a `standby` state and direct pose engagement. A new `DockSwipeRecognizer` (pose `three`) emits continuous `dockSwipeHorizontal` / `dockSwipeVertical` events; `DockSwipeInjector` turns them into Dock Swipe events through a new `SyntheticEvent.dockSwipe`, posted by `CGEventSink` via a `dlsym`-resolved private bridge, with a discrete-key fallback. The training pipeline ingests the user's landmark recordings.

**Tech Stack:** as before (Swift 6, Vision, Core ML, CoreGraphics + SkyLight/IOKit via dlsym; Python/uv).

**Spec:** `docs/superpowers/specs/2026-10-29-easycontrol-design.md` §12 (addendum).

## Global Constraints

- Private API only in `Sources/Actions/DockSwipeBridge.swift`, resolved with `dlsym`; missing symbols → `supportsDockSwipe == false` → discrete fallback. Never crash.
- Dock Swipe event: IOHIDEvent type 23, fields motion `(23<<16)|1` (1 horizontal, 2 vertical), progress `(23<<16)|2`, flavor `(23<<16)|5` = **3**; phase in options `phase << 24` (began 1, changed 2, ended 4, cancelled 8); on ended/cancelled append Velocity event (type 9) with X = Y = lastDelta × 100; type-30 CGEvent; `SLEventSetIOHIDEvent`; post to session tap; `eventSourceUserData = 0x45430001`.
- Horizontal progress = hand's horizontal travel / `handTravelPerSpace` (positive = hand moved right, verified natural direction). Vertical progress sign is a constant to verify live.
- Timings: standby 15 s; direct engage hold 0.3 s; Dock swipe axis lock after 0.03 isotropic units; end event re-sent after 0.2 s and 0.5 s.

## Review Focus

1. **Stuck Dock transition** — a began without ended leaves Spaces mid-slide. Every exit path (pose change, hand lost, typing, pause, disengage) must end or cancel. Tests in Task 3/4.
2. **Standby flapping / stranger hands** — a still palm must not toggle engaged↔standby; a relaxed hand in view must not resume. Tests in Task 2.
3. **Isotropic edges** — edge rejection must stay in normalized frame coordinates while distances use isotropic ones. Test in Task 1.
4. **Fallback when private API is missing** — release still switches Space / opens Mission Control. Test in Task 4.
5. **Personal-data leakage into reported HaGRID numbers** — user rows never enter the HaGRID test metrics; personal metrics reported separately on held-out time segments. Test in Task 6.

---

### Task 1: Isotropic motion
- Recognizers take `aspect: Float`; `ScrollRecognizer` scales delta.x by aspect; `SwipeRecognizer` measures displacement/speed/dominance with x × aspect, edge check in normalized coords. Engine passes the engaged hand's `aspectRatio`.
- Tests: `wideFrameHorizontalSwipeFires` (aspect 16/9, normalized x travel 0.14 in 0.2 s → swipeLeft), `wideFrameEdgeStillNormalized` (stroke ending at normalized x 0.95 in 16:9 → none), `scrollDeltaIsIsotropic`.

### Task 2: Standby and direct engagement
- `EngagementState` gains `.standby`. Engaged → standby on hand lost (> 1 s) or idle (3 s). Standby → engaged when a hand (palm ≥ minPalmSize) *transitions into* `openPalm`/`two`/`three` (a newly seen hand's first stable gesture pose counts); standby → idle after 15 s (hands present then are "spent" as before). Idle → engaged by `openPalm` held 0.4 s or `two`/`three` held 0.3 s.
- Tests: `handLostEntersStandbyAndReturnResumes`, `standbyExpiresToIdle`, `stillPalmDoesNotFlap`, `relaxedHandDoesNotResume`, `twoFingersEngageDirectly`, updated `disengages…` tests; engine `handLostMidScrollEndsScroll` expects `.standby`.

### Task 3: Dock swipe recognizer
- `GestureID.dockSwipeHorizontal`, `.dockSwipeVertical`. `DockSwipeRecognizer.update(pose:palmCenter:aspect:at:)`: while `three`, after isotropic travel ≥ 0.03 lock the dominant axis and emit `began` then `changed` deltas along that axis (other component 0); `ended` when pose leaves `three`; `cancelled` when hand lost/`cancel()`.
- Engine: `three` drives this recognizer (scroll stays `two`, swipes stay `openPalm`); suppression/disengage/pause cancel it.
- Tests: `horizontalDragEmitsAxisLockedDeltas`, `verticalDrag`, `jitterBelowLockEmitsNothing`, `handLostCancels`, engine `threeFingerDragAfterEngage`, `typingCancelsDockSwipe`.

### Task 4: Dock swipe injection
- `SyntheticEvent.dockSwipe(motion: DockMotion, phase: DockPhase, progress: Double, velocity: Double)`; `EventSink.supportsDockSwipe` (default false); `CGEventSink` posts via `DockSwipeBridge`.
- `DockSwipeInjector(sink:, fallback:, handTravelPerSpace: 0.25)`: accumulates progress; ended → cancelled when last delta sign ≠ progress sign; schedules end re-sends (+0.2 s, +0.5 s) delivered by `tick(at:)`; if `!supportsDockSwipe`, on ended with |progress| ≥ 0.5 calls the fallback (Space left/right, Mission Control, App Exposé).
- Bindings: `dockSwipeHorizontal/Vertical → .dockSwipe`; dispatcher routes, ticks, and `cancelMomentum()` also cancels an open Dock swipe.
- Tests: `progressAccumulatesWithNaturalSign`, `endCarriesVelocity`, `reversalBecomesCancelled`, `endIsResent`, `fallbackSwitchesSpaceWhenUnsupported`, `pauseCancelsOpenDockSwipe`.
- Live: `ec-probe dock-swipe left|right` changes the active Space and returns.

### Task 5: App
- Pipeline ticks while the dispatcher needs ticks (momentum or Dock re-sends); status text / icon / debug labels for `.standby`.

### Task 6: Personalized model with pinch
- `ec-extract --recordings <dir> --out <jsonl>`: label from file name prefix; drop first/last 1 s; time split per file: first 70 % `train`, last 30 % `test`; `user_id = "local-user"`, `source = "recording"`; `normal-use` frames with a hand → `none`, every 3rd frame; flipped copies for train.
- Training: `CLASSES` gains `pinch` (10); HaGRID metrics computed on HaGRID test rows only; new "Your hand" section from local-user test rows; selection unchanged otherwise.
- Tests: Swift `recordingSplitIsTemporal` (pure function), Python `test_hagrid_metrics_exclude_local_rows`.

### Task 7: Docs and verification
- README gesture table, QA items (three-finger drags, standby), full suites, app build, CI.
