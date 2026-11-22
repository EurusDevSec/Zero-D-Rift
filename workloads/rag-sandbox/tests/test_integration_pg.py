"""Against a real PostgreSQL 17 + pgvector (the pinned kind image).

Skipped unless RAG_TEST_PG_HOST and RAG_TEST_PG_PASSWORD (superuser ``postgres``)
are set. On vanilla PostgreSQL the master must be a superuser, because pgvector
0.8.2 is not a trusted extension; on RDS it is ``rds_superuser``. This test does
not prove RDS, IRSA or Secrets Manager behaviour.
"""

import os
import time

import psycopg
import pytest
from psycopg import errors

from ragsandbox import commands
from ragsandbox import serve as sv
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


def _app(endpoint, store, secret):
    db = sv.Database(endpoint, store, secret, reload_seconds=0)
    return sv.App(db, sv.Bucket(None)), db


@pytest.mark.parametrize("secret", ["zero-drift/rag/tenant-a/s1", "zero-drift/rag/tenant-b/s2"])
def test_3c_serve_ready_and_query(endpoint, store, secret):
    for _ in range(2):  # a restarted Pod seeds again without duplicating rows
        app, db = _app(endpoint, store, secret)
        status, body = app.readyz()
        assert status == 200, body
        status, body = app.query({"v": ["1,0,0,0"], "k": ["2"]})
        assert status == 200 and [r["id"] for r in body["results"]] == [1, 5]
        db.close()
    with as_role(endpoint, store, secret) as c:
        assert c.execute("SELECT count(*) FROM documents").fetchone()[0] == len(sv.SEED)


def test_3d_serve_wrong_password_not_ready_then_recovers(endpoint, store):
    good = store.get("zero-drift/rag/tenant-a/s1")
    store.create("lab/wrong", {**good, "password": "not-the-password"})
    app, db = _app(endpoint, store, "lab/wrong")
    status, body = app.readyz()
    # Real libpq text names the host and role; only a fixed label may come out.
    assert status == 503 and body["db"] == "error: OperationalError: authentication failed"
    assert endpoint.host not in str(body)
    # The secret is corrected (as after a rotation): the app re-reads and recovers.
    store.delete("lab/wrong")
    store.create("lab/wrong", good)
    assert app.readyz()[0] == 200
    db.close()
    store.delete("lab/wrong")


def _sleep(seconds):
    return lambda c: c.execute("SELECT pg_sleep(%s)", (seconds,)).fetchone()


def test_3e_serve_statement_timeout_is_server_side(endpoint, store):
    # The server cancels the statement (SQLSTATE 57014); no retry doubles the wait.
    db = sv.Database(endpoint, store, "zero-drift/rag/tenant-a/s1", reload_seconds=0, call_timeout=10)
    db.run(sv.check_schema)
    start = time.monotonic()
    with pytest.raises(sv.NotReady, match="QueryCanceled: SQLSTATE 57014"):
        db.run(_sleep(5))
    assert time.monotonic() - start < sv.STATEMENT_TIMEOUT_MS / 1000 + 1
    assert db.run(sv.check_schema)["schema"] == ROLE_A
    db.close()


def test_3f_serve_watchdog_wakes_a_call_the_server_never_answers(endpoint, store):
    # Stands in for a stopped server: the statement_timeout is set above the
    # watchdog, so only the client-side socket shutdown can end the call.
    options = {**sv.SERVE_CONNECT, "options": "-c statement_timeout=30000"}
    db = sv.Database(endpoint, store, "zero-drift/rag/tenant-a/s1", reload_seconds=0,
                     connect_options=options, call_timeout=0.5)
    db.run(sv.check_schema)
    start = time.monotonic()
    with pytest.raises(sv.NotReady, match="timeout: no answer from the database within 0.5 s"):
        db.run(_sleep(10))
    assert time.monotonic() - start < 2
    assert db.run(sv.check_schema)["schema"] == ROLE_A  # reconnects by itself
    db.close()


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


def test_4c_serve_refuses_another_sandboxs_credential(endpoint, store):
    """Codex C4: tenant-a's valid credential, but the request is tenant-b's sandbox."""
    db = sv.Database(endpoint, store, "zero-drift/rag/tenant-a/s1", reload_seconds=0,
                     expect=("rag_tenant_b__s2", "rag_tenant_b__s2"))
    with pytest.raises(sv.NotReady, match="expected role and schema"):
        db.run(sv.check_schema)


def test_6b_bootstrap_cannot_pass_on_create_database(endpoint, store):
    """Codex C9: bootstrap keeps CREATE for its own schemas but cannot hand it on."""
    with as_role(endpoint, store, BOOT) as c:
        row = c.execute(
            "SELECT has_database_privilege(current_user, 'rag', 'CREATE'),"
            " has_database_privilege(current_user, 'rag', 'CREATE WITH GRANT OPTION'),"
            " has_database_privilege(current_user, 'rag', 'CONNECT WITH GRANT OPTION')"
        ).fetchone()
    assert row == (True, False, True)


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
