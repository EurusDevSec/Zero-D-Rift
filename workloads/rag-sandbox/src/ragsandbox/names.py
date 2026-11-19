"""Sandbox naming contract (SPEC-P4 D3, D11; ADR-0008 §4).

A sandbox is identified by its tenant (the request namespace) and its name (the
request's metadata.name). Every PostgreSQL identifier and secret name is derived
here, so callers never build them by string concatenation.

Derived names
- schema and login role: ``rag_<tenant>__<name>`` with ``-`` mapped to ``_``,
  for example ``tenant-a`` / ``docs-qa`` -> ``rag_tenant_a__docs_qa``. Schema and
  role share the name, so the role's search path is obvious when reading grants.
- sandbox secret: ``zero-drift/rag/<tenant>/<name>``, inside the IAM prefix
  ``zero-drift/rag/tenant-*/`` that ADR-0008 gives the bootstrap role.

The mapping is injective: tenants come from a fixed list and names are
DNS-1123 labels without ``_`` and without ``--``.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

TENANTS = ("tenant-a", "tenant-b")
DATABASE = "rag"
BOOTSTRAP_ROLE = "rag_bootstrap"
SECRET_PREFIX = "zero-drift/rag"
BOOTSTRAP_SECRET_DEFAULT = f"{SECRET_PREFIX}/platform/bootstrap"

# 1 to 32 characters: lowercase letter first, lowercase letter or digit last,
# hyphens only between them. 32 keeps the identifier (at most 46 bytes) below the
# PostgreSQL limit of 63 and the bucket name zero-drift-rag-<tenant>-<name>
# below the S3 limit of 63.
NAME_MAX = 32
_NAME_RE = re.compile(r"^[a-z](?:[a-z0-9-]{0,30}[a-z0-9])?$")


class InvalidName(ValueError):
    """Raised when a tenant or sandbox name breaks the contract."""


@dataclass(frozen=True)
class Sandbox:
    tenant: str
    name: str

    @property
    def ident(self) -> str:
        return "rag_" + self.tenant.replace("-", "_") + "__" + self.name.replace("-", "_")

    @property
    def schema(self) -> str:
        return self.ident

    @property
    def role(self) -> str:
        return self.ident

    @property
    def secret_name(self) -> str:
        return f"{SECRET_PREFIX}/{self.tenant}/{self.name}"


def validate_name(name: str) -> str:
    if not isinstance(name, str) or not _NAME_RE.fullmatch(name) or "--" in name:
        raise InvalidName(
            f"sandbox name {name!r} must be 1-{NAME_MAX} chars of [a-z0-9-], "
            "start with a letter, end with a letter or digit, and contain no '--'"
        )
    return name


def validate_tenant(tenant: str) -> str:
    if tenant not in TENANTS:
        raise InvalidName(f"tenant {tenant!r} is not one of {', '.join(TENANTS)}")
    return tenant


def parse_sandbox(tenant: str, name: str) -> Sandbox:
    return Sandbox(validate_tenant(tenant), validate_name(name))
