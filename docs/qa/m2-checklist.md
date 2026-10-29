# M2 Live QA Checklist

Run with the user at the Mac. Build first: `scripts/build-app.sh`, then `open build/EasyControl.app`.
Open **Debug Window…** from the menu-bar hand icon for every step below.

> Until an *Apple Development* signing identity exists (Xcode → Settings → Accounts), builds are ad-hoc
> signed and macOS forgets the Camera/Accessibility grants after every rebuild.

## 1. Permissions
- [ ] Permissions window appears on first launch.
- [ ] **Allow Camera** → system prompt → granted; window shows a green check; camera light turns on.
- [ ] **Open Accessibility Settings** → enable EasyControl → window turns green within ~1 s, no relaunch.
- [ ] Menu-bar icon: `hand.raised` when idle (not the warning triangle).

## 2. Tracking and coordinates (records open items from `docs/spikes/m0-results.md`)
- [ ] Skeleton overlay sits on the hand in the mirrored preview.
- [ ] Raise **right** hand: it appears on the right of the preview and the panel says `right`. If it says `left`, flip chirality in `VisionHandDetector.hand(from:)`.
- [ ] Move hand left: overlay moves left (mirror convention).
- [ ] FPS ≈ 30 with a hand visible; drops to ≈ 10 after 5 s without hands; returns to 30 when a hand reappears.
- [ ] Latency p95 in the panel: target < 70 ms. Record the value: ____
- [ ] Activity Monitor CPU for EasyControl: idle ____ %, hand visible ____ %.

## 3. Engagement
- [ ] Open palm toward camera at normal sitting distance for ~0.5 s → state `engaged`, icon `hand.raised.fill`.
- [ ] Note `palm` size shown at that distance: ____ (default threshold `minPalmSize = 0.06`; tune if engagement fails or triggers from too far).
- [ ] Hand down for > 1 s → `idle`. Palm held still for 3 s → `idle`, and it does not re-engage until the palm is lowered and raised again.

## 4. Gestures (engaged)
- [ ] Two fingers (V) up, move hand up/down in Safari → page scrolls; direction feels natural; flick → momentum.
- [ ] Same in Finder and Xcode.
- [ ] Quick open-palm swipe left/right → Space switches left/right.
- [ ] Swipe up → Mission Control opens; swipe down → App Exposé. (Not verifiable headlessly.)
- [ ] Slow hand drift does not swipe. Talking with hands while engaged produces no swipes.
- [ ] `ec-probe scroll-demo down` scrolls the front window down (`swift run --package-path Packages/EasyControlCore ec-probe scroll-demo down`).

## 5. Safety guards
- [ ] Type on the keyboard with a hand visible → panel shows "Suppressed"; no gestures fire.
- [ ] Mid-scroll, touch the trackpad → scroll stops immediately.
- [ ] Second person's hand in frame while engaged → only the engaged (green) hand drives gestures.
- [ ] Dim the lights / bright window behind you → hands turn red (unreliable) instead of firing gestures.

## 6. Privacy and pause
- [ ] Menu → Pause → camera light off; Resume → on.
- [ ] Lock screen (⌃⌘Q) → camera light off; unlock → tracking resumes.
- [ ] Close the lid / sleep → resumes after wake.

## 7. Data for M3
- [ ] Debug window → recorder label `normal-use` → record 5 minutes of ordinary work (typing, talking, coffee).
- [ ] Record ~30 s for each pose label (open palm, fist, point, two, three, pinch, ok, thumbs up/down) with both hands, varied distance and angle.
- [ ] Files land in `~/Library/Application Support/EasyControl/recordings/`.
