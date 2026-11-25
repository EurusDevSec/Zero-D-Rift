"""``submit``: send one message per run attempt (SPEC-P6 P6-T2.1).

Order, and why:

1. ``ListObjectsV2`` on exactly ``<prefix>submitted``. The submit role may list
   only keys matching ``runs/*/submitted`` and has no ``s3:GetObject``, so it
   never sees tenant object names. Present → exit 0 without sending. A failed
   read → ``READ_FAILED``, exit 2, nothing sent (never "absent").
2. ``submit-started`` with ``If-None-Match: *``. A 412 keeps the first value, so
   a retry never moves the freshness mark that B04 compares against.
3. Send ``{requestId, tenant, runAttempt, steps}``.
4. Write ``submitted``.

A crash between 3 and 4 can send the same run key twice; ``train`` makes the
second delivery harmless (``ALREADY_DONE``).
"""

from __future__ import annotations

from .log import emit, error_code
from .runkey import SUBMIT_STARTED, SUBMITTED, RunKey, message_body
from .store import Store

EXIT_OK = 0
EXIT_READ_FAILED = 2
EXIT_WRITE_FAILED = 1


def run(key: RunKey, steps: int, store: Store, sqs, queue_url: str) -> int:
    marker = key.key(SUBMITTED)
    try:
        present = store.exists(marker)
    except Exception as exc:  # 403, timeout, endpoint: unknown is not absent
        emit("READ_FAILED", run_key=str(key), op="ListObjectsV2", code=error_code(exc))
        return EXIT_READ_FAILED
    if present:
        emit("ALREADY_SUBMITTED", run_key=str(key))
        return EXIT_OK

    try:
        first = store.create_if_absent(key.key(SUBMIT_STARTED), {"run_key": str(key)})
    except Exception as exc:
        emit("WRITE_FAILED", run_key=str(key), op="PutObject", marker=SUBMIT_STARTED, code=error_code(exc))
        return EXIT_WRITE_FAILED
    emit("SUBMIT_STARTED", run_key=str(key), first_write=first)

    try:
        sqs.send_message(QueueUrl=queue_url, MessageBody=message_body(key, steps))
    except Exception as exc:
        emit("SEND_FAILED", run_key=str(key), code=error_code(exc))
        return EXIT_WRITE_FAILED

    try:
        store.marker(marker, run_key=str(key), steps=steps)
    except Exception as exc:
        # The message is sent; a retry may send a duplicate, which train absorbs.
        emit("WRITE_FAILED", run_key=str(key), op="PutObject", marker=SUBMITTED, code=error_code(exc))
        return EXIT_WRITE_FAILED
    emit("SUBMITTED", run_key=str(key), steps=steps)
    return EXIT_OK
