"""Trains the pose classifier on ec-extract features, evaluates on held-out subjects, exports Core ML.

Usage:
  uv run train.py --sweep   # model selection on the validation split, then train + export the winner
  uv run train.py           # train + export the configuration recorded in docs/eval/m3-sweep.json (or defaults)
"""
import argparse
import datetime
import itertools
import json
import pathlib
import random

import numpy as np
import torch
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_recall_fscore_support
from torch import nn

from data import CLASSES, class_weights, load, passes_gate
from model import PoseMLP, export_coreml
from report import render

ROOT = pathlib.Path(__file__).resolve().parents[2]
SWEEP_FILE = ROOT / "docs/eval/m3-sweep.json"
FLAG_OFFSET = 42  # HandFeatures.vector: 42 coords, then 5 extension flags (thumb...little)
THRESHOLD = 0.85  # GestureConfig.poseEnter: the app only acts on poses this confident
NONE = CLASSES.index("none")
RULE_CLASSES = ["openPalm", "fist", "point", "two", "three", "none"]
DEFAULT = {"gate": "reliable", "weight_power": 0.0, "hidden": [256, 128]}
GRID = {"gate": ["known", "reliable"], "weight_power": [0.0, 0.5], "hidden": [[128, 64], [256, 128]]}


def seed() -> None:
    torch.manual_seed(42)
    np.random.seed(42)
    random.seed(42)


def rules(X: np.ndarray) -> np.ndarray:
    """Python mirror of Swift `RuleBasedPoseClassifier` (its gate is applied separately)."""
    out = []
    for flags in (X[:, FLAG_OFFSET:FLAG_OFFSET + 5] > 0.5):
        thumb, fingers = flags[0], tuple(flags[1:])
        label = ("openPalm" if thumb and fingers == (True, True, True, True) else
                 "two" if fingers == (True, True, False, False) else
                 "point" if fingers == (True, False, False, False) else
                 "three" if fingers == (True, True, True, False) else
                 "fist" if fingers == (False, False, False, False) else "none")
        out.append(CLASSES.index(label))
    return np.asarray(out)


class Split:
    """Every matched hand of one split (augmented copies only for training), with its gate result."""

    def __init__(self, path: pathlib.Path, split: str, gate: str, augmented: bool):
        X, y, meta = load(path, gate="none", augmented=augmented)
        keep = np.array([m["split"] == split for m in meta])
        self.X, self.y = X[keep], y[keep]
        self.meta = [m for m, k in zip(meta, keep) if k]
        self.gated = np.array([passes_gate(m, gate) for m in self.meta])
        self.known = np.array([passes_gate(m, "known") for m in self.meta])
        self.users = len({m["user_id"] for m in self.meta})


def probabilities(model: PoseMLP, X: np.ndarray) -> np.ndarray:
    model.eval()
    with torch.no_grad():
        return torch.softmax(model(torch.from_numpy(X)), dim=1).numpy()


def evaluate(model: PoseMLP, s: Split) -> dict:
    """End-to-end like the app: rows failing the gate are `none`; the app acts only above THRESHOLD."""
    probs = np.zeros((len(s.y), len(CLASSES)), np.float32)
    probs[:, NONE] = 1
    probs[s.gated] = probabilities(model, s.X[s.gated])
    argmax = probs.argmax(1)
    acted = np.where(probs.max(1) >= THRESHOLD, argmax, NONE)
    labels = list(range(len(CLASSES)))
    _, recall, _, support = precision_recall_fscore_support(s.y, acted, labels=labels, zero_division=0)
    gestures = acted != NONE
    return {
        "gated_accuracy": float(accuracy_score(s.y[s.gated], argmax[s.gated])),
        "gated_macro_f1": float(f1_score(s.y[s.gated], argmax[s.gated], average="macro")),
        "end_to_end_accuracy": float(accuracy_score(s.y, argmax)),
        "acted_accuracy": float(accuracy_score(s.y, acted)),
        "acted_gesture_precision": float(np.mean(acted[gestures] == s.y[gestures])) if gestures.any() else 0.0,
        "none_false_trigger_rate": float(np.mean(acted[s.y == NONE] != NONE)),
        "acted_recall": {c: float(recall[i]) for i, c in enumerate(CLASSES)},
        "support": {c: int(support[i]) for i, c in enumerate(CLASSES)},
        "confusion_acted": confusion_matrix(s.y, acted, labels=labels).tolist(),
        "gate_kept": float(s.gated.mean()),
    }


def evaluate_rules(s: Split) -> dict:
    pred = np.where(s.known, rules(s.X), NONE)  # the rules always used the strict "known" gate
    mask = np.isin(s.y, [CLASSES.index(c) for c in RULE_CLASSES])
    return {"end_to_end_accuracy": float(accuracy_score(s.y, pred)),
            "own_classes_accuracy": float(accuracy_score(s.y[mask], pred[mask]))}


