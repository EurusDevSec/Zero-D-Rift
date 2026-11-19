"""SQL builders. Pure functions: no connection, no I/O.

Every identifier goes through ``sql.Identifier`` and every value through
``sql.Literal`` or a bound parameter, so nothing is built by string concatenation
(SPEC-P4 P4-T2.1 A). Passwords are rendered as literals because PostgreSQL does
not accept bound parameters in ``CREATE/ALTER ROLE``; the statement text is never
logged by this package.

Privilege model (ADR-0008 §2, SPEC-P4 D3/D4)
- ``rag_bootstrap``: LOGIN, CREATEROLE, not superuser, no CREATEDB. CONNECT and
  CREATE on database ``rag`` WITH GRANT OPTION, so it can create schemas and give
  CONNECT to sandbox roles. It owns every sandbox schema.
- sandbox role: LOGIN only. CONNECT on ``rag``; USAGE and CREATE on its own schema
  only. It owns the tables it creates there, but nobody else has USAGE on that
  schema, so other sandboxes cannot reach them.
- ``PUBLIC``: no privilege on database ``rag``; no CREATE on schema ``public``.
  USAGE on ``public`` stays, because the ``vector`` type lives there.
"""

from __future__ import annotations

from dataclasses import dataclass

from psycopg import sql

SANDBOX_CONNECTION_LIMIT = 10
BOOTSTRAP_CONNECTION_LIMIT = 5


@dataclass(frozen=True)
class RoleSpec:
    name: str
    createrole: bool
    connection_limit: int


def _attributes(spec: RoleSpec) -> sql.Composed:
    return sql.SQL(
        "LOGIN NOSUPERUSER NOCREATEDB {createrole} NOINHERIT NOREPLICATION "
        "NOBYPASSRLS CONNECTION LIMIT {limit}"
    ).format(
        createrole=sql.SQL("CREATEROLE" if spec.createrole else "NOCREATEROLE"),
        limit=sql.Literal(spec.connection_limit),
    )


def create_role(spec: RoleSpec, password: str) -> sql.Composed:
    return sql.SQL("CREATE ROLE {} WITH {} PASSWORD {}").format(
        sql.Identifier(spec.name), _attributes(spec), sql.Literal(password)
    )


def alter_role_attributes(spec: RoleSpec) -> sql.Composed:
    """Re-assert only the attributes any role manager may restate.

    PostgreSQL 16+ lets a non-superuser change (or even restate, ``NO`` values
    included) SUPERUSER, REPLICATION, BYPASSRLS, CREATEDB or CREATEROLE only if
    it holds that attribute itself. The RDS master (``rds_superuser``) and
    ``rag_bootstrap`` are non-superusers, and ``rag_bootstrap`` has no CREATEDB
    (found on PostgreSQL 17.10, 17/11/2026). Those attributes are fixed by
    ``create_role`` and cannot be raised by a non-superuser later, which the
    integration test checks; a re-run restates the rest.
    """
    return sql.SQL("ALTER ROLE {} WITH LOGIN NOINHERIT CONNECTION LIMIT {}").format(
        sql.Identifier(spec.name), sql.Literal(spec.connection_limit)
    )


def alter_role_password(role: str, password: str) -> sql.Composed:
    return sql.SQL("ALTER ROLE {} WITH PASSWORD {}").format(
        sql.Identifier(role), sql.Literal(password)
    )


def plan_role(
    spec: RoleSpec, password: str, *, role_exists: bool, secret_created: bool
) -> list[sql.Composed]:
    """Statements that make the role match the secret, and nothing more.

    - new role: create it with the secret's password;
    - existing role, existing secret (a re-run): re-assert attributes only, so the
      password a running app uses is kept;
    - existing role, new secret (the secret was lost): set the new password,
      otherwise the secret could never log in.
    """
    if not role_exists:
        return [create_role(spec, password)]
    statements = [alter_role_attributes(spec)]
    if secret_created:
        statements.append(alter_role_password(spec.name, password))
    return statements


# --- db-init (master credential) -------------------------------------------


def create_database(database: str) -> sql.Composed:
    return sql.SQL("CREATE DATABASE {}").format(sql.Identifier(database))


def database_grants(database: str, bootstrap_role: str) -> list[sql.Composed]:
    db = sql.Identifier(database)
    return [
        sql.SQL("REVOKE ALL ON DATABASE {} FROM PUBLIC").format(db),
        sql.SQL("GRANT CONNECT, CREATE ON DATABASE {} TO {} WITH GRANT OPTION").format(
            db, sql.Identifier(bootstrap_role)
        ),
    ]


def database_setup() -> list[sql.Composed]:
    """Run inside database ``rag`` with the master credential."""
    return [
        sql.SQL("CREATE EXTENSION IF NOT EXISTS vector"),
        sql.SQL("REVOKE CREATE ON SCHEMA public FROM PUBLIC"),
    ]


# --- bootstrap and cleanup (bootstrap credential) ---------------------------


def sandbox_grants(database: str, schema: str, role: str) -> list[sql.Composed]:
    s, r = sql.Identifier(schema), sql.Identifier(role)
    return [
        sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(s),
        sql.SQL("REVOKE ALL ON SCHEMA {} FROM PUBLIC").format(s),
        sql.SQL("GRANT USAGE, CREATE ON SCHEMA {} TO {}").format(s, r),
        sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(sql.Identifier(database), r),
        sql.SQL("ALTER ROLE {} SET search_path TO {}, public").format(r, s),
    ]


def drop_schema(schema: str) -> sql.Composed:
    return sql.SQL("DROP SCHEMA IF EXISTS {} CASCADE").format(sql.Identifier(schema))


def drop_role(database: str, role: str) -> list[sql.Composed]:
    r = sql.Identifier(role)
    return [
        sql.SQL("REVOKE ALL ON DATABASE {} FROM {}").format(sql.Identifier(database), r),
        sql.SQL("DROP ROLE {}").format(r),
    ]


# --- state queries (bound parameters) ---------------------------------------

ROLE_EXISTS = sql.SQL("SELECT 1 FROM pg_roles WHERE rolname = %s")
DATABASE_EXISTS = sql.SQL("SELECT 1 FROM pg_database WHERE datname = %s")
SCHEMA_EXISTS = sql.SQL("SELECT 1 FROM pg_namespace WHERE nspname = %s")
# Serialise concurrent runs for the same sandbox (two bootstrap attempts at once).
ADVISORY_LOCK = sql.SQL("SELECT pg_advisory_xact_lock(hashtext(%s))")
