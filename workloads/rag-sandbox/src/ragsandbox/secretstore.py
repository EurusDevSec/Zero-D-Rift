"""Secret stores (ADR-0008 §3, SPEC-P4 D5).

``aws`` reads and writes AWS Secrets Manager with the SDK, authenticated through
IRSA. It is the only backend allowed outside a lab.

``file`` keeps one JSON file per secret under a directory. It exists only for the
kind labs, which have no AWS (SPEC-P4 P4-T3.2 C: "secret from a lab-only source").

Secret values are dicts. They are never logged or printed.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Callable, Mapping, Protocol

from .errors import aws_error_code as _error_code

_SECRET_NAME_RE = re.compile(r"^[A-Za-z0-9/_+=.@!-]{1,512}$")


class SecretStore(Protocol):
    def get(self, name: str) -> dict | None: ...

    def create(self, name: str, value: dict) -> bool:
        """Create the secret. Return False when it already exists."""

    def delete(self, name: str) -> bool:
        """Delete the secret at once. Return False when it did not exist."""


def get_or_create(
    store: SecretStore, name: str, factory: Callable[[], dict]
) -> tuple[dict, bool]:
    """Return ``(value, created)``. An existing secret is reused, never rotated."""
    current = store.get(name)
    if current is not None:
        return current, False
    value = factory()
    if store.create(name, value):
        return value, True
    # Another run created it between get and create: use the winner's value.
    current = store.get(name)
    if current is None:
        raise RuntimeError(f"secret {name} exists but cannot be read")
    return current, False


def require(store: SecretStore, name: str, label: str | None = None) -> dict:
    """``label`` replaces ``name`` in error messages when the name itself must not
    be printed (the master secret is passed as its ARN; Codex C3)."""
    shown = label or name
    value = store.get(name)
    if value is None:
        raise RuntimeError(f"secret {shown} not found")
    for key in ("username", "password"):
        if not value.get(key):
            raise RuntimeError(f"secret {shown} has no {key}")
    return value


class FileSecretStore:
    """Lab only: ``<root>/<name>.json``, mode 0600, created exclusively."""

    def __init__(self, root: str | os.PathLike[str]):
        self.root = Path(root)

    def _path(self, name: str) -> Path:
        if not _SECRET_NAME_RE.fullmatch(name) or any(
            part in ("", ".", "..") for part in name.split("/")
        ):
            raise ValueError(f"invalid secret name {name!r}")
        return self.root.joinpath(*name.split("/")).with_suffix(".json")

    def get(self, name: str) -> dict | None:
        try:
            return json.loads(self._path(name).read_text(encoding="utf-8"))
        except FileNotFoundError:
            return None

    def create(self, name: str, value: dict) -> bool:
        path = self._path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            return False
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(value, fh)
        return True

    def delete(self, name: str) -> bool:
        try:
            self._path(name).unlink()
            return True
        except FileNotFoundError:
            return False


class AwsSecretStore:
    """AWS Secrets Manager through the default credential chain (IRSA in EKS)."""

    def __init__(self, client=None, tags: Mapping[str, str] | None = None):
        if client is None:
            import boto3  # imported lazily so the file backend needs no AWS SDK

            client = boto3.client("secretsmanager")
        self.client = client
        self.tags = [{"Key": k, "Value": v} for k, v in (tags or {}).items()]

    def get(self, name: str) -> dict | None:
        try:
            response = self.client.get_secret_value(SecretId=name)
        except Exception as exc:  # botocore ClientError
            if _error_code(exc) == "ResourceNotFoundException":
                return None
            raise
        return json.loads(response["SecretString"])

    def create(self, name: str, value: dict) -> bool:
        kwargs = {"Name": name, "SecretString": json.dumps(value)}
        if self.tags:
            kwargs["Tags"] = self.tags
        try:
            self.client.create_secret(**kwargs)
        except Exception as exc:
            if _error_code(exc) == "ResourceExistsException":
                return False
            raise
        return True

    def delete(self, name: str) -> bool:
        try:
            # No recovery window: teardown inventory must find no P4 secret.
            self.client.delete_secret(SecretId=name, ForceDeleteWithoutRecovery=True)
        except Exception as exc:
            if _error_code(exc) == "ResourceNotFoundException":
                return False
            raise
        return True


def parse_tags(raw: str) -> dict[str, str]:
    """``"Project=Zero-D-Rift,RunId=x"`` -> dict. Empty string -> {}."""
    tags: dict[str, str] = {}
    for item in filter(None, (p.strip() for p in raw.split(","))):
        key, sep, value = item.partition("=")
        if not sep or not key:
            raise ValueError(f"invalid tag {item!r}, expected Key=Value")
        tags[key] = value
    return tags


def store_from_env(env: Mapping[str, str]) -> SecretStore:
    backend = env.get("SECRET_BACKEND", "aws")
    if backend == "aws":
        return AwsSecretStore(tags=parse_tags(env.get("SECRET_TAGS", "")))
    if backend == "file":
        root = env.get("SECRET_DIR")
        if not root:
            raise RuntimeError("SECRET_BACKEND=file needs SECRET_DIR")
        return FileSecretStore(root)
    raise RuntimeError(f"unknown SECRET_BACKEND {backend!r}, expected aws or file")
