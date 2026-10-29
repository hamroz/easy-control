# EasyControl M3 Implementation Plan — Learned Pose Classifier

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the rule-based pose classifier with a small neural network trained on Apple-Vision landmarks extracted from HaGRID, shipped as Core ML, with a held-out-subject evaluation report and a false-trigger replay benchmark.

**Architecture:** Python (`tools/dataset`) selects and downloads a HaGRID subset by subject split and writes a manifest. A Swift CLI (`ec-extract`) runs the *same* `VisionHandDetector` + `HandFeatureExtractor` used at runtime on each image, so training features and runtime features come from one code path. Python (`tools/training`) trains an MLP with standardization folded in, exports `PoseClassifier.mlpackage`, and writes the report. `CoreMLPoseClassifier` implements `PoseClassifying`; the app uses it and falls back to the rules if the model can't load. `ec-replay` replays landmark recordings through the engine to count false actions per hour.

**Tech Stack:** Swift 6, Vision, Core ML; Python 3.12 via uv, PyTorch, coremltools, scikit-learn, remotezip, pytest.

**Spec:** `docs/superpowers/specs/2026-10-29-easycontrol-design.md` (§6 ML pipeline, §9 M3).

## Global Constraints

- Images live only under git-ignored `data/`; never committed. Only landmarks/feature vectors and the model are committed.
- HaGRID subset ≤ ~3 GB total (user-approved "selective ~3–5 GB"), fetched from the official host via HTTP range requests.
- HaGRID licence (reworked CC BY-SA 4.0, attribution + share-alike, no non-commercial clause): the model ships with `App/Resources/MODEL_LICENSE.md` crediting HaGRID (https://github.com/hukenovs/hagrid) under CC BY-SA 4.0.
- Splits are HaGRID's own subject-disjoint `train` / `val` / `test` annotation splits; test = held-out subjects.
- Model input: the 52-float `HandFeatures.vector`; model classes (9): `openPalm, fist, point, two, three, ok, thumbsUp, thumbsDown, none`. `pinch` has no HaGRID source; it stays at probability 0 until user recordings exist.
- Runtime gate unchanged: unreliable hands or any unknown finger → `.none` before the model runs; training uses only samples that pass the same gate.
- Targets (spec §1): ≥ 97 % accuracy on the test split; < 1 false action / hour on normal-use replays (measured when the user has recorded them).

### Class mapping (HaGRID label → model class)

| Model class | HaGRID labels |
|---|---|
| openPalm | palm, stop |
| fist | fist |
| point | one |
| two | peace, two_up |
| three | three, three2, three3 |
| ok | ok |
| thumbsUp | like |
| thumbsDown | dislike |
| none | no_gesture, four, point, thumb_index, thumb_index2, grip, grabbing, call, rock, mute, little_finger, middle_finger, hand_heart, hand_heart2, holy, take_picture, timeout, xsign, peace_inverted, two_up_inverted, stop_inverted |

Per-source-class sample sizes: positive sources 900 train / 150 val / 250 test; none sources 200 / 40 / 60. Second hands labelled `no_gesture` inside any image are kept as extra `none` samples.

## Review Focus

1. **Subject leakage** — a user id appearing in two splits inflates test accuracy. Test in Task 1 (`manifestSplitsAreSubjectDisjoint`).
2. **Wrong hand matched to a box** — two hands in an image, features assigned to the other hand's label. Test in Task 2 (`matcherPicksHandInsideBox`, `matcherIgnoresHandOutsideAllBoxes`).
3. **Standardization not carried into Core ML** — model trained on standardized inputs receives raw vectors at runtime. Test in Task 3 (`foldedModelMatchesStandardizedModel`, `coremlMatchesTorch`).
4. **Missing / corrupt model in the app** — must fall back to rules, never crash. Test in Task 4 (`loadingMissingModelThrows`) + fallback in `AppModel`/`Pipeline`.
5. **Class imbalance** — `none` dominates and suppresses real gestures. Class-weighted loss; per-class recall reported; Task 3 test `classWeightsInverseToFrequency`.

---

### Task 1: Dataset selection and fetch (`tools/dataset`)

**Files:** Create `tools/dataset/{pyproject.toml,classes.py,select_subset.py,fetch.py}`, `tools/dataset/tests/test_select.py`.

**Interfaces — Produces:**
- `classes.py`: `TARGET_CLASSES: list[str]` (9, order above), `SOURCE_TO_TARGET: dict[str, str]`, `POSITIVE_SOURCES`, `NONE_SOURCES`, `SPLIT_SIZES = {"positive": {"train": 900, "val": 150, "test": 250}, "none": {"train": 200, "val": 40, "test": 60}}`.
- `select_subset.py`: `select(records: dict[str, dict], source: str, split: str, n: int, seed: int = 42) -> list[dict]` (deterministic sample of annotation records for one class/split; each output `{"image_id", "source", "split", "user_id", "boxes": [{"label": target, "bbox": [x, y, w, h]}]}` with every box label mapped via `SOURCE_TO_TARGET`, unknown labels dropped).
- `fetch.py` CLI: `uv run fetch.py [--out ../../data/hagrid] [--workers 16]` → `data/hagrid/annotations/<split>/<source>.json`, `data/hagrid/images/<source>/<image_id>.jpg`, `data/hagrid/manifest.jsonl` (one `select` record per line). Resumable: existing images are skipped. Prints counts and total bytes.

- [ ] Step 1: tests `test_mapping_covers_all_sources` (every source maps to a target in TARGET_CLASSES), `test_select_is_deterministic` (same seed → same ids), `test_select_maps_box_labels` (record with labels `["palm","no_gesture"]` → box labels `["openPalm","none"]`), `test_manifest_splits_are_subject_disjoint` (given records where one user is in train and test, `check_disjoint` raises).
- [ ] Step 2: `uv run pytest` → fails (module missing).
- [ ] Step 3: implement; `check_disjoint(manifest: list[dict]) -> None` raises `ValueError` on overlap.
- [ ] Step 4: `uv run pytest` → passes.
- [ ] Step 5: run `uv run fetch.py`; expected ≈ 20 k images, ≤ 3 GB; `check_disjoint` passes on the real manifest.
- [ ] Step 6: commit `feat(tools): HaGRID subset selection and fetch`.

### Task 2: Landmark extraction CLI (`ec-extract`)

**Files:** Create `Packages/EasyControlCore/Sources/Capture/HandBoxMatcher.swift`, `Sources/ec-extract/main.swift`, `Tests/CaptureTests/HandBoxMatcherTests.swift`; modify `Package.swift` (executable target `ec-extract` → Capture, Signal).

**Interfaces — Produces:**
- `public struct LabeledBox: Sendable { var label: String; var rect: CGRect /* image coords, top-left origin, unmirrored, normalized */ }`
- `public enum HandBoxMatcher { static func match(hands: [Hand], boxes: [LabeledBox]) -> [(box: Int, hand: Int)] }` — palm centre converted back to unmirrored image coords (`x = 1 − x'`); a hand matches a box whose rect contains its palm centre; ties → nearest rect centre; each hand and box used at most once.
- `ec-extract --manifest <jsonl> --images <dir> --out <jsonl> [--jobs N]` → one line per matched box: `{"image_id","split","user_id","source","label","vector":[52],"reliable":bool,"known":bool,"chirality"}`; prints images processed, hands detected, boxes matched/unmatched.

- [ ] Step 1: tests `matcherPicksHandInsideBox` (two synthetic hands at x' 0.3 and 0.7; box around unmirrored x 0.3 ⇒ matches the hand at x' 0.7), `matcherIgnoresHandOutsideAllBoxes`, `matcherUsesEachHandOnce`.
- [ ] Step 2: run → fails. Step 3: implement. Step 4: run → passes.
- [ ] Step 5: implement `ec-extract` (concurrent over images with one `VisionHandDetector` per worker); run on the full manifest → `data/hagrid/features.jsonl`. Expected: ≥ 85 % of boxes matched.
- [ ] Step 6: commit `feat(tools): ec-extract landmark extraction with box matching`.

### Task 3: Training, Core ML export, evaluation report (`tools/training`)

**Files:** Create `tools/training/{pyproject.toml,data.py,model.py,train.py,report.py}`, `tools/training/tests/test_training.py`; outputs `App/Resources/PoseClassifier.mlpackage`, `App/Resources/MODEL_LICENSE.md`, `docs/eval/m3-report.md`, `docs/eval/m3-metrics.json`, `Packages/EasyControlCore/Tests/GestureEngineTests/Fixtures/pose-fixture.jsonl` (300 test-split samples).

**Interfaces — Produces:**
- `data.load(path) -> (X: np.ndarray[N,52], y: np.ndarray[N], meta: list[dict])`, keeping only `reliable and known` rows.
- `model.PoseMLP(mean, std, n_classes)`: `Normalize(mean,std) → Linear(52,128) → ReLU → Dropout(0.2) → Linear(128,64) → ReLU → Dropout(0.2) → Linear(64,9)`; `forward` returns logits; `export_coreml(model, path, class_labels)` traces with softmax and converts via `coremltools` (`ct.ClassifierConfig(class_labels)`, input `features` shape (1,52) float32, minimum target macOS15).
- `train.py`: AdamW lr 1e-3, wd 1e-4, batch 256, ≤ 80 epochs, early stop on val macro-F1 (patience 10), class-weighted CE (weights ∝ 1/frequency, normalized to mean 1), seed 42.
- `report.py`: per-class precision/recall/F1, confusion matrix, split sizes, gate drop rate, comparison with the rule-based classifier on the same test vectors.

- [ ] Step 1: tests `test_class_weights_inverse_to_frequency`, `test_folded_model_matches_standardized_model` (PoseMLP with Normalize on raw x == same weights without Normalize on (x−mean)/std, atol 1e-5), `test_coreml_matches_torch` (export tiny random model, Core ML probs ≈ torch softmax on 5 inputs, atol 1e-4), `test_load_filters_gated_rows`.
- [ ] Step 2: `uv run pytest` → fails. Step 3: implement. Step 4: passes.
- [ ] Step 5: `uv run train.py` → test accuracy reported; target ≥ 97 %. If below, record the shortfall and per-class causes in the report (do not tune on the test split).
- [ ] Step 6: commit `feat(ml): pose classifier training, Core ML export, evaluation report`.

### Task 4: `CoreMLPoseClassifier` and app integration

**Files:** Create `Sources/GestureEngine/CoreMLPoseClassifier.swift`, `Tests/GestureEngineTests/CoreMLPoseClassifierTests.swift`; modify `project.yml` (resource), `App/Pipeline.swift`, `App/Views/DebugView.swift`, `GestureEngine.swift` (`snapshot.classifierName`).

**Interfaces — Produces:**
- `public final class CoreMLPoseClassifier: PoseClassifying { init(compiledModelURL: URL) throws; static func compile(_ packageURL: URL) async throws -> URL; func classify(_ f: HandFeatures) -> [PoseClass: Float] }` — gate first (`!isReliable || fingerKnown.contains(false)` → `[.none: 1]`); `MLModelConfiguration.computeUnits = .cpuOnly`; maps `classProbability` keys to `PoseClass(rawValue:)`; probabilities renormalized to sum 1.
- `PoseClassifying` gains `var name: String { get }` (rules: "rules", Core ML: "coreml").
- Pipeline: load `PoseClassifier.mlmodelc` from `Bundle.main`; on failure log and use `RuleBasedPoseClassifier`.

- [ ] Step 1: tests `fixtureAccuracy` (≥ 95 % on committed fixture via compiled model from `App/Resources/PoseClassifier.mlpackage`), `probabilitiesSumToOne`, `gatedFeaturesAreNone`, `loadingMissingModelThrows`.
- [ ] Step 2: run → fails. Step 3: implement. Step 4: passes.
- [ ] Step 5: `scripts/build-app.sh` → succeeds; bundle contains `PoseClassifier.mlmodelc`.
- [ ] Step 6: commit `feat(engine): Core ML pose classifier with rule-based fallback`.

### Task 5: False-trigger replay benchmark (`ec-replay`)

**Files:** Create `Sources/GestureEngine/ReplayBenchmark.swift`, `Sources/ec-replay/main.swift`, `Tests/GestureEngineTests/ReplayBenchmarkTests.swift`; modify `Package.swift`.

**Interfaces — Produces:**
- `public struct ReplayStats: Sendable, Equatable { var duration: Double; var engagements: Int; var discreteEvents: Int; var scrollsBegan: Int; var actionsPerHour: Double }`
- `public enum ReplayBenchmark { static func run(_ frames: [HandFrame], engine: GestureEngine) -> ReplayStats }` (lastUserInput nil; actions = discrete + scroll began).
- `ec-replay [--model <mlpackage>] <recording.jsonl>...` prints a table and the total actions/hour.

- [ ] Step 1: tests `statsCountActions` (scripted engage + swipe + scroll ⇒ engagements 1, discrete 1, scrollsBegan 1, duration from timestamps), `idleRecordingHasNoActions`.
- [ ] Step 2–4: fail → implement → pass.
- [ ] Step 5: commit `feat(tools): ec-replay false-trigger benchmark`.

### Task 6: Docs and verification

- [ ] Update README (ML pipeline, results table, licence), `docs/qa/m2-checklist.md` (verify Core ML poses live; record normal-use for `ec-replay`), full test suite + app build + CI green; commit `docs: M3 results`.

## Deferred

- Create ML hand-pose baseline (spec §6.3) → after the user's live session, when it can be compared on the user's own recordings too.
- Pinch class and user-recording fine-tuning → after recordings exist.
