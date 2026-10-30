"""Loads ec-extract feature files."""
import json
import pathlib

import numpy as np

# Raw values of Swift `PoseClass`. `pinch` comes only from the user's own recordings (HaGRID has none).
CLASSES = ["openPalm", "fist", "point", "two", "three", "ok", "thumbsUp", "thumbsDown", "pinch", "none"]
# Must equal Swift `HandFeatures.vectorLength`.
N_FEATURES = 55


def passes_gate(row: dict, gate: str) -> bool:
    """The app's runtime gate: "reliable" = wrist and knuckles confidently detected; "known" additionally
    requires every finger's middle joint and tip. Rows failing it are classified `none` without the model."""
    if gate == "none":
        return True
    return bool(row["reliable"] and (gate == "reliable" or row["known"]))


LOCAL_USER = "local-user"


def load(path: str | pathlib.Path | list, gate: str = "reliable", augmented: bool = False) -> tuple[np.ndarray, np.ndarray, list[dict]]:
    """Returns features, class indices and per-row metadata for rows passing `gate`, from one file or a list.
    Chirality-flipped augmentation rows are included only when `augmented` is true (training)."""
    X, y, meta = [], [], []
    paths = [pathlib.Path(p) for p in (path if isinstance(path, list) else [path])]
    for p in (p for p in paths if p.exists()):
        with open(p) as f:
            for line in f:
                if not line.strip():
                    continue
                row = json.loads(line)
                if row.get("augmented", False) and not augmented:
                    continue
                if not passes_gate(row, gate) or row["label"] not in CLASSES:
                    continue
                X.append(row["vector"])
                y.append(CLASSES.index(row["label"]))
                meta.append({k: v for k, v in row.items() if k != "vector"})
    return np.asarray(X, dtype=np.float32).reshape(-1, N_FEATURES), np.asarray(y, dtype=np.int64), meta


def class_weights(y: np.ndarray, n_classes: int, power: float = 1.0) -> np.ndarray:
    """(1/frequency)^power, normalized to mean 1. power=1 balances classes fully, 0 disables weighting."""
    counts = np.maximum(np.bincount(y, minlength=n_classes), 1).astype(np.float64)
    w = (1.0 / counts) ** power
    return (w / w.mean()).astype(np.float32)
