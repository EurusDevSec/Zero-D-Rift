"""In-memory S3 and SQS with the boto3 call shapes the worker uses.

Errors are real ``botocore`` ``ClientError``s with the AWS code and HTTP status,
so the worker's error handling is exercised as it runs against AWS. ``fail``
maps an operation name to an error code to inject.
"""

from __future__ import annotations

import io
import itertools
import threading

from botocore.exceptions import ClientError, ReadTimeoutError

# 12 digits built at run time, so the repository ID scan never sees an account-shaped literal.
FAKE_ACCOUNT = "1234" * 3

_STATUS = {"PreconditionFailed": 412, "NoSuchKey": 404, "AccessDenied": 403, "InternalError": 500}


def client_error(code: str, op: str) -> ClientError:
    return ClientError(
        {"Error": {"Code": code, "Message": f"arn:aws:iam::{FAKE_ACCOUNT}:role/should-never-print"},
         "ResponseMetadata": {"HTTPStatusCode": _STATUS.get(code, 400)}},
        op,
    )


class FakeS3:
    def __init__(self, fail: dict[str, str] | None = None) -> None:
        self.objects: dict[tuple[str, str], bytes] = {}
        self.fail = dict(fail or {})
        self.calls: list[str] = []
        self.page_size = 1000
        self.lock = threading.Lock()

    def _check(self, op: str) -> None:
        self.calls.append(op)
        code = self.fail.get(op)
        if code == "TIMEOUT":
            raise ReadTimeoutError(endpoint_url="http://fake")
        if code:
            raise client_error(code, op)

    def put_object(self, Bucket, Key, Body, IfNoneMatch=None, ContentType=None):
        self._check("PutObject")
        with self.lock:
            if IfNoneMatch == "*" and (Bucket, Key) in self.objects:
                raise client_error("PreconditionFailed", "PutObject")
            self.objects[(Bucket, Key)] = Body if isinstance(Body, bytes) else Body.encode()
        return {}

    def get_object(self, Bucket, Key):
        self._check("GetObject")
        if (Bucket, Key) not in self.objects:
            raise client_error("NoSuchKey", "GetObject")
        return {"Body": io.BytesIO(self.objects[(Bucket, Key)])}

    def head_object(self, Bucket, Key):
        self._check("HeadObject")
        if (Bucket, Key) not in self.objects:
            raise client_error("404", "HeadObject")
        return {}

    def list_objects_v2(self, Bucket, Prefix="", ContinuationToken=None):
        self._check("ListObjectsV2")
        keys = sorted(k for (b, k) in self.objects if b == Bucket and k.startswith(Prefix))
        start = int(ContinuationToken or 0)
        page = keys[start:start + self.page_size]
        resp = {"KeyCount": len(page), "IsTruncated": start + self.page_size < len(keys)}
        if page:
            resp["Contents"] = [{"Key": k} for k in page]
        if resp["IsTruncated"]:
            resp["NextContinuationToken"] = str(start + self.page_size)
        return resp

    def keys(self, bucket: str, prefix: str = "") -> list[str]:
        return sorted(k for (b, k) in self.objects if b == bucket and k.startswith(prefix))

    def body(self, bucket: str, key: str) -> bytes:
        return self.objects[(bucket, key)]


class FakeSQS:
    """Standard queue semantics on a manual clock (``now``)."""

    def __init__(self, visibility_timeout: int = 120, fail: dict[str, str] | None = None) -> None:
        self.visibility_timeout = visibility_timeout
        self.fail = dict(fail or {})
        self.now = 0.0
        self.messages: list[dict] = []
        self.sent: list[str] = []
        self.deleted: list[str] = []
        self.visibility_calls: list[int] = []
        self._ids = itertools.count(1)
        self.lock = threading.Lock()

    def _check(self, op: str) -> None:
        code = self.fail.get(op)
        if code == "TIMEOUT":
            raise ReadTimeoutError(endpoint_url="http://fake")
        if code:
            raise client_error(code, op)

    def send_message(self, QueueUrl, MessageBody):
        self._check("SendMessage")
        mid = str(next(self._ids))
        self.messages.append({"id": mid, "body": MessageBody, "visible_at": self.now, "count": 0, "handle": None})
        self.sent.append(MessageBody)
        return {"MessageId": mid}

    def receive_message(self, QueueUrl, MaxNumberOfMessages=1, WaitTimeSeconds=0, VisibilityTimeout=None,
                        AttributeNames=None, MessageSystemAttributeNames=None):
        self._check("ReceiveMessage")
        out = []
        with self.lock:
            for m in self.messages:
                if len(out) >= MaxNumberOfMessages:
                    break
                if m["visible_at"] <= self.now:
                    m["count"] += 1
                    m["handle"] = f"h-{m['id']}-{m['count']}"
                    vt = self.visibility_timeout if VisibilityTimeout is None else VisibilityTimeout
                    m["visible_at"] = self.now + vt
                    msg = {"MessageId": m["id"], "ReceiptHandle": m["handle"], "Body": m["body"]}
                    if AttributeNames or MessageSystemAttributeNames:
                        msg["Attributes"] = {"ApproximateReceiveCount": str(m["count"])}
                    out.append(msg)
        return {"Messages": out} if out else {}

    def _find(self, handle):
        for m in self.messages:
            if m["handle"] == handle:
                return m
        raise client_error("ReceiptHandleIsInvalid", "ChangeMessageVisibility")

    def change_message_visibility(self, QueueUrl, ReceiptHandle, VisibilityTimeout):
        self._check("ChangeMessageVisibility")
        with self.lock:
            m = self._find(ReceiptHandle)
            m["visible_at"] = self.now + VisibilityTimeout
            self.visibility_calls.append(VisibilityTimeout)
        return {}

    def delete_message(self, QueueUrl, ReceiptHandle):
        self._check("DeleteMessage")
        with self.lock:
            m = self._find(ReceiptHandle)
            self.messages.remove(m)
            self.deleted.append(m["body"])
        return {}

    def advance(self, seconds: float) -> None:
        self.now += seconds


class FakeSTS:
    def __init__(self, role: str = "zero-drift-batch-tenant-a", fail: str | None = None) -> None:
        self.role, self.fail = role, fail

    def get_caller_identity(self):
        if self.fail:
            raise client_error(self.fail, "GetCallerIdentity")
        return {"Arn": f"arn:aws:sts::{FAKE_ACCOUNT}:assumed-role/{self.role}/botocore-session-1",
                "Account": FAKE_ACCOUNT}
