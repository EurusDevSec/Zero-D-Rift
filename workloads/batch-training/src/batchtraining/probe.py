"""``probe``: one S3 or IMDS call that prints only the outcome (B12, B14).

Before any S3 call it runs STS ``GetCallerIdentity`` and prints only
``caller_role_match=true|false`` against the expected role name; it never
prints the ARN or the account. A mismatch stops before the S3 call (exit 4),
so an ``AccessDenied`` can never come from the wrong role (SPEC-P6 R4).

Output is ``key=value`` lines; exit 0 means the call ran and its outcome was
printed, whatever that outcome was.
"""

from __future__ import annotations

import sys
import urllib.error
import urllib.request

from .log import error_code

EXIT_OK = 0
EXIT_CALLER_UNKNOWN = 2
EXIT_CALLER_MISMATCH = 4
S3_ACTIONS = ("s3-head", "s3-get", "s3-put")
IMDS_TOKEN_URL = "http://169.254.169.254/latest/api/token"


def _out(**fields: object) -> None:
    for k, v in fields.items():
        sys.stdout.write(f"{k}={v}\n")
    sys.stdout.flush()


def role_name_from_arn(arn: str) -> str:
    """``arn:aws:sts::<acct>:assumed-role/<role>/<session>`` → ``<role>``."""
    resource = arn.split(":", 5)[-1] if arn.count(":") >= 5 else ""
    parts = resource.split("/")
    if len(parts) >= 2 and parts[0] == "assumed-role":
        return parts[1]
    return ""


def caller_matches(sts, expected_role: str) -> bool:
    arn = sts.get_caller_identity()["Arn"]
    return role_name_from_arn(arn) == expected_role


def s3(action: str, sts, s3_client, expected_role: str, bucket: str, key: str) -> int:
    try:
        match = caller_matches(sts, expected_role)
    except Exception as exc:
        _out(caller_role_match="READ_FAILED", code=error_code(exc))
        return EXIT_CALLER_UNKNOWN
    _out(caller_role_match=str(match).lower())
    if not match:
        return EXIT_CALLER_MISMATCH
    try:
        if action == "s3-head":
            s3_client.head_object(Bucket=bucket, Key=key)
        elif action == "s3-get":
            s3_client.get_object(Bucket=bucket, Key=key)["Body"].read()
        else:
            s3_client.put_object(Bucket=bucket, Key=key, Body=b"probe")
        _out(action=action, outcome="ok")
    except Exception as exc:
        _out(action=action, outcome="error", code=error_code(exc))
    return EXIT_OK


def s3_conditional(s3_client, bucket: str, prefix: str) -> int:
    """§9.3 L2: a second ``If-None-Match: *`` write returns 412 and the first value stays.

    Uses a fresh key under ``prefix`` so the first write is a real create.
    Prints ``conditional_write=PASS`` only when all three facts hold.
    """
    import uuid

    from botocore.exceptions import ClientError

    key = f"{prefix.rstrip('/')}/conditional-{uuid.uuid4().hex}"
    first_body = f"first-{uuid.uuid4().hex}".encode()
    try:
        s3_client.put_object(Bucket=bucket, Key=key, Body=first_body, IfNoneMatch="*")
        first = "created"
    except Exception as exc:
        _out(conditional_first="error", code=error_code(exc), conditional_write="FAIL")
        return EXIT_OK
    try:
        s3_client.put_object(Bucket=bucket, Key=key, Body=b"second", IfNoneMatch="*")
        second = "overwritten"
    except ClientError as exc:
        status = exc.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
        second = f"{status}:{error_code(exc)}"
    except Exception as exc:
        second = f"error:{error_code(exc)}"
    try:
        kept = s3_client.get_object(Bucket=bucket, Key=key)["Body"].read() == first_body
        kept_txt = str(kept).lower()
    except Exception as exc:
        kept, kept_txt = False, f"READ_FAILED:{error_code(exc)}"
    ok = first == "created" and second == "412:PreconditionFailed" and kept
    _out(conditional_first=first, conditional_second=second, first_value_kept=kept_txt,
         conditional_write="PASS" if ok else "FAIL")
    return EXIT_OK


def imds(opener=urllib.request.urlopen, timeout: float = 2.0) -> int:
    """IMDSv2 token call. The token itself is never printed."""
    req = urllib.request.Request(
        IMDS_TOKEN_URL, method="PUT", headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
    )
    try:
        with opener(req, timeout=timeout) as resp:
            got = bool(resp.read())
        _out(action="imds-token", outcome="obtained" if got else "empty")
    except urllib.error.HTTPError as exc:
        _out(action="imds-token", outcome="denied", code=f"HTTP{exc.code}")
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        _out(action="imds-token", outcome="denied", code=type(getattr(exc, "reason", exc)).__name__)
    return EXIT_OK
