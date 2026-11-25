"""The run key ``tenant/requestId/runAttempt`` and the S3 keys of one attempt.

Every marker, checkpoint and the artifact of an attempt sit under
``runs/<requestId>/<runAttempt>/`` (SPEC-P6 P6-T2.1). Names are checked before
use, so a message body can never steer a key outside that prefix.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass

_NAME = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")
MAX_ATTEMPT = 9999
MAX_STEPS = 1000

SUBMIT_STARTED = "submit-started"
SUBMITTED = "submitted"
TRAINING_STARTED = "TRAINING_STARTED"
SUCCEEDED = "SUCCEEDED"
MESSAGE_DELETED = "MESSAGE_DELETED"
CHECKPOINT_DIR = "ckpt/"
ARTIFACT = "artifact/model.json"


class InvalidRunKey(ValueError):
    """A tenant, request ID, run attempt or step count is out of contract."""


def _name(field: str, value: object) -> str:
    if not isinstance(value, str) or not _NAME.match(value):
        raise InvalidRunKey(f"{field} must be a DNS label (a-z, 0-9, '-', max 63)")
    return value


def _attempt(value: object) -> int:
    if isinstance(value, bool):
        raise InvalidRunKey("runAttempt must be an integer 1..9999")
    try:
        n = int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        raise InvalidRunKey("runAttempt must be an integer 1..9999") from None
    if str(n) != str(value).strip() or not 1 <= n <= MAX_ATTEMPT:
        raise InvalidRunKey("runAttempt must be an integer 1..9999")
    return n


def parse_steps(value: object) -> int:
    if isinstance(value, bool):
        raise InvalidRunKey(f"steps must be an integer 1..{MAX_STEPS}")
    try:
        n = int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        raise InvalidRunKey(f"steps must be an integer 1..{MAX_STEPS}") from None
    if str(n) != str(value).strip() or not 1 <= n <= MAX_STEPS:
        raise InvalidRunKey(f"steps must be an integer 1..{MAX_STEPS}")
    return n


@dataclass(frozen=True)
class RunKey:
    tenant: str
    request_id: str
    run_attempt: int

    @classmethod
    def of(cls, tenant: object, request_id: object, run_attempt: object) -> "RunKey":
        return cls(_name("tenant", tenant), _name("requestId", request_id), _attempt(run_attempt))

    @property
    def prefix(self) -> str:
        return f"runs/{self.request_id}/{self.run_attempt}/"

    def key(self, name: str) -> str:
        return self.prefix + name

    def received(self, n: int) -> str:
        return self.key(f"RECEIVED-{n}")

    def checkpoint(self, step: int) -> str:
        return self.key(f"{CHECKPOINT_DIR}step-{step:06d}.json")

    def __str__(self) -> str:
        return f"{self.tenant}/{self.request_id}/{self.run_attempt}"


def message_body(key: RunKey, steps: int) -> str:
    """Identifiers only (D3): no tenant data in a message."""
    return json.dumps(
        {"requestId": key.request_id, "tenant": key.tenant, "runAttempt": key.run_attempt, "steps": steps},
        sort_keys=True,
    )


def parse_body(body: str) -> tuple[RunKey, int]:
    try:
        data = json.loads(body)
    except (TypeError, ValueError):
        raise InvalidRunKey("message body is not JSON") from None
    if not isinstance(data, dict):
        raise InvalidRunKey("message body is not an object")
    key = RunKey.of(data.get("tenant"), data.get("requestId"), data.get("runAttempt"))
    return key, parse_steps(data.get("steps"))
