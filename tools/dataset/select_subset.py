"""Deterministic selection of annotation records."""
import random

from classes import SOURCE_TO_TARGET


def select(records: dict[str, dict], source: str, split: str, n: int, seed: int = 42) -> list[dict]:
    """Samples `n` images of one HaGRID class/split; box labels are mapped to model classes."""
    ids = sorted(records)
    picked = random.Random(f"{seed}-{source}-{split}").sample(ids, min(n, len(ids)))
    out = []
    for image_id in sorted(picked):
        rec = records[image_id]
        if not rec.get("user_id"):
            continue  # without a subject id the split can't be checked for leakage
        boxes = [
            {"label": SOURCE_TO_TARGET[label], "bbox": bbox}
            for label, bbox in zip(rec["labels"], rec["bboxes"])
            if label in SOURCE_TO_TARGET
        ]
        if boxes:
            out.append({"image_id": image_id, "source": source, "split": split, "user_id": rec["user_id"], "boxes": boxes})
    return out


def check_disjoint(manifest: list[dict]) -> None:
    """Raises if any subject appears in more than one split (test accuracy would be inflated)."""
    splits: dict[str, set[str]] = {}
    for rec in manifest:
        splits.setdefault(rec["user_id"], set()).add(rec["split"])
    leaked = [user for user, s in splits.items() if len(s) > 1]
    if leaked:
        raise ValueError(f"{len(leaked)} subjects appear in more than one split, e.g. {leaked[0][:12]}")
