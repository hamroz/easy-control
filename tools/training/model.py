"""Pose classifier network and Core ML export."""
import pathlib

import coremltools as ct
import numpy as np
import torch
from torch import nn


class Normalize(nn.Module):
    """Standardization baked into the model, so the app feeds raw feature vectors."""

    def __init__(self, mean: np.ndarray, std: np.ndarray):
        super().__init__()
        self.register_buffer("mean", torch.as_tensor(mean, dtype=torch.float32))
        self.register_buffer("std", torch.as_tensor(np.maximum(std, 1e-6), dtype=torch.float32))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return (x - self.mean) / self.std


class PoseMLP(nn.Module):
    def __init__(self, mean: np.ndarray, std: np.ndarray, n_classes: int, dropout: float = 0.2,
                 hidden: tuple[int, int] = (128, 64)):
        super().__init__()
        self.norm = Normalize(mean, std)
        h1, h2 = hidden
        self.net = nn.Sequential(
            nn.Linear(52, h1), nn.ReLU(), nn.Dropout(dropout),
            nn.Linear(h1, h2), nn.ReLU(), nn.Dropout(dropout),
            nn.Linear(h2, n_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """Logits."""
        return self.net(self.norm(x))


class _Probabilities(nn.Module):
    def __init__(self, model: nn.Module):
        super().__init__()
        self.model = model

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return torch.softmax(self.model(x), dim=1)


def export_coreml(model: PoseMLP, path: str | pathlib.Path, class_labels: list[str]) -> "ct.models.MLModel":
    """Writes an ML Program classifier: input `features` (1×52 float32), outputs `classLabel` and
    `classLabel_probs` (label → probability)."""
    wrapped = _Probabilities(model.eval()).eval()
    traced = torch.jit.trace(wrapped, torch.zeros(1, 52))
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="features", shape=(1, 52), dtype=np.float32)],
        outputs=[ct.TensorType(name="probabilities")],
        classifier_config=ct.ClassifierConfig(class_labels),
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS15,
    )
    mlmodel.short_description = "EasyControl hand pose classifier (Apple Vision landmarks → pose)"
    mlmodel.license = "CC BY-SA 4.0 — trained on HaGRID (https://github.com/hukenovs/hagrid)"
    mlmodel.save(str(path))
    return mlmodel
