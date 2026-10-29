"""Trains the pose classifier on ec-extract features, evaluates on held-out subjects, exports Core ML.

Usage: uv run train.py [--features ../../data/hagrid/features.jsonl]
"""
import argparse
import datetime
import json
import pathlib
import random

import numpy as np
import torch
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_recall_fscore_support
from torch import nn

from data import CLASSES, class_weights, load
from model import PoseMLP, export_coreml
from report import render

ROOT = pathlib.Path(__file__).resolve().parents[2]
# Validation results from `train.py --val-only` (2026-10-30): weight power, hidden, acc, macro F1, gesture precision.
SWEEP = [
    (1.0, "128,64", 0.9590, 0.9474, 0.9456), (1.0, "256,128", 0.9606, 0.9501, 0.9465),
    (0.5, "128,64", 0.9623, 0.9516, 0.9552), (0.5, "256,128", 0.9688, 0.9574, 0.9609),
    (0.0, "128,64", 0.9712, 0.9607, 0.9682), (0.0, "256,128", 0.9716, 0.9601, 0.9689),
]
FLAG_OFFSET = 42  # HandFeatures.vector: 42 coords, then 5 extension flags (thumb...little), then 5 angles


def rules(X: np.ndarray) -> np.ndarray:
    """Python mirror of Swift `RuleBasedPoseClassifier` (gated rows only), for the comparison row."""
    out = []
    for flags in (X[:, FLAG_OFFSET:FLAG_OFFSET + 5] > 0.5):
        thumb, fingers = flags[0], tuple(flags[1:])
        if thumb and fingers == (True, True, True, True):
            label = "openPalm"
        elif fingers == (True, True, False, False):
            label = "two"
        elif fingers == (True, False, False, False):
            label = "point"
        elif fingers == (True, True, True, False):
            label = "three"
        elif fingers == (False, False, False, False):
            label = "fist"
        else:
            label = "none"
        out.append(CLASSES.index(label))
    return np.asarray(out)


