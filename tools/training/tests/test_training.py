import json

import numpy as np
import torch

from data import CLASSES, N_FEATURES, class_weights, load
from model import Normalize, PoseMLP, export_coreml


def test_class_weights_inverse_to_frequency():
    y = np.array([0] * 90 + [1] * 10)
    w = class_weights(y, n_classes=2)
    assert abs(float(w[1] / w[0]) - 9) < 1e-5
    assert abs(float(w.mean()) - 1) < 1e-6


def test_folded_model_matches_standardized_model():
    torch.manual_seed(0)
    mean, std = np.random.rand(N_FEATURES).astype("f"), (np.random.rand(N_FEATURES) + 0.5).astype("f")
    folded = PoseMLP(mean, std, len(CLASSES)).eval()
    plain = PoseMLP(np.zeros(N_FEATURES, "f"), np.ones(N_FEATURES, "f"), len(CLASSES)).eval()
    plain.load_state_dict({k: v for k, v in folded.state_dict().items() if not k.startswith("norm.")}, strict=False)
    x = torch.rand(8, N_FEATURES)
    expected = plain((x - torch.from_numpy(mean)) / torch.from_numpy(std))
    assert torch.allclose(folded(x), expected, atol=1e-5)


def test_coreml_matches_torch(tmp_path):
    torch.manual_seed(1)
    model = PoseMLP(np.zeros(N_FEATURES, "f"), np.ones(N_FEATURES, "f"), len(CLASSES)).eval()
    path = tmp_path / "m.mlpackage"
    mlmodel = export_coreml(model, path, CLASSES, gate="known")
    assert mlmodel.user_defined_metadata["gate"] == "known"
    x = np.random.rand(5, N_FEATURES).astype("f")
    torch_probs = torch.softmax(model(torch.from_numpy(x)), dim=1).detach().numpy()
    for i in range(5):
        out = mlmodel.predict({"features": x[i:i + 1]})
        probs = out["classLabel_probs"]
        assert np.allclose([probs[c] for c in CLASSES], torch_probs[i], atol=1e-4)


def write_rows(tmp_path):
    v = [0.0] * N_FEATURES
    rows = [
        {"label": "openPalm", "vector": v, "reliable": True, "known": True, "augmented": False, "split": "train", "user_id": "a"},
        {"label": "fist", "vector": v, "reliable": False, "known": True, "augmented": False, "split": "train", "user_id": "a"},
        {"label": "two", "vector": v, "reliable": True, "known": False, "augmented": False, "split": "train", "user_id": "a"},
        {"label": "ok", "vector": v, "reliable": True, "known": True, "augmented": True, "split": "train", "user_id": "a"},
    ]
    path = tmp_path / "f.jsonl"
    path.write_text("\n".join(json.dumps(r) for r in rows))
    return path


def test_load_filters_gated_rows(tmp_path):
    X, y, meta = load(write_rows(tmp_path), gate="known")
    assert X.shape == (1, N_FEATURES) and list(y) == [CLASSES.index("openPalm")] and len(meta) == 1


def test_reliable_gate_keeps_unknown_fingers(tmp_path):
    _, y, _ = load(write_rows(tmp_path), gate="reliable")
    assert sorted(y) == sorted([CLASSES.index("openPalm"), CLASSES.index("two")])


def test_augmented_rows_only_when_asked(tmp_path):
    _, y, meta = load(write_rows(tmp_path), gate="known", augmented=True)
    assert CLASSES.index("ok") in y and any(m["augmented"] for m in meta)


def test_normalize_floors_tiny_std():
    norm = Normalize(np.zeros(2, "f"), np.array([1e-9, 1.0], "f"))
    assert float(norm(torch.tensor([[1e-7, 1.0]]))[0, 0]) < 1e-3  # float noise stays noise


def test_class_weight_power_softens_weighting():
    y = np.array([0] * 90 + [1] * 10)
    assert abs(float(class_weights(y, 2, power=0.5)[1] / class_weights(y, 2, power=0.5)[0]) - 3) < 1e-5
    assert np.allclose(class_weights(y, 2, power=0.0), 1)


def test_hagrid_metrics_exclude_local_rows(tmp_path):
    from train import Split
    v = [0.0] * N_FEATURES
    rows = [
        {"label": "openPalm", "vector": v, "reliable": True, "known": True, "augmented": False, "split": "test", "user_id": "u1"},
        {"label": "pinch", "vector": v, "reliable": True, "known": True, "augmented": False, "split": "test", "user_id": "local-user"},
    ]
    path = tmp_path / "f.jsonl"
    path.write_text("\n".join(json.dumps(r) for r in rows))
    assert [CLASSES[i] for i in Split([path], "test", "reliable", False, group="hagrid").y] == ["openPalm"]
    assert [CLASSES[i] for i in Split([path], "test", "reliable", False, group="local").y] == ["pinch"]
    assert "pinch" in CLASSES


def test_local_weight_repeats_local_rows():
    from train import weighted
    X = np.arange(6, dtype="f").reshape(3, 2)
    y = np.array([0, 1, 2])
    meta = [{"user_id": "u1"}, {"user_id": "local-user"}, {"user_id": "u2"}]
    Xw, yw = weighted(X, y, meta, local_weight=3)
    assert list(yw).count(1) == 3 and list(yw).count(0) == 1 and len(Xw) == 5
