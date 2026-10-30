"""Scores two pose models on the user's held-out recording segments (end to end, acting at the app threshold).

Usage: uv run compare_baseline.py <baseline.mlpackage> [<model.mlpackage>]
Writes docs/eval/m3-personal-baseline.json.
"""
import json
import pathlib
import sys

import coremltools as ct
import numpy as np

from data import passes_gate

ROOT = pathlib.Path(__file__).resolve().parents[2]
THRESHOLD = 0.85


def score(path: str, rows: list[dict], gate: str) -> dict:
    model = ct.models.MLModel(path)
    per: dict[str, list[int]] = {}
    correct = 0
    for r in rows:
        pred = "none"
        if passes_gate(r, gate):
            probs = model.predict({"features": np.array([r["vector"]], dtype="f")})["classLabel_probs"]
            top = max(probs, key=probs.get)
            pred = top if probs[top] >= THRESHOLD else "none"
        hit = pred == r["label"]
        correct += hit
        per.setdefault(r["label"], [0, 0])
        per[r["label"]][0] += hit
        per[r["label"]][1] += 1
    no_pinch = [(h, n) for c, (h, n) in per.items() if c != "pinch"]
    return {"acted_accuracy": correct / len(rows),
            "acted_accuracy_excluding_pinch": sum(h for h, _ in no_pinch) / sum(n for _, n in no_pinch),
            "recall": {c: h / n for c, (h, n) in per.items()}}


def main() -> None:
    baseline = sys.argv[1]
    model = sys.argv[2] if len(sys.argv) > 2 else str(ROOT / "App/Resources/PoseClassifier.mlpackage")
    rows = [json.loads(line) for line in open(ROOT / "data/local/features.jsonl")]
    rows = [r for r in rows if r["split"] == "test" and not r["augmented"]]
    gate = ct.models.MLModel(model, skip_model_load=True).user_defined_metadata.get("gate", "reliable")
    out = {"rows": len(rows), "threshold": THRESHOLD, "gate": gate,
           "baseline (HaGRID only)": score(baseline, rows, gate), "personalized": score(model, rows, gate)}
    (ROOT / "docs/eval/m3-personal-baseline.json").write_text(json.dumps(out, indent=2) + "\n")
    for name in ("baseline (HaGRID only)", "personalized"):
        print(f"{name}: {out[name]['acted_accuracy']:.4f} (excluding pinch {out[name]['acted_accuracy_excluding_pinch']:.4f})")


if __name__ == "__main__":
    main()
