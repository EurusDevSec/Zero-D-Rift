"""S3 operations on one bucket: markers, conditional create, listing.

Read failures are never turned into "absent": a caller that needs to know
whether an object exists gets an exception, not ``False``.
"""

from __future__ import annotations

import json

from botocore.exceptions import ClientError

from .log import now

_NOT_FOUND = {"NoSuchKey", "404", "NotFound"}
_PRECONDITION = {"PreconditionFailed", "412"}


class Store:
    def __init__(self, s3, bucket: str) -> None:
        self.s3 = s3
        self.bucket = bucket

    def put_json(self, key: str, data: dict) -> None:
        self.s3.put_object(
            Bucket=self.bucket, Key=key, Body=json.dumps(data, sort_keys=True).encode(),
            ContentType="application/json",
        )

    def marker(self, key: str, **fields: object) -> None:
        self.put_json(key, {"ts": now(), **fields})

    def create_if_absent(self, key: str, data: dict) -> bool:
        """Conditional write (``If-None-Match: *``). False when the key exists (412).

        The first value always stays; any other error is raised.
        """
        body = {"ts": now(), **data}
        try:
            self.s3.put_object(
                Bucket=self.bucket, Key=key, Body=json.dumps(body, sort_keys=True).encode(),
                ContentType="application/json", IfNoneMatch="*",
            )
            return True
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") in _PRECONDITION:
                return False
            raise

    def get_json(self, key: str) -> dict | None:
        """The object as JSON, or None when it does not exist. Other errors raise."""
        try:
            body = self.s3.get_object(Bucket=self.bucket, Key=key)["Body"].read()
        except ClientError as exc:
            if exc.response.get("Error", {}).get("Code") in _NOT_FOUND:
                return None
            raise
        return json.loads(body)

    def list_keys(self, prefix: str) -> list[str]:
        keys: list[str] = []
        kwargs = {"Bucket": self.bucket, "Prefix": prefix}
        while True:
            page = self.s3.list_objects_v2(**kwargs)
            keys.extend(item["Key"] for item in page.get("Contents", []))
            token = page.get("NextContinuationToken")
            if not page.get("IsTruncated") or not token:
                return keys
            kwargs["ContinuationToken"] = token

    def exists(self, key: str) -> bool:
        """Exact-key check by listing that key as a prefix (no ``s3:GetObject`` needed)."""
        return key in self.list_keys(key)