def gate_counts(path: pathlib.Path) -> dict:
    total = kept = 0
    with open(path) as f:
        for line in f:
            row = json.loads(line)
            total += 1
            kept += bool(row["reliable"] and row["known"])
    return {"total": total, "kept": kept}


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--features", default=str(ROOT / "data/hagrid/features.jsonl"))
    p.add_argument("--epochs", type=int, default=80)
    p.add_argument("--weight-power", type=float, default=0.0, help="class weighting: 1 = inverse frequency, 0 = none")
    p.add_argument("--hidden", default="256,128")
    p.add_argument("--val-only", action="store_true", help="print validation metrics and stop (model selection)")
    args = p.parse_args()
    hidden = tuple(int(h) for h in args.hidden.split(","))
    torch.manual_seed(42); np.random.seed(42); random.seed(42)

    X, y, meta = load(args.features)
    split = np.array([m["split"] for m in meta])
    parts = {s: (X[split == s], y[split == s]) for s in ("train", "val", "test")}
    users = {s: len({m["user_id"] for m in meta if m["split"] == s}) for s in parts}
    Xtr, ytr = parts["train"]
    model = PoseMLP(Xtr.mean(0), Xtr.std(0), len(CLASSES), hidden=hidden)
    loss_fn = nn.CrossEntropyLoss(weight=torch.from_numpy(class_weights(ytr, len(CLASSES), args.weight_power)))
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=1e-4)
    Xtr_t, ytr_t = torch.from_numpy(Xtr), torch.from_numpy(ytr)

    def predict(Xs: np.ndarray) -> np.ndarray:
        model.eval()
        with torch.no_grad():
            return model(torch.from_numpy(Xs)).argmax(1).numpy()

    best = {"f1": -1.0, "epoch": 0, "state": None}
    patience = 10
    for epoch in range(1, args.epochs + 1):
        model.train()
        perm = torch.randperm(len(Xtr_t))
        for i in range(0, len(perm), 256):
            idx = perm[i:i + 256]
            opt.zero_grad()
            loss_fn(model(Xtr_t[idx]), ytr_t[idx]).backward()
            opt.step()
        val_f1 = f1_score(parts["val"][1], predict(parts["val"][0]), average="macro")
        if val_f1 > best["f1"]:
            best = {"f1": val_f1, "epoch": epoch, "state": {k: v.clone() for k, v in model.state_dict().items()}}
        elif epoch - best["epoch"] >= patience:
            break
        print(f"epoch {epoch:3d}  val macro F1 {val_f1:.4f}")
    model.load_state_dict(best["state"])

    if args.val_only:
        Xv, yv = parts["val"]
        vp = predict(Xv)
        none = CLASSES.index("none")
        none_prec = float(np.mean(vp[vp != none] == yv[vp != none]))  # how often a predicted gesture is real
        print(f"VAL weight_power={args.weight_power} hidden={args.hidden} acc={accuracy_score(yv, vp):.4f} "
              f"macroF1={f1_score(yv, vp, average='macro'):.4f} gesture_precision={none_prec:.4f}")
        return

    Xte, yte = parts["test"]
    pred = predict(Xte)
    labels = list(range(len(CLASSES)))
    prec, rec, f1, sup = precision_recall_fscore_support(yte, pred, labels=labels, zero_division=0)
    rule_pred = rules(Xte)

    out_model = ROOT / "App/Resources/PoseClassifier.mlpackage"
    mlmodel = export_coreml(model, out_model, CLASSES)
    n = min(300, len(Xte))
    coreml_pred = [CLASSES.index(mlmodel.predict({"features": Xte[i:i + 1]})["classLabel"]) for i in range(n)]
    agreement = float(np.mean(np.array(coreml_pred) == pred[:n]))

    metrics = {
        "date": datetime.date.today().isoformat(),
        "classes": CLASSES,
        "sizes": {s: int(len(parts[s][1])) for s in parts},
        "subjects": users,
        "gate": gate_counts(pathlib.Path(args.features)),
        "training": {"best_epoch": best["epoch"], "best_val_f1": float(best["f1"]),
                     "weight_power": args.weight_power, "hidden": list(hidden)},
        "test": {
            "accuracy": float(accuracy_score(yte, pred)),
            "macro_f1": float(f1_score(yte, pred, average="macro")),
            "per_class": {c: {"precision": float(prec[i]), "recall": float(rec[i]), "f1": float(f1[i]), "support": int(sup[i])}
                          for i, c in enumerate(CLASSES)},
            "confusion": confusion_matrix(yte, pred, labels=labels).tolist(),
        },
        "rules": {"accuracy": float(accuracy_score(yte, rule_pred)), "macro_f1": float(f1_score(yte, rule_pred, average="macro"))},
        "coreml_check": {"n": n, "agreement": agreement},
        "sweep": SWEEP,
    }
    (ROOT / "docs/eval").mkdir(parents=True, exist_ok=True)
    (ROOT / "docs/eval/m3-metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    (ROOT / "docs/eval/m3-report.md").write_text(render(metrics))

    # Small stratified fixture of real test vectors for the Swift Core ML test.
    fixture = ROOT / "Packages/EasyControlCore/Tests/GestureEngineTests/Fixtures/pose-fixture.jsonl"
    fixture.parent.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(42)
    rows = []
    for c in labels:
        idx = np.flatnonzero(yte == c)
        for i in rng.choice(idx, size=min(34, len(idx)), replace=False):
            rows.append(json.dumps({"label": CLASSES[c], "vector": [round(float(v), 6) for v in Xte[i]]}))
    fixture.write_text("\n".join(rows) + "\n")

    t = metrics["test"]
    print(f"test accuracy {t['accuracy']:.4f}  macro F1 {t['macro_f1']:.4f}  rules {metrics['rules']['accuracy']:.4f}  "
          f"coreml agreement {agreement:.3f}  fixture {len(rows)} rows")


if __name__ == "__main__":
    main()
