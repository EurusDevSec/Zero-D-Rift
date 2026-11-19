"""Command flows against a fake connection: order of steps and the re-run path."""

import contextlib

import pytest

from ragsandbox import commands
from ragsandbox import statements as st
from ragsandbox.db import endpoint_from_env
from ragsandbox.secretstore import FileSecretStore

ENV = {"DB_HOST": "db.lab", "DB_SSLMODE": "disable", "MASTER_SECRET_ID": "lab/master"}


class FakeDB:
    """Holds roles, schemas and databases; records rendered statements."""

    def __init__(self):
        self.roles, self.schemas, self.databases = set(), set(), {"postgres"}
        self.log = []

    def connect(self, endpoint, credential, dbname, *, autocommit=False):
        return FakeConn(self)


class _Row:
    def __init__(self, row):
        self.row = row

    def fetchone(self):
        return self.row


class FakeConn:
    def __init__(self, db):
        self.db = db

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def transaction(self):
        return contextlib.nullcontext()

    def execute(self, stmt, params=None):
        text = stmt if isinstance(stmt, str) else stmt.as_string(None)
        if stmt is st.ROLE_EXISTS:
            return _Row((1,) if params[0] in self.db.roles else None)
        if stmt is st.SCHEMA_EXISTS:
            return _Row((1,) if params[0] in self.db.schemas else None)
        if stmt is st.DATABASE_EXISTS:
            return _Row((1,) if params[0] in self.db.databases else None)
        if stmt is st.ADVISORY_LOCK or text.startswith("SELECT extversion"):
            return _Row(("0.8.2",))
        self.db.log.append(text)
        word = text.split('"')
        if text.startswith("CREATE ROLE"):
            self.db.roles.add(word[1])
        elif text.startswith("DROP ROLE"):
            self.db.roles.discard(word[1])
        elif text.startswith("CREATE SCHEMA"):
            self.db.schemas.add(word[1])
        elif text.startswith("DROP SCHEMA"):
            self.db.schemas.discard(word[1])
        elif text.startswith("CREATE DATABASE"):
            self.db.databases.add(word[1])
        return _Row(None)


@pytest.fixture
def lab(tmp_path):
    store = FileSecretStore(tmp_path)
    store.create("lab/master", {"username": "postgres", "password": "master-pw"})
    return store, FakeDB()


def test_db_init_then_rerun_is_noop_for_passwords(lab):
    store, db = lab
    first = commands.db_init(ENV, store, connect_fn=db.connect)
    assert first["database_created"] and first["bootstrap_role_created"] and first["bootstrap_secret_created"]
    boot_pw = store.get("zero-drift/rag/platform/bootstrap")["password"]

    db.log.clear()
    second = commands.db_init(ENV, store, connect_fn=db.connect)
    assert not second["database_created"] and not second["bootstrap_secret_created"]
    assert store.get("zero-drift/rag/platform/bootstrap")["password"] == boot_pw
    assert not any("PASSWORD" in line for line in db.log)


def test_bootstrap_writes_secret_before_database(lab):
    store, db = lab
    commands.db_init(ENV, store, connect_fn=db.connect)

    class FailingDB(FakeDB):
        def connect(self, *a, **k):
            raise ConnectionError("database unreachable")

    with pytest.raises(ConnectionError):
        commands.bootstrap(ENV, store, "tenant-a", "s1", connect_fn=FailingDB().connect)
    # The secret survived the failure, so a re-run reuses its password.
    pw = store.get("zero-drift/rag/tenant-a/s1")["password"]
    result = commands.bootstrap(ENV, store, "tenant-a", "s1", connect_fn=db.connect)
    assert result["secret_created"] is False and result["role_created"] is True
    assert any(line.endswith(f"PASSWORD '{pw}'") for line in db.log)


def test_bootstrap_rerun_changes_no_password(lab):
    store, db = lab
    commands.db_init(ENV, store, connect_fn=db.connect)
    first = commands.bootstrap(ENV, store, "tenant-a", "s1", connect_fn=db.connect)
    assert first["role_created"] and first["schema_created"] and first["password_changed"]
    pw = store.get("zero-drift/rag/tenant-a/s1")["password"]

    db.log.clear()
    second = commands.bootstrap(ENV, store, "tenant-a", "s1", connect_fn=db.connect)
    assert not (second["role_created"] or second["schema_created"] or second["password_changed"])
    assert store.get("zero-drift/rag/tenant-a/s1")["password"] == pw
    assert not any("PASSWORD" in line for line in db.log)


def test_bootstrap_lost_secret_resets_password(lab):
    store, db = lab
    commands.db_init(ENV, store, connect_fn=db.connect)
    commands.bootstrap(ENV, store, "tenant-a", "s1", connect_fn=db.connect)
    store.delete("zero-drift/rag/tenant-a/s1")
    result = commands.bootstrap(ENV, store, "tenant-a", "s1", connect_fn=db.connect)
    assert result["secret_created"] and result["password_changed"] and not result["role_created"]


def test_bootstrap_rejects_foreign_secret(lab):
    store, db = lab
    commands.db_init(ENV, store, connect_fn=db.connect)
    store.create("zero-drift/rag/tenant-a/s1", {"username": "rag_tenant_b__s1", "password": "x", "schema": "rag_tenant_b__s1"})
    with pytest.raises(RuntimeError, match="does not belong"):
        commands.bootstrap(ENV, store, "tenant-a", "s1", connect_fn=db.connect)


def test_cleanup_removes_everything_and_is_repeatable(lab):
    store, db = lab
    commands.db_init(ENV, store, connect_fn=db.connect)
    commands.bootstrap(ENV, store, "tenant-a", "s1", connect_fn=db.connect)
    first = commands.cleanup(ENV, store, "tenant-a", "s1", connect_fn=db.connect)
    assert first["schema_dropped"] and first["role_dropped"] and first["secret_deleted"]
    assert "rag_tenant_a__s1" not in db.roles | db.schemas
    second = commands.cleanup(ENV, store, "tenant-a", "s1", connect_fn=db.connect)
    assert not (second["schema_dropped"] or second["role_dropped"] or second["secret_deleted"])


def test_sandbox_from_env(lab):
    store, db = lab
    commands.db_init(ENV, store, connect_fn=db.connect)
    env = {**ENV, "SANDBOX_TENANT": "tenant-b", "SANDBOX_NAME": "docs"}
    assert commands.bootstrap(env, store, connect_fn=db.connect)["role"] == "rag_tenant_b__docs"


def test_tls_defaults_to_verify_full():
    with pytest.raises(RuntimeError, match="DB_SSLROOTCERT"):
        endpoint_from_env({"DB_HOST": "h"})
    ep = endpoint_from_env({"DB_HOST": "h", "DB_SSLROOTCERT": "/etc/rds/ca.pem"})
    assert (ep.sslmode, ep.port) == ("verify-full", 5432)
    with pytest.raises(RuntimeError):
        endpoint_from_env({"DB_HOST": "h", "DB_SSLMODE": "prefer"})
