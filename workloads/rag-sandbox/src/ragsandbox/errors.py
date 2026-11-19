"""Error text that is safe to return over HTTP or write to a log.

Messages from the AWS SDK and from libpq can carry identifiers that must not
leave the process: an ``AccessDenied`` names the caller's role ARN (and so the
account ID), and a connection error names the database host and its address.
For those libraries only the exception class and a code (AWS error code,
SQLSTATE) or a fixed label are kept. Messages of this package's own exceptions
are kept, because they are written here and hold no secret.
"""

from __future__ import annotations

_DEPENDENCIES = ("psycopg", "botocore", "boto3", "s3transfer", "urllib3")

# Connection failures from libpq have no SQLSTATE. A fixed label per known
# cause; the raw message is never copied.
_LIBPQ_LABELS = (
    ("password authentication failed", "authentication failed"),
    ("no pg_hba.conf entry", "rejected by pg_hba.conf"),
    ("resolve host", "host not resolved"),
    ("translate host name", "host not resolved"),
    ("connection refused", "connection refused"),
    ("timeout expired", "timeout"),
    ("timed out", "timeout"),
    ("server closed the connection", "connection lost"),
    ("certificate", "tls certificate error"),
    ("ssl", "tls error"),
    ("does not exist", "database or role does not exist"),
)


def aws_error_code(exc: BaseException) -> str | None:
    response = getattr(exc, "response", None) or {}
    return (response.get("Error") or {}).get("Code")


def _from_dependency(exc: BaseException) -> bool:
    return type(exc).__module__.split(".")[0] in _DEPENDENCIES


def safe_reason(exc: BaseException) -> str:
    name = type(exc).__name__
    code = aws_error_code(exc)
    if code:
        return f"{name}: {code}"
    if _from_dependency(exc):
        sqlstate = getattr(exc, "sqlstate", None)
        if sqlstate:
            return f"{name}: SQLSTATE {sqlstate}"
        text = str(exc).lower()
        for needle, label in _LIBPQ_LABELS:
            if needle in text:
                return f"{name}: {label}"
        return name
    first = (str(exc).strip().splitlines() or [""])[0]
    return f"{name}: {first[:200]}" if first else name
