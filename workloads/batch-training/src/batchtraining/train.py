"""``train``: receive one message, train with checkpoints, delete the message.

Contract (SPEC-P6 P6-T2.1), in order:

1. Receive one message. A body that is not this worker's request (tenant,
   request ID, and run attempt when the Job knows it) is released with
   visibility 0 and never deleted (D3, soft isolation). Exit 3.
2. ``RECEIVED-<n>`` with the SQS ``ApproximateReceiveCount`` n, so every
   receive is visible in S3 (B08).
3. Profile ``fail-always`` stops here: release, exit 5 (dead-letter scenario).
4. ``SUCCEEDED`` already present → delete the message, ``MESSAGE_DELETED`` on a
   successful delete, log ``ALREADY_DONE``, exit 0, no training.
5. Heartbeat: extend visibility every ``heartbeat_seconds`` (D8: 40 s / 120 s).
6. Load the newest valid checkpoint of this attempt; ``TRAINING_STARTED``
   (stdout and S3) with ``device=cpu``, run key, Pod and ``spec.nodeName``.
   The downward API cannot expose Node labels, so no capacity or instance type
   is recorded here; the suite reads those from the Node.
7. Train, checkpoint every K steps, write the artifact and ``SUCCEEDED``.
8. Delete the message; only a successful delete writes ``MESSAGE_DELETED`` and
   exits 0. A failed delete exits 6; the next receive ends in ``ALREADY_DONE``.

SIGTERM: checkpoint the last completed step, leave the message, exit 143.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass

import numpy as np

from . import model
from .log import emit, error_code
from .runkey import (
    ARTIFACT,
    CHECKPOINT_DIR,
    MESSAGE_DELETED,
    SUCCEEDED,
    TRAINING_STARTED,
    InvalidRunKey,
    RunKey,
    parse_body,
)
from .store import Store

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_READ_FAILED = 2
EXIT_FOREIGN = 3
EXIT_FAIL_PROFILE = 5
EXIT_DELETE_FAILED = 6
EXIT_SIGTERM = 143

PROFILES = ("normal", "fail-always")


@dataclass(frozen=True)
class TrainConfig:
    tenant: str
    request_id: str
    queue_url: str
    run_attempt: int | None = None
    profile: str = "normal"
    checkpoint_every: int = 25
    step_seconds: float = 1.0
    heartbeat_seconds: float = 40.0
    visibility_timeout: int = 120
    receive_wait_seconds: int = 20
    receive_rounds: int = 3
    pod_name: str = ""
    node_name: str = ""


class _Heartbeat(threading.Thread):
    def __init__(self, sqs, queue_url: str, handle: str, every: float, timeout: int, key: RunKey) -> None:
        super().__init__(name="heartbeat", daemon=True)
        self.sqs, self.queue_url, self.handle = sqs, queue_url, handle
        self.every, self.timeout, self.key = every, timeout, key
        self.done = threading.Event()
        self.beats = 0

    def run(self) -> None:
        while not self.done.wait(self.every):
            try:
                self.sqs.change_message_visibility(
                    QueueUrl=self.queue_url, ReceiptHandle=self.handle, VisibilityTimeout=self.timeout,
                )
                self.beats += 1
            except Exception as exc:  # keep training; the message may come back early
                emit("HEARTBEAT_FAILED", run_key=str(self.key), code=error_code(exc))

    def stop(self) -> None:
        self.done.set()
        if self.is_alive():
            self.join(timeout=5)


def _release(sqs, queue_url: str, handle: str) -> None:
    try:
        sqs.change_message_visibility(QueueUrl=queue_url, ReceiptHandle=handle, VisibilityTimeout=0)
    except Exception as exc:  # the message returns after its visibility timeout anyway
        emit("RELEASE_FAILED", code=error_code(exc))


def _receive(cfg: TrainConfig, sqs):
    for _ in range(cfg.receive_rounds):
        resp = sqs.receive_message(
            QueueUrl=cfg.queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=cfg.receive_wait_seconds,
            AttributeNames=["ApproximateReceiveCount"],
            MessageSystemAttributeNames=["ApproximateReceiveCount"],
        )
        messages = resp.get("Messages", [])
        if messages:
            return messages[0]
    return None


def _newest_checkpoint(store: Store, key: RunKey) -> tuple[int, np.ndarray] | None:
    """Newest valid checkpoint of this attempt only. Listing errors raise."""
    for ckpt in sorted(store.list_keys(key.prefix + CHECKPOINT_DIR), reverse=True):
        try:
            data = store.get_json(ckpt)
        except ValueError:  # unreadable JSON: fall back to an older checkpoint
            data = None
        if not isinstance(data, dict):
            continue
        step, weights = data.get("step"), data.get("weights")
        if isinstance(step, int) and step > 0 and isinstance(weights, list) \
                and len(weights) == model.FEATURES + 1:
            return step, np.asarray(weights, dtype=np.float64)
        emit("CHECKPOINT_SKIPPED", run_key=str(key), key=ckpt)
    return None


def _checkpoint(store: Store, key: RunKey, step: int, w: np.ndarray) -> None:
    store.put_json(key.checkpoint(step), {"step": step, "weights": w.tolist(), "run_key": str(key)})


def run(cfg: TrainConfig, store: Store, sqs, stop: threading.Event | None = None) -> int:
    stop = stop or threading.Event()
    try:
        msg = _receive(cfg, sqs)
    except Exception as exc:
        emit("READ_FAILED", op="ReceiveMessage", code=error_code(exc))
        return EXIT_READ_FAILED
    if msg is None:
        emit("NO_MESSAGE", tenant=cfg.tenant, requestId=cfg.request_id)
        return EXIT_OK
    handle = msg["ReceiptHandle"]

    try:
        key, steps = parse_body(msg.get("Body", ""))
    except InvalidRunKey as exc:
        _release(sqs, cfg.queue_url, handle)
        emit("MALFORMED_RELEASED", reason=str(exc))
        return EXIT_FOREIGN
    if key.tenant != cfg.tenant or key.request_id != cfg.request_id or (
        cfg.run_attempt is not None and key.run_attempt != cfg.run_attempt
    ):
        _release(sqs, cfg.queue_url, handle)
        emit("FOREIGN_RELEASED", own=f"{cfg.tenant}/{cfg.request_id}", message_run_key=str(key))
        return EXIT_FOREIGN

    attrs = msg.get("Attributes", {})
    count = int(attrs.get("ApproximateReceiveCount", "0") or 0)
    try:
        store.marker(key.received(count), run_key=str(key), pod=cfg.pod_name)
    except Exception as exc:
        emit("WRITE_FAILED", run_key=str(key), marker=f"RECEIVED-{count}", code=error_code(exc))
        return EXIT_FAILED
    emit("RECEIVED", run_key=str(key), receive_count=count)

    if cfg.profile == "fail-always":
        _release(sqs, cfg.queue_url, handle)
        emit("FAIL_PROFILE", run_key=str(key), receive_count=count)
        return EXIT_FAIL_PROFILE

    try:
        done = store.exists(key.key(SUCCEEDED))
    except Exception as exc:
        emit("READ_FAILED", run_key=str(key), op="ListObjectsV2", code=error_code(exc))
        return EXIT_READ_FAILED
    if done:
        emit("ALREADY_DONE", run_key=str(key))
        return _delete(cfg, store, sqs, key, handle)

    beat = _Heartbeat(sqs, cfg.queue_url, handle, cfg.heartbeat_seconds, cfg.visibility_timeout, key)
    beat.start()
    try:
        return _train(cfg, store, sqs, key, steps, handle, beat, stop)
    except Exception as exc:  # the message stays and comes back after the timeout
        emit("FAILED", run_key=str(key), code=error_code(exc))
        return EXIT_FAILED
    finally:
        beat.stop()


def _train(cfg, store, sqs, key, steps, handle, beat, stop) -> int:
    try:
        found = _newest_checkpoint(store, key)
    except Exception as exc:  # unknown checkpoint state is not "start from 0"
        emit("READ_FAILED", run_key=str(key), op="ListObjectsV2", code=error_code(exc))
        return EXIT_READ_FAILED
    start, w = found if found else (0, model.initial_weights())
    x, y = model.dataset(key.request_id)

    started = {
        "device": "cpu", "run_key": str(key), "pod": cfg.pod_name, "node": cfg.node_name,
        "resumed_from": start, "steps": steps,
    }
    store.marker(key.key(TRAINING_STARTED), **started)
    emit(TRAINING_STARTED, **started)
    if start:
        emit("RESUMED", run_key=str(key), message=f"resumed from step {start}")

    for s in range(start + 1, steps + 1):
        if stop.is_set():
            return _on_sigterm(store, key, s - 1, start, w)
        w = model.step(w, x, y)
        if s % cfg.checkpoint_every == 0 and s < steps:
            _checkpoint(store, key, s, w)
            emit("CHECKPOINT", run_key=str(key), step=s)
        if cfg.step_seconds and stop.wait(cfg.step_seconds):
            return _on_sigterm(store, key, s, start, w)

    result = model.metrics(w, x, y)
    store.put_json(key.key(ARTIFACT), {"run_key": str(key), "steps": steps, "weights": w.tolist(), **result})
    store.marker(key.key(SUCCEEDED), run_key=str(key), steps=steps, **result)
    emit(SUCCEEDED, run_key=str(key), steps=steps, **result)
    beat.stop()
    return _delete(cfg, store, sqs, key, handle)


def _on_sigterm(store: Store, key: RunKey, completed: int, start: int, w: np.ndarray) -> int:
    if completed > start:
        _checkpoint(store, key, completed, w)
    emit("SIGTERM_CHECKPOINT", run_key=str(key), step=completed)
    return EXIT_SIGTERM


def _delete(cfg: TrainConfig, store: Store, sqs, key: RunKey, handle: str) -> int:
    try:
        sqs.delete_message(QueueUrl=cfg.queue_url, ReceiptHandle=handle)
    except Exception as exc:
        emit("DELETE_FAILED", run_key=str(key), code=error_code(exc))
        return EXIT_DELETE_FAILED
    try:
        store.marker(key.key(MESSAGE_DELETED), run_key=str(key))
    except Exception as exc:
        emit("WRITE_FAILED", run_key=str(key), marker=MESSAGE_DELETED, code=error_code(exc))
        return EXIT_FAILED
    emit(MESSAGE_DELETED, run_key=str(key))
    return EXIT_OK
