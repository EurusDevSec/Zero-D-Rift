from __future__ import annotations

import pytest

from batchtraining.runkey import RunKey
from batchtraining.store import Store
from batchtraining.train import TrainConfig

from fakes import FakeS3, FakeSQS

BUCKET = "zero-drift-batch-tenant-a-demo"
QUEUE = "https://sqs.example.invalid/queue/zero-drift-batch"


class StopAfter:
    """Stands in for the SIGTERM event: ``wait`` reports a signal after n steps."""

    def __init__(self, n: int) -> None:
        self.n, self.calls = n, 0

    def is_set(self) -> bool:
        return self.calls >= self.n

    def wait(self, _seconds: float) -> bool:
        self.calls += 1
        return self.calls >= self.n


@pytest.fixture
def s3():
    return FakeS3()


@pytest.fixture
def sqs():
    return FakeSQS()


@pytest.fixture
def store(s3):
    return Store(s3, BUCKET)


@pytest.fixture
def key():
    return RunKey.of("tenant-a", "demo", 1)


def cfg(**over) -> TrainConfig:
    base = dict(tenant="tenant-a", request_id="demo", queue_url=QUEUE, step_seconds=0.0,
                heartbeat_seconds=40.0, receive_wait_seconds=0, receive_rounds=1)
    base.update(over)
    return TrainConfig(**base)
