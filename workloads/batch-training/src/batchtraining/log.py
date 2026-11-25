"""One JSON line per event on stdout, and error reasons without identifiers.

AWS error messages can carry an ARN or an account ID (an ``AccessDenied``
message names the caller). Only the exception class and the AWS error code are
ever printed (SPEC-P6 boundary 10).
"""

from __future__ import annotations

import json
import sys
import time

from botocore.exceptions import (
    BotoCoreError,
    ClientError,
    ConnectTimeoutError,
    EndpointConnectionError,
    ReadTimeoutError,
)


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def emit(event: str, **fields: object) -> None:
    line = {"event": event, "ts": now(), **fields}
    sys.stdout.write(json.dumps(line, sort_keys=True) + "\n")
    sys.stdout.flush()


def error_code(exc: BaseException) -> str:
    """The AWS error code, or a fixed word for transport failures."""
    if isinstance(exc, ClientError):
        return str(exc.response.get("Error", {}).get("Code") or "ClientError")
    if isinstance(exc, (ConnectTimeoutError, ReadTimeoutError)):
        return "TIMEOUT"
    if isinstance(exc, EndpointConnectionError):
        return "ENDPOINT_ERROR"
    if isinstance(exc, BotoCoreError):
        return type(exc).__name__
    return type(exc).__name__


def http_status(exc: BaseException) -> int | None:
    if isinstance(exc, ClientError):
        status = exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
        return int(status) if status is not None else None
    return None
