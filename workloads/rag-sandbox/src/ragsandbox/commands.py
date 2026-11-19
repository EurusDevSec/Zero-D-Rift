"""The three platform entry points: db-init, bootstrap, cleanup.

Order rule for every command that creates a password: the secret is written
first, then PostgreSQL is changed. If the database step fails, a re-run finds the
secret, reuses its password and finishes the database step. The reverse order
could leave a role whose password no secret holds.

Each command returns a summary dict without secret values; ``__main__`` prints it
as one JSON line, so the lab and the Job log can compare runs.
"""

from __future__ import annotations

from typing import Callable, Mapping

from . import statements as st
from .db import Endpoint, connect, endpoint_from_env, new_password
from .names import BOOTSTRAP_ROLE, BOOTSTRAP_SECRET_DEFAULT, DATABASE, Sandbox, parse_sandbox
from .secretstore import SecretStore, get_or_create, require

Connect = Callable[..., object]

BOOTSTRAP_SPEC = st.RoleSpec(BOOTSTRAP_ROLE, createrole=True, connection_limit=st.BOOTSTRAP_CONNECTION_LIMIT)


def _exists(conn, query, value: str) -> bool:
    return conn.execute(query, (value,)).fetchone() is not None


def _connection_secret(endpoint: Endpoint, username: str, **extra) -> dict:
    return {
        "engine": "postgres",
        **endpoint.as_secret_fields(),
        "dbname": DATABASE,
        "username": username,
        "password": new_password(),
        **extra,
    }


def db_init(env: Mapping[str, str], store: SecretStore, connect_fn: Connect = connect) -> dict:
    """Once per window, master credential: database, bootstrap role, pgvector."""
    endpoint = endpoint_from_env(env)
    master = require(store, env.get("MASTER_SECRET_ID") or _missing("MASTER_SECRET_ID"))
    master_db = env.get("MASTER_DBNAME", "postgres")
    boot_name = env.get("BOOTSTRAP_SECRET_ID", BOOTSTRAP_SECRET_DEFAULT)

    boot, secret_created = get_or_create(
        store, boot_name, lambda: _connection_secret(endpoint, BOOTSTRAP_ROLE)
    )
    if boot.get("username") != BOOTSTRAP_ROLE:
        raise RuntimeError(f"secret {boot_name} belongs to another role")

    # CREATE DATABASE cannot run inside a transaction.
    with connect_fn(endpoint, master, master_db, autocommit=True) as conn:
        database_created = not _exists(conn, st.DATABASE_EXISTS, DATABASE)
        if database_created:
            conn.execute(st.create_database(DATABASE))
        role_exists = _exists(conn, st.ROLE_EXISTS, BOOTSTRAP_ROLE)
        for stmt in st.plan_role(
            BOOTSTRAP_SPEC, boot["password"], role_exists=role_exists, secret_created=secret_created
        ):
            conn.execute(stmt)
        for stmt in st.database_grants(DATABASE, BOOTSTRAP_ROLE):
            conn.execute(stmt)

    with connect_fn(endpoint, master, DATABASE) as conn:
        for stmt in st.database_setup():
            conn.execute(stmt)
        vector = conn.execute(
            "SELECT extversion FROM pg_extension WHERE extname = 'vector'"
        ).fetchone()

    return {
        "command": "db-init",
        "database_created": database_created,
        "bootstrap_role_created": not role_exists,
        "bootstrap_secret": boot_name,
        "bootstrap_secret_created": secret_created,
        "vector_version": vector[0] if vector else None,
    }


def _sandbox_from(env: Mapping[str, str], tenant: str | None, name: str | None) -> Sandbox:
    return parse_sandbox(
        tenant or env.get("SANDBOX_TENANT") or _missing("SANDBOX_TENANT"),
        name or env.get("SANDBOX_NAME") or _missing("SANDBOX_NAME"),
    )


def bootstrap(
    env: Mapping[str, str],
    store: SecretStore,
    tenant: str | None = None,
    name: str | None = None,
    connect_fn: Connect = connect,
) -> dict:
    """Per request, bootstrap credential: schema, login role, grants, secret.

    Idempotent: a re-run with an existing secret changes no password.
    """
    sandbox = _sandbox_from(env, tenant, name)
    endpoint = endpoint_from_env(env)
    boot = require(store, env.get("BOOTSTRAP_SECRET_ID", BOOTSTRAP_SECRET_DEFAULT))
    spec = st.RoleSpec(sandbox.role, createrole=False, connection_limit=st.SANDBOX_CONNECTION_LIMIT)

    secret, secret_created = get_or_create(
        store,
        sandbox.secret_name,
        lambda: _connection_secret(endpoint, sandbox.role, schema=sandbox.schema),
    )
    if secret.get("username") != sandbox.role or secret.get("schema") != sandbox.schema:
        raise RuntimeError(f"secret {sandbox.secret_name} does not belong to {sandbox.role}")

    with connect_fn(endpoint, boot, DATABASE) as conn, conn.transaction():
        conn.execute(st.ADVISORY_LOCK, (sandbox.role,))
        role_exists = _exists(conn, st.ROLE_EXISTS, sandbox.role)
        schema_existed = _exists(conn, st.SCHEMA_EXISTS, sandbox.schema)
        for stmt in st.plan_role(
            spec, secret["password"], role_exists=role_exists, secret_created=secret_created
        ):
            conn.execute(stmt)
        for stmt in st.sandbox_grants(DATABASE, sandbox.schema, sandbox.role):
            conn.execute(stmt)

    return {
        "command": "bootstrap",
        "tenant": sandbox.tenant,
        "sandbox": sandbox.name,
        "schema": sandbox.schema,
        "role": sandbox.role,
        "secret": sandbox.secret_name,
        "role_created": not role_exists,
        "schema_created": not schema_existed,
        "secret_created": secret_created,
        "password_changed": (not role_exists) or secret_created,
    }


def cleanup(
    env: Mapping[str, str],
    store: SecretStore,
    tenant: str | None = None,
    name: str | None = None,
    connect_fn: Connect = connect,
) -> dict:
    """Operator-run (D9): drop schema (with its tables) and role, delete the secret.

    Run it after the app is gone; open sessions of the role are not terminated.
    Old Jobs and their Pods are deleted by the runbook, not here.
    """
    sandbox = _sandbox_from(env, tenant, name)
    endpoint = endpoint_from_env(env)
    boot = require(store, env.get("BOOTSTRAP_SECRET_ID", BOOTSTRAP_SECRET_DEFAULT))

    with connect_fn(endpoint, boot, DATABASE) as conn, conn.transaction():
        conn.execute(st.ADVISORY_LOCK, (sandbox.role,))
        schema_existed = _exists(conn, st.SCHEMA_EXISTS, sandbox.schema)
        conn.execute(st.drop_schema(sandbox.schema))
        role_existed = _exists(conn, st.ROLE_EXISTS, sandbox.role)
        if role_existed:
            for stmt in st.drop_role(DATABASE, sandbox.role):
                conn.execute(stmt)

    secret_deleted = store.delete(sandbox.secret_name)
    return {
        "command": "cleanup",
        "tenant": sandbox.tenant,
        "sandbox": sandbox.name,
        "schema_dropped": schema_existed,
        "role_dropped": role_existed,
        "secret_deleted": secret_deleted,
    }


def _missing(var: str):
    raise RuntimeError(f"{var} is not set")
