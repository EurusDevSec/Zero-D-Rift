"""Database endpoint and connections.

The endpoint (host, port, TLS mode) comes from the environment, which the RGD
fills from the ``platform-config`` ConfigMap. Credentials come only from a secret.
TLS defaults to ``verify-full``: encryption plus a check that the server's
certificate chains to the RDS CA bundle and matches the host name. A lab must
lower it explicitly.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass
from typing import Mapping

SSL_MODES = ("disable", "require", "verify-ca", "verify-full")


@dataclass(frozen=True)
class Endpoint:
    host: str
    port: int
    sslmode: str
    sslrootcert: str | None

    def as_secret_fields(self) -> dict:
        return {"host": self.host, "port": self.port}


def endpoint_from_env(env: Mapping[str, str]) -> Endpoint:
    host = env.get("DB_HOST")
    if not host:
        raise RuntimeError("DB_HOST is not set")
    sslmode = env.get("DB_SSLMODE", "verify-full")
    if sslmode not in SSL_MODES:
        raise RuntimeError(f"DB_SSLMODE {sslmode!r} is not one of {', '.join(SSL_MODES)}")
    sslrootcert = env.get("DB_SSLROOTCERT") or None
    if sslmode.startswith("verify") and not sslrootcert:
        raise RuntimeError(f"DB_SSLMODE={sslmode} needs DB_SSLROOTCERT (the RDS CA bundle)")
    return Endpoint(host, int(env.get("DB_PORT", "5432")), sslmode, sslrootcert)


def new_password() -> str:
    # 43 URL-safe characters, about 256 bits; no quote or backslash to escape.
    return secrets.token_urlsafe(32)


# For the long-running app: fail fast instead of hanging on a dead peer (an RDS
# reboot or failover drops packets without a reset). tcp_user_timeout bounds a
# query whose packets are never acknowledged; keepalives catch an idle socket.
FAST_FAIL = {
    "connect_timeout": 2,
    "tcp_user_timeout": 3000,
    "keepalives": 1,
    "keepalives_idle": 5,
    "keepalives_interval": 2,
    "keepalives_count": 2,
}


def connect(
    endpoint: Endpoint, credential: Mapping, dbname: str, *, autocommit: bool = False, **options
):
    """Open a psycopg connection. ``options`` are extra libpq parameters."""
    import psycopg

    kwargs = {
        "host": endpoint.host,
        "port": endpoint.port,
        "dbname": dbname,
        "user": credential["username"],
        "password": credential["password"],
        "sslmode": endpoint.sslmode,
        "connect_timeout": 10,
        "application_name": "ragsandbox",
        "autocommit": autocommit,
        **options,
    }
    if endpoint.sslrootcert:
        kwargs["sslrootcert"] = endpoint.sslrootcert
    return psycopg.connect(**kwargs)
