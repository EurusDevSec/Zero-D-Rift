"""Synthetic workload (D10): NumPy logistic regression, no dataset, no licence.

The data comes from a seed derived from the request ID, so a resumed run sees
the same data and reaches the same weights as an uninterrupted run.
"""

from __future__ import annotations

import hashlib

import numpy as np

FEATURES = 8
SAMPLES = 512
LEARNING_RATE = 0.1


def _seed(request_id: str) -> int:
    return int.from_bytes(hashlib.sha256(request_id.encode()).digest()[:4], "big")


def dataset(request_id: str) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(_seed(request_id))
    x = rng.normal(size=(SAMPLES, FEATURES))
    true_w = rng.normal(size=FEATURES)
    y = (x @ true_w + 0.1 * rng.normal(size=SAMPLES) > 0).astype(np.float64)
    return x, y


def initial_weights() -> np.ndarray:
    return np.zeros(FEATURES + 1)  # last entry is the bias


def _predict(w: np.ndarray, x: np.ndarray) -> np.ndarray:
    z = x @ w[:-1] + w[-1]
    return 1.0 / (1.0 + np.exp(-np.clip(z, -30, 30)))


def step(w: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    p = _predict(w, x)
    err = p - y
    grad = np.append(x.T @ err / len(y), err.mean())
    return w - LEARNING_RATE * grad


def metrics(w: np.ndarray, x: np.ndarray, y: np.ndarray) -> dict:
    p = np.clip(_predict(w, x), 1e-12, 1 - 1e-12)
    loss = float(-(y * np.log(p) + (1 - y) * np.log(1 - p)).mean())
    accuracy = float(((p > 0.5) == (y > 0.5)).mean())
    return {"loss": round(loss, 6), "accuracy": round(accuracy, 6)}
