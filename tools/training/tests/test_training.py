import json

import numpy as np
import torch

from data import CLASSES, class_weights, load
from model import PoseMLP, export_coreml


def test_class_weights_inverse_to_frequency():
    y = np.array([0] * 90 + [1] * 10)
    w = class_weights(y, n_classes=2)
    assert abs(float(w[1] / w[0]) - 9) < 1e-5
    assert abs(float(w.mean()) - 1) < 1e-6


def test_folded_model_matches_standardized_model():
    torch.manual_seed(0)
    mean, std = np.random.rand(52).astype("f"), (np.random.rand(52) + 0.5).astype("f")
    folded = PoseMLP(mean, std, len(CLASSES)).eval()
    plain = PoseMLP(np.zeros(52, "f"), np.ones(52, "f"), len(CLASSES)).eval()
    plain.load_state_dict({k: v for k, v in folded.state_dict().items() if not k.startswith("norm.")}, strict=False)
    x = torch.rand(8, 52)
    expected = plain((x - torch.from_numpy(mean)) / torch.from_numpy(std))
    assert torch.allclose(folded(x), expected, atol=1e-5)


def test_coreml_matches_torch(tmp_path):
    torch.manual_seed(1)
    model = PoseMLP(np.zeros(52, "f"), np.ones(52, "f"), len(CLASSES)).eval()
    path = tmp_path / "m.mlpackage"
    mlmodel = export_coreml(model, path, CLASSES)
    x = np.random.rand(5, 52).astype("f")
    torch_probs = torch.softmax(model(torch.from_numpy(x)), dim=1).detach().numpy()
    for i in range(5):
        out = mlmodel.predict({"features": x[i:i + 1]})
        probs = out["classLabel_probs"]
        assert np.allclose([probs[c] for c in CLASSES], torch_probs[i], atol=1e-4)


def test_load_filters_gated_rows(tmp_path):
    rows = [
        {"label": "openPalm", "vector": [0.0] * 52, "reliable": True, "known": True, "split": "train", "user_id": "a"},
        {"label": "fist", "vector": [0.0] * 52, "reliable": False, "known": True, "split": "train", "user_id": "a"},
        {"label": "two", "vector": [0.0] * 52, "reliable": True, "known": False, "split": "train", "user_id": "a"},
    ]
    path = tmp_path / "f.jsonl"
    path.write_text("\n".join(json.dumps(r) for r in rows))
    X, y, meta = load(path)
    assert X.shape == (1, 52) and list(y) == [CLASSES.index("openPalm")] and len(meta) == 1


def test_class_weight_power_softens_weighting():
    y = np.array([0] * 90 + [1] * 10)
    assert abs(float(class_weights(y, 2, power=0.5)[1] / class_weights(y, 2, power=0.5)[0]) - 3) < 1e-5
    assert np.allclose(class_weights(y, 2, power=0.0), 1)
