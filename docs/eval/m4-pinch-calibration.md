# M4 Pinch Calibration

Measured 2026-11-02 with `ec-replay --pinch-stats` on the author's landmark recordings (first and last second of
each trimmed). Only these aggregates are committed; the recordings stay on the author's Mac.

Pinch ratio = |thumb tip − index tip| / palm size (isotropic). Close < 0.22, open > 0.35.

| Recording | Frames | Ratio p5 / p50 / p95 | Below close (0.22) | Index reach of those frames p5 / p50 / p95 |
|---|---|---|---|---|
| pinch | 947 | 0.040 / 0.078 / 0.722 | 79.8 % | 0.93 / 1.29 / 1.54 |
| ok | 941 | 0.098 / 0.207 / 0.262 | 65.9 % | 0.97 / 1.05 / 1.27 |
| normal use | 3764 | 0.048 / 0.483 / 1.668 | 38.6 % | 0.83 / 1.29 / 1.44 |
| none | 932 | 0.090 / 0.512 / 1.518 | 22.4 % | 0.95 / 1.33 / 1.54 |
| fist | 867 | 0.130 / 0.465 / 1.063 | 13.3 % | 0.57 / 0.70 / 1.09 |
| three | 970 | 0.505 / 0.972 / 1.508 | 2.8 % | — |
| open palm, point, two, thumbs | ≥ 788 each | p5 ≥ 0.56 | ≤ 0.2 % | — |

Findings:
- A deliberate pinch is unambiguous (median 0.078); the 20 % of `pinch` frames above the threshold are the moments
  the author rotated the hand or opened it while recording. Thresholds 0.22 / 0.35 kept.
- Geometry alone also "touches" in a fist (thumb on a curled index). **Minimum index reach 0.85** rejects most
  fist frames (p50 0.70) while keeping ≥ 95 % of pinch frames (p5 0.93).
- In normal use the thumb often meets the index tip with the same geometry as a pinch (38.6 % of frames), so
  intent has to come from engagement: clicks only while engaged, a pinch must be seen open before it can press,
  and typing suppresses everything. The OK sign reads as a pinch, which is acceptable (it is one).

## Replay gate (held-out last 25 % of the normal-use recording, 2.5 min, no typing suppression applied)

| Classifier | Engagements | Clicks | Drags | Scrolls / Dock | Actions per hour |
|---|---|---|---|---|---|
| Core ML (shipped, HaGRID-only) | 0 | 0 | 0 | 0 | 0 |
| Rule-based fallback | 1 | 0 | 0 | 1 (cancelled after 4 frames) | 23.5 |

The fallback (used only if the model fails to load) engaged on a relaxed open hand and then started a scroll on a
pinch-like touch during a one-frame 0.14 frame-height tracking jump. 2.5 minutes is far too short to establish
the < 1 action/hour target; that needs about an hour of normal-use recording.
