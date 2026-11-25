"""``cleanup``: delete leftover messages of one request (SPEC-P6 §9.5 step 1).

Receives in batches and filters: a message of this tenant and request ID (any
run attempt) is deleted; any other message is released with visibility 0.
Receiving another request's message still counts toward its
``maxReceiveCount`` (D3), so cleanup runs only after that request is disabled.

Finished Jobs of the request are Kubernetes objects; the operator deletes them
with ``kubectl`` (window runbook), so this image needs no Kubernetes API right.
"""

from __future__ import annotations

from .log import emit, error_code
from .runkey import InvalidRunKey, parse_body

EXIT_OK = 0
EXIT_READ_FAILED = 2
EXIT_PARTIAL = 1


def run(tenant: str, request_id: str, sqs, queue_url: str, max_rounds: int = 20,
        wait_seconds: int = 2, empty_rounds_to_stop: int = 2) -> int:
    deleted = released = failed = 0
    empty = rounds = 0
    while rounds < max_rounds and empty < empty_rounds_to_stop:
        rounds += 1
        try:
            resp = sqs.receive_message(
                QueueUrl=queue_url, MaxNumberOfMessages=10, WaitTimeSeconds=wait_seconds,
                VisibilityTimeout=30,
            )
        except Exception as exc:
            emit("READ_FAILED", op="ReceiveMessage", code=error_code(exc),
                 deleted=deleted, released=released)
            return EXIT_READ_FAILED
        messages = resp.get("Messages", [])
        if not messages:
            empty += 1
            continue
        empty = 0
        for msg in messages:
            handle = msg["ReceiptHandle"]
            try:
                key, _ = parse_body(msg.get("Body", ""))
                mine = key.tenant == tenant and key.request_id == request_id
            except InvalidRunKey:
                mine = False
            try:
                if mine:
                    sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=handle)
                    deleted += 1
                else:
                    sqs.change_message_visibility(
                        QueueUrl=queue_url, ReceiptHandle=handle, VisibilityTimeout=0,
                    )
                    released += 1
            except Exception as exc:
                failed += 1
                emit("CLEANUP_OP_FAILED", code=error_code(exc))
    complete = empty >= empty_rounds_to_stop and failed == 0
    emit("CLEANUP", tenant=tenant, requestId=request_id, deleted=deleted, released=released,
         failed=failed, rounds=rounds, complete=complete)
    return EXIT_OK if complete else EXIT_PARTIAL
