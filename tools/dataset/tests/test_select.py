import pytest

from classes import NONE_SOURCES, POSITIVE_SOURCES, SOURCE_TO_TARGET, TARGET_CLASSES
from select_subset import check_disjoint, select


def records(n, user="u", labels=("palm",)):
    return {
        f"img{i}": {"user_id": f"{user}{i % 5}", "labels": list(labels), "bboxes": [[0.1, 0.1, 0.2, 0.3]] * len(labels)}
        for i in range(n)
    }


def test_mapping_covers_all_sources():
    for source in POSITIVE_SOURCES + NONE_SOURCES + ["no_gesture"]:
        assert SOURCE_TO_TARGET[source] in TARGET_CLASSES
    assert len(TARGET_CLASSES) == 9


def test_select_is_deterministic():
    recs = records(100)
    a = [r["image_id"] for r in select(recs, "palm", "train", 10)]
    b = [r["image_id"] for r in select(recs, "palm", "train", 10)]
    assert a == b and len(a) == 10


def test_select_maps_box_labels():
    recs = records(3, labels=("palm", "no_gesture"))
    out = select(recs, "palm", "test", 3)
    assert all([b["label"] for b in r["boxes"]] == ["openPalm", "none"] for r in out)
    assert out[0]["source"] == "palm" and out[0]["split"] == "test"


def test_manifest_splits_are_subject_disjoint():
    manifest = [
        {"image_id": "a", "split": "train", "user_id": "u1"},
        {"image_id": "b", "split": "test", "user_id": "u1"},
    ]
    with pytest.raises(ValueError):
        check_disjoint(manifest)
    check_disjoint([{"image_id": "a", "split": "train", "user_id": "u1"}, {"image_id": "b", "split": "test", "user_id": "u2"}])