def fit(train: Split, val: Split, cfg: dict, epochs: int = 80) -> tuple[PoseMLP, int]:
    seed()
    X, y = train.X[train.gated], train.y[train.gated]
    model = PoseMLP(X.mean(0), X.std(0), len(CLASSES), hidden=tuple(cfg["hidden"]))
    loss_fn = nn.CrossEntropyLoss(weight=torch.from_numpy(class_weights(y, len(CLASSES), cfg["weight_power"])))
    opt = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=1e-4)
    Xt, yt = torch.from_numpy(X), torch.from_numpy(y)
    best = (-1.0, 0, None)
    for epoch in range(1, epochs + 1):
        model.train()
        perm = torch.randperm(len(Xt))
        for i in range(0, len(perm), 256):
            idx = perm[i:i + 256]
            opt.zero_grad()
            loss_fn(model(Xt[idx]), yt[idx]).backward()
            opt.step()
        score = evaluate(model, val)["acted_accuracy"]
        if score > best[0]:
            best = (score, epoch, {k: v.clone() for k, v in model.state_dict().items()})
        elif epoch - best[1] >= 10:
            break
    model.load_state_dict(best[2])
    return model, best[1]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--features", default=str(ROOT / "data/hagrid/features.jsonl"))
    p.add_argument("--sweep", action="store_true", help="select the configuration on the validation split first")
    args = p.parse_args()
    path = pathlib.Path(args.features)

    cfg, sweep = dict(DEFAULT), []
    if args.sweep:
        for gate, power, hidden in itertools.product(GRID["gate"], GRID["weight_power"], GRID["hidden"]):
            c = {"gate": gate, "weight_power": power, "hidden": hidden}
            model, _ = fit(Split(path, "train", gate, True), Split(path, "val", gate, False), c)
            v = evaluate(model, Split(path, "val", gate, False))
            sweep.append({**c, "val": {k: v[k] for k in ("acted_accuracy", "acted_gesture_precision",
                                                         "none_false_trigger_rate", "gated_accuracy")}})
            print(f"VAL {c} acted_acc={v['acted_accuracy']:.4f} precision={v['acted_gesture_precision']:.4f}")
        best = max(sweep, key=lambda r: r["val"]["acted_accuracy"])
        cfg = {k: best[k] for k in ("gate", "weight_power", "hidden")}
        SWEEP_FILE.parent.mkdir(parents=True, exist_ok=True)
        SWEEP_FILE.write_text(json.dumps({"criterion": "highest validation accuracy at the app threshold (0.85), "
                                                       "gated rows counted as none",
                                          "chosen": cfg, "runs": sweep}, indent=2) + "\n")
    elif SWEEP_FILE.exists():
        recorded = json.loads(SWEEP_FILE.read_text())
        cfg, sweep = recorded["chosen"], recorded["runs"]

    train, val = Split(path, "train", cfg["gate"], True), Split(path, "val", cfg["gate"], False)
    test = Split(path, "test", cfg["gate"], False)
    model, best_epoch = fit(train, val, cfg)
    result = evaluate(model, test)

    mlmodel = export_coreml(model, ROOT / "App/Resources/PoseClassifier.mlpackage", CLASSES, gate=cfg["gate"])
    Xg = test.X[test.gated]
    n = min(300, len(Xg))
    torch_pred = probabilities(model, Xg[:n]).argmax(1)
    coreml_pred = [CLASSES.index(mlmodel.predict({"features": Xg[i:i + 1]})["classLabel"]) for i in range(n)]

    metrics = {
        "date": datetime.date.today().isoformat(),
        "classes": CLASSES,
        "threshold": THRESHOLD,
        "config": cfg,
        "selection": {"criterion": "highest validation accuracy at the app threshold, gated rows counted as none",
                      "runs": sweep},
        "sizes": {"train_rows_incl_augmented": int(train.gated.sum()), "val": len(val.y), "test": len(test.y)},
        "subjects": {"train": train.users, "val": val.users, "test": test.users},
        "training": {"best_epoch": best_epoch},
        "test": result,
        "rules": evaluate_rules(test),
        "coreml_check": {"n": n, "agreement": float(np.mean(np.array(coreml_pred) == torch_pred))},
    }
    (ROOT / "docs/eval/m3-metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    (ROOT / "docs/eval/m3-report.md").write_text(render(metrics))

    fixture = ROOT / "Packages/EasyControlCore/Tests/GestureEngineTests/Fixtures/pose-fixture.jsonl"
    rng = np.random.default_rng(42)
    rows = []
    for c in range(len(CLASSES)):
        idx = np.flatnonzero(test.y[test.gated] == c)
        for i in rng.choice(idx, size=min(34, len(idx)), replace=False):
            rows.append(json.dumps({"label": CLASSES[c], "vector": [round(float(v), 6) for v in Xg[i]]}))
    fixture.write_text("\n".join(rows) + "\n")

    print(f"config {cfg}  test: acted {result['acted_accuracy']:.4f}  end-to-end {result['end_to_end_accuracy']:.4f}  "
          f"gated {result['gated_accuracy']:.4f}  precision {result['acted_gesture_precision']:.4f}  "
          f"none→gesture {result['none_false_trigger_rate']:.4f}  coreml agreement {metrics['coreml_check']['agreement']:.3f}")


if __name__ == "__main__":
    main()
