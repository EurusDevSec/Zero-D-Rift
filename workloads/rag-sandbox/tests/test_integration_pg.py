"""Against a real PostgreSQL 17 + pgvector (the pinned kind image).

Skipped unless RAG_TEST_PG_HOST and RAG_TEST_PG_PASSWORD (superuser ``postgres``)
are set. On vanilla PostgreSQL the master must be a superuser, because pgvector
0.8.2 is not a trusted extension; on RDS it is ``rds_superuser``. This test does
not prove RDS, IRSA or Secrets Manager behaviour.
"""

import os

import psycopg
import pytest
from psycopg import errors

from ragsandbox import commands
from ragsandbox.db import Endpoint, connect
from ragsandbox.secretstore import FileSecretStore

HOST = os.environ.get("RAG_TEST_PG_HOST")
pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(not HOST, reason="RAG_TEST_PG_HOST not set"),
]

BOOT = "zero-drift/rag/platform/bootstrap"
A, B = ("tenant-a", "s1"), ("tenant-b", "s2")
ROLE_A, ROLE_B = "rag_tenant_a__s1", "rag_tenant_b__s2"


@pytest.fixture(scope="module")
def env():
    return {"DB_HOST": HOST, "DB_PORT": os.environ.get("RAG_TEST_PG_PORT", "5432"),
            "DB_SSLMODE": "disable", "MASTER_SECRET_ID": "lab/master"}


@pytest.fixture(scope="module")
def store(tmp_path_factory, env):
    s = FileSecretStore(tmp_path_factory.mktemp("secrets"))
    s.create("lab/master", {"username": "postgres", "password": os.environ["RAG_TEST_PG_PASSWORD"]})
    return s


@pytest.fixture(scope="module")
def endpoint(env):
    return Endpoint(env["DB_HOST"], int(env["DB_PORT"]), "disable", None)


def as_role(endpoint, store, secret_name, dbname="rag"):
    return connect(endpoint, store.get(secret_name), dbname, autocommit=True)


def rolpassword(endpoint, store, role):
    with connect(endpoint, store.get("lab/master"), "postgres") as c:
        return c.execute("SELECT rolpassword FROM pg_authid WHERE rolname = %s", (role,)).fetchone()[0]


def test_1_db_init_twice(env, store):
    first = commands.db_init(env, store)
    assert first["vector_version"] == "0.8.2"
    second = commands.db_init(env, store)
    assert not second["database_created"] and not second["bootstrap_secret_created"]


def test_2_bootstrap_two_sandboxes_and_rerun(env, store, endpoint):
    for tenant, name in (A, B):
        assert commands.bootstrap(env, store, tenant, name)["role_created"]
    before = rolpassword(endpoint, store, ROLE_A)
    rerun = commands.bootstrap(env, store, *A)
    assert not (rerun["role_created"] or rerun["schema_created"] or rerun["password_changed"])
    assert rolpassword(endpoint, store, ROLE_A) == before  # same SCRAM verifier: password kept


@pytest.mark.parametrize("secret", ["zero-drift/rag/tenant-a/s1", "zero-drift/rag/tenant-b/s2"])
def test_3_vector_table_and_similarity(endpoint, store, secret):
    with as_role(endpoint, store, secret) as c:
        c.execute("CREATE TABLE items (id int PRIMARY KEY, embedding vector(3))")
        c.execute("INSERT INTO items VALUES (1, '[1,0,0]'), (2, '[0,1,0]'), (3, '[0.9,0.1,0]')")
        rows = c.execute("SELECT id FROM items ORDER BY embedding <-> '[1,0,0]' LIMIT 2").fetchall()
        assert [r[0] for r in rows] == [1, 3]
        schema = c.execute("SELECT schemaname FROM pg_tables WHERE tablename = 'items' AND tableowner = current_user").fetchone()[0]
        assert schema == store.get(secret)["schema"]


def test_4_role_a_cannot_read_schema_b(endpoint, store):
    with as_role(endpoint, store, "zero-drift/rag/tenant-a/s1") as c:
        with pytest.raises(errors.InsufficientPrivilege):
            c.execute(f"SELECT * FROM {ROLE_B}.items")


@pytest.mark.parametrize(
    "statement",
    [
        "CREATE ROLE intruder",
        "CREATE SCHEMA other",
        "CREATE TABLE public.leak (id int)",
    ],
)
def test_5_sandbox_role_denied(endpoint, store, statement):
    with as_role(endpoint, store, "zero-drift/rag/tenant-a/s1") as c:
        with pytest.raises(errors.InsufficientPrivilege):
            c.execute(statement)


def test_5b_role_a_cannot_share_its_schema(endpoint, store):
    """A owns its table and may GRANT on it, but cannot give USAGE on the schema.

    PostgreSQL answers a GRANT without grant option with a WARNING, not an error,
    so the check is the outcome: B still cannot read A's table.
    """
    with as_role(endpoint, store, "zero-drift/rag/tenant-a/s1") as c:
        c.execute(f"GRANT USAGE ON SCHEMA {ROLE_A} TO {ROLE_B}")  # warning, no effect
        c.execute(f"GRANT SELECT ON {ROLE_A}.items TO {ROLE_B}")  # allowed: A owns the table
    with as_role(endpoint, store, "zero-drift/rag/tenant-b/s2") as c:
        with pytest.raises(errors.InsufficientPrivilege, match="schema"):
            c.execute(f"SELECT * FROM {ROLE_A}.items")


@pytest.mark.parametrize(
    "statement",
    ["ALTER ROLE rag_bootstrap SUPERUSER", "CREATE ROLE boss SUPERUSER", "CREATE DATABASE other"],
)
def test_6_bootstrap_cannot_escalate(endpoint, store, statement):
    with as_role(endpoint, store, BOOT) as c:
        with pytest.raises(errors.InsufficientPrivilege):
            c.execute(statement)


def test_7_unlisted_role_cannot_connect_to_rag(endpoint, store):
    with connect(endpoint, store.get("lab/master"), "postgres", autocommit=True) as c:
        c.execute("DROP ROLE IF EXISTS outsider")
        c.execute("CREATE ROLE outsider LOGIN PASSWORD 'outsider-pw'")
    try:
        with pytest.raises(psycopg.OperationalError, match="permission denied for database"):
            connect(endpoint, {"username": "outsider", "password": "outsider-pw"}, "rag")
    finally:
        with connect(endpoint, store.get("lab/master"), "postgres", autocommit=True) as c:
            c.execute("DROP ROLE outsider")


def test_8_cleanup_one_sandbox_leaves_the_other(env, store, endpoint):
    result = commands.cleanup(env, store, *A)
    assert result["schema_dropped"] and result["role_dropped"] and result["secret_deleted"]
    with connect(endpoint, store.get("lab/master"), "rag") as c:
        assert c.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (ROLE_A,)).fetchone() is None
        assert c.execute("SELECT 1 FROM pg_namespace WHERE nspname = %s", (ROLE_A,)).fetchone() is None
        assert c.execute("SELECT count(*) FROM rag_tenant_b__s2.items").fetchone()[0] == 3
    assert store.get("zero-drift/rag/tenant-a/s1") is None
    commands.cleanup(env, store, *B)
