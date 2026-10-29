"""Loads ec-extract feature files."""
import json
import pathlib

import numpy as np

# Same order and raw values as Swift `PoseClass` (pinch excluded: no training data yet).
CLASSES = ["openPalm", "fist", "point", "two", "three", "ok", "thumbsUp", "thumbsDown", "none"]


def load(path: str | pathlib.Path) -> tuple[np.ndarray, np.ndarray, list[dict]]:
    """Returns features, class indices and per-row metadata, keeping only rows that pass the runtime gate
    (reliable hand, every finger known); the app sends anything else straight to `none`."""
    X, y, meta = [], [], []
    with open(path) as f:
        for line in f:
            if not line.strip():
                continue
            row = json.loads(line)
            if not (row["reliable"] and row["known"]) or row["label"] not in CLASSES:
                continue
            X.append(row["vector"])
            y.append(CLASSES.index(row["label"]))
            meta.append({k: v for k, v in row.items() if k != "vector"})
    return np.asarray(X, dtype=np.float32).reshape(-1, 52), np.asarray(y, dtype=np.int64), meta


def class_weights(y: np.ndarray, n_classes: int, power: float = 1.0) -> np.ndarray:
    """(1/frequency)^power, normalized to mean 1. power=1 balances classes fully, 0 disables weighting."""
    counts = np.maximum(np.bincount(y, minlength=n_classes), 1).astype(np.float64)
    w = (1.0 / counts) ** power
    return (w / w.mean()).astype(np.float32)
