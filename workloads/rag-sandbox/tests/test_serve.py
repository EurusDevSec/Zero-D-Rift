"""serve with fakes: readiness layers, credential reload, query validation, HTTP."""

import contextlib
import json
import socket
import threading
import time
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import psycopg
import pytest

from ragsandbox import serve as sv
from ragsandbox.db import Endpoint

EP = Endpoint("db.example", 5432, "disable", None)
SECRET = "zero-drift/rag/tenant-a/s1"
GOOD = {"username": "rag_tenant_a__s1", "password": "p1", "dbname": "rag"}


class Store:
    def __init__(self, value=None):
        self.value = value
        self.reads = 0

    def get(self, name):
        self.reads += 1
        return None if self.value is None else dict(self.value)


class Result:
    def __init__(self, rows):
        self.rows = rows

    def fetchone(self):
        return self.rows[0] if self.rows else None

    def fetchall(self):
        return self.rows


class Conn:
    def __init__(self, server):
        self.server = server
        self.closed = False
        self.aborted = threading.Event()

    @contextlib.contextmanager
    def transaction(self):
        yield

    def execute(self, query, params=None):
        text = query.as_string(None)
        self.server.statements.append(text)
        if self.server.hung:  # process stopped, kernel still ACKs: only an abort wakes us
            self.server.entered.set()
            if not self.aborted.wait(10):
                raise AssertionError("never aborted: the call would hang")
            raise psycopg.OperationalError("server closed the connection unexpectedly")
        if self.server.error is not None:
            raise self.server.error
        if self.server.broken:
            raise psycopg.OperationalError("server closed the connection unexpectedly")
        if text.startswith("SELECT current_user"):
            return Result([self.server.identity])
        if "information_schema.columns" in text:
            return Result([("rag_tenant_a__s1", self.server.vector_columns)])
        if text.startswith("SELECT id, title"):
            return Result(self.server.rows[: params[1]])
        return Result([])

    def close(self):
        self.closed = True


class Server:
    """Stands in for PostgreSQL: accepts one password, can drop connections."""

    def __init__(self, password="p1"):
        self.password = password
        self.broken = False
        self.hung = False
        self.entered = threading.Event()
        self.error = None
        self.connect_error = None
        self.options = None
        self.vector_columns = 1
        self.identity = ("rag_tenant_a__s1", "rag_tenant_a__s1")
        self.rows = [(1, "kro builds the sandbox graph", 0.0), (5, "kro waits", 0.1414)]
        self.statements = []
        self.logins = []

    def connect(self, endpoint, credential, dbname, *, autocommit, **options):
        assert autocommit and dbname == "rag"
        assert options["tcp_user_timeout"] and options["connect_timeout"] <= 3
        self.logins.append(credential["password"])
        self.options = options
        if self.connect_error is not None:
            raise self.connect_error
        if self.broken:
            raise psycopg.OperationalError("connection refused")
        if credential["password"] != self.password:
            raise psycopg.OperationalError('password authentication failed for user "x"')
        return Conn(self)


class Clock:
    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now


def make_db(store, server, clock=None, reload_seconds=5.0, **bounds):
    return sv.Database(EP, store, SECRET, connect_fn=server.connect,
                       reload_seconds=reload_seconds, clock=clock or Clock(), **bounds)


def fake_abort(conn):
    conn.aborted.set()


class S3:
    def __init__(self, code=None):
        self.code = code
        self.calls = []

    def head_bucket(self, Bucket):
        self.calls.append(Bucket)
        if self.code:
            exc = Exception("boom")
            exc.response = {"Error": {"Code": self.code}}
            raise exc


# --- readiness ---------------------------------------------------------------


def test_ready_when_schema_and_bucket_pass():
    server = Server()
    app = sv.App(make_db(Store(GOOD), server), sv.Bucket("zero-drift-rag-tenant-a-s1", S3()))
    status, body = app.readyz()
    assert status == 200
    assert body == {"ready": True, "db": "ok", "bucket": "ok", "schema": "rag_tenant_a__s1"}


def test_seed_runs_on_connect_under_a_lock():
    server = Server()
    make_db(Store(GOOD), server).run(sv.check_schema)
    assert server.statements[0].startswith("SELECT pg_advisory_xact_lock")
    assert server.statements[1].startswith('CREATE TABLE IF NOT EXISTS "documents"')
    inserts = [s for s in server.statements if s.startswith("INSERT")]
    assert len(inserts) == len(sv.SEED) and all("ON CONFLICT (id) DO NOTHING" in s for s in inserts)


IDENT_A = ("rag_tenant_a__s1", "rag_tenant_a__s1")


def test_identity_checked_before_seed():
    server = Server()
    make_db(Store(GOOD), server, expect=IDENT_A).run(sv.check_schema)
    assert server.statements[0] == "SELECT current_user, current_schema()"
    assert server.statements[1].startswith("SELECT pg_advisory_xact_lock")


def test_not_ready_with_another_sandboxs_credential():
    # Codex C4: valid login, wrong sandbox. No seed, no 200, even with the bucket fine.
    server = Server()
    server.identity = ("rag_tenant_b__s1", "rag_tenant_b__s1")
    app = sv.App(make_db(Store(GOOD), server, expect=IDENT_A), sv.Bucket("zero-drift-rag-tenant-a-s1", S3()))
    status, body = app.readyz()
    assert status == 503 and not body["ready"]
    assert "expected role and schema" in body["db"]
    assert not any(s.startswith(("CREATE", "INSERT", "SELECT pg_advisory")) for s in server.statements)


def test_not_ready_without_secret():
    app = sv.App(make_db(Store(None), Server()), sv.Bucket(None))
    status, body = app.readyz()
    assert status == 503 and not body["ready"]
    assert "not found" in body["db"] and body["bucket"] == "skipped"


def test_not_ready_without_vector_column():
    server = Server()
    server.vector_columns = 0
    status, body = sv.App(make_db(Store(GOOD), server), sv.Bucket(None)).readyz()
    assert status == 503 and "no vector column" in body["db"]


def test_not_ready_when_bucket_denied_even_if_db_ok():
    app = sv.App(make_db(Store(GOOD), Server()), sv.Bucket("b", S3("403")))
    status, body = app.readyz()
    assert status == 503 and body["db"] == "ok" and body["bucket"] == "error: bucket b: 403"


def test_bucket_check_off_is_reported_not_hidden():
    status, body = sv.App(make_db(Store(GOOD), Server()), sv.Bucket(None)).readyz()
    assert status == 200 and body["bucket"] == "skipped"


# --- credential reload ------------------------------------------------------


def test_secret_appears_later():
    store, clock = Store(None), Clock()
    db = make_db(store, Server(), clock)
    with pytest.raises(sv.NotReady):
        db.run(sv.check_schema)
    store.value = GOOD
    with pytest.raises(sv.NotReady):  # inside the reload interval: no new read
        db.run(sv.check_schema)
    assert store.reads == 1
    clock.now += 5
    assert db.run(sv.check_schema) == {"schema": "rag_tenant_a__s1"}
    assert store.reads == 2


def test_password_rotated_rereads_secret_and_reconnects():
    store, server, clock = Store(GOOD), Server(), Clock()
    db = make_db(store, server, clock)
    db.run(sv.check_schema)
    # Rotation (P8): the database and the secret now hold p2; the open connection dies.
    server.password, store.value = "p2", {**GOOD, "password": "p2"}
    server.broken = True
    clock.now += 60
    with pytest.raises(sv.NotReady):
        db.run(sv.check_schema)
    server.broken = False
    clock.now += 60
    assert db.run(sv.check_schema)["schema"] == "rag_tenant_a__s1"
    assert server.logins[-1] == "p2"


def test_auth_failure_retries_once_with_fresh_secret():
    store, server, clock = Store({**GOOD, "password": "old"}), Server(), Clock()
    db = make_db(store, server, clock, reload_seconds=0)
    store.value = GOOD  # secret already fixed; cached credential is stale
    db._credential, db._read_at = {**GOOD, "password": "old"}, clock.now
    assert db.run(sv.check_schema)["schema"] == "rag_tenant_a__s1"
    assert server.logins == ["old", "p1"]


def test_wrong_password_stays_not_ready_and_says_why():
    server = Server(password="other")
    status, body = sv.App(make_db(Store(GOOD), server, reload_seconds=0), sv.Bucket(None)).readyz()
    assert status == 503
    assert body["db"] == "error: OperationalError: authentication failed"
    assert "p1" not in json.dumps(body)


# --- no identifiers in errors (Codex review of PR #39) -----------------------

ARN = "arn:aws:sts::123456789012:assumed-role/zdr-rag-tenant-a/botocore-session-1"


def access_denied(operation):
    from botocore.exceptions import ClientError

    message = f"User: {ARN} is not authorized to perform: {operation} with an explicit deny"
    return ClientError({"Error": {"Code": "AccessDeniedException", "Message": message}}, operation)


class DeniedStore:
    def get(self, name):
        raise access_denied("secretsmanager:GetSecretValue")


def test_secret_access_denied_shows_code_not_arn():
    status, body = sv.App(make_db(DeniedStore(), Server()), sv.Bucket(None)).readyz()
    assert status == 503
    assert body["db"] == f"error: secret {SECRET}: ClientError: AccessDeniedException"
    assert "123456789012" not in json.dumps(body) and "arn:" not in json.dumps(body)


def test_connection_error_hides_host_and_address():
    server = Server()
    server.connect = lambda *a, **k: (_ for _ in ()).throw(psycopg.OperationalError(
        'connection to server at "zdr-p4.abc123.us-east-1.rds.amazonaws.com" (10.20.1.7), '
        "port 5432 failed: Connection refused"))
    status, body = sv.App(make_db(Store(GOOD), server), sv.Bucket(None)).readyz()
    text = json.dumps(body)
    assert status == 503 and body["db"] == "error: OperationalError: connection refused"
    assert "rds.amazonaws.com" not in text and "10.20.1.7" not in text


def test_bucket_error_without_code_hides_message():
    from botocore.exceptions import EndpointConnectionError

    class Unreachable:
        def head_bucket(self, Bucket):
            raise EndpointConnectionError(endpoint_url="https://vpce-0abc.s3.us-east-1.vpce.amazonaws.com")

    status, body = sv.App(make_db(Store(GOOD), Server()), sv.Bucket("b", Unreachable())).readyz()
    assert status == 503 and body["bucket"] == "error: bucket b: EndpointConnectionError"


def test_bucket_access_denied_shows_code():
    class Denied:
        def head_bucket(self, Bucket):
            raise access_denied("s3:ListBucket")

    body = sv.App(make_db(Store(GOOD), Server()), sv.Bucket("b", Denied())).readyz()[1]
    assert body["bucket"] == "error: bucket b: AccessDeniedException" and ARN not in json.dumps(body)


def test_error_log_line_has_no_arn(capsys):
    app = sv.App(make_db(DeniedStore(), Server()), sv.Bucket(None))
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), sv.make_handler(app))
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        with pytest.raises(urllib.error.HTTPError) as err:
            urllib.request.urlopen(f"http://127.0.0.1:{httpd.server_address[1]}/readyz", timeout=5)
        assert err.value.code == 503 and ARN not in err.value.read().decode()
    finally:
        httpd.shutdown()
        httpd.server_close()
    log = capsys.readouterr().err
    assert "GET /readyz 503" in log and "AccessDeniedException" in log and "123456789012" not in log


def test_incomplete_secret_is_not_ready():
    db = make_db(Store({"username": "x"}), Server())
    with pytest.raises(sv.NotReady, match="incomplete"):
        db.run(sv.check_schema)


# --- hung database: bounded time (DRF-51 finding 2) --------------------------


def hung_db(server, **bounds):
    bounds = {"call_timeout": 0.2, "lock_wait": 0.05, "abort_fn": fake_abort, **bounds}
    return make_db(Store(GOOD), server, **bounds)


def timed(fn):
    start = time.monotonic()
    result = fn()
    return result, time.monotonic() - start


def test_serve_connections_carry_a_statement_timeout():
    server = Server()
    make_db(Store(GOOD), server).run(sv.check_schema)
    assert server.options["options"] == f"-c statement_timeout={sv.STATEMENT_TIMEOUT_MS}"
    assert sv.LOCK_WAIT + sv.CALL_TIMEOUT < 8 / 2  # well under the probe's timeoutSeconds


def test_hung_server_times_out_without_retry_then_recovers():
    server = Server()
    db = hung_db(server)
    db.run(sv.check_schema)  # connected and seeded
    server.hung = True
    with pytest.raises(sv.NotReady, match="timeout: no answer from the database within 0.2 s"):
        timed(lambda: db.run(sv.check_schema))
    assert len(server.logins) == 1  # no second wait on a hung server
    assert db._conn is None
    server.hung = False
    assert db.run(sv.check_schema)["schema"] == "rag_tenant_a__s1"


def test_hung_server_during_seed_of_a_new_connection():
    server = Server()
    server.hung = True
    status, body = sv.App(hung_db(server), sv.Bucket(None)).readyz()
    assert status == 503 and body["db"].startswith("error: timeout")


def test_waiting_request_gets_busy_instead_of_queueing():
    server = Server()
    db = hung_db(server, call_timeout=1.0, lock_wait=0.1)
    db.run(sv.check_schema)
    server.hung = True
    app = sv.App(db, sv.Bucket(None))
    first = {}
    stuck = threading.Thread(target=lambda: first.update(body=app.readyz()[1]))
    stuck.start()
    assert server.entered.wait(5)
    (status, body), elapsed = timed(app.readyz)
    assert status == 503 and body["db"].startswith("error: busy") and elapsed < 0.5
    status, body = app.query({"v": ["1,0,0,0"]})
    assert status == 503 and body["error"].startswith("busy")
    stuck.join(5)
    assert first["body"]["db"].startswith("error: timeout")


def test_statement_timeout_is_not_retried():
    server = Server()
    db = make_db(Store(GOOD), server)
    db.run(sv.check_schema)
    server.error = psycopg.errors.QueryCanceled("canceling statement due to statement timeout")
    with pytest.raises(sv.NotReady, match="QueryCanceled: SQLSTATE 57014"):
        db.run(sv.check_schema)
    assert len(server.logins) == 1


def test_connect_timeout_is_not_retried():
    server = Server()
    server.connect_error = psycopg.errors.ConnectionTimeout("connection timeout expired")
    with pytest.raises(sv.NotReady, match="ConnectionTimeout: timeout"):
        make_db(Store(GOOD), server, reload_seconds=0).run(sv.check_schema)
    assert len(server.logins) == 1


def test_readyz_checks_db_and_bucket_in_parallel():
    class SlowS3(S3):
        def head_bucket(self, Bucket):
            time.sleep(0.5)
            raise EndpointTimeout()

    class EndpointTimeout(Exception):
        pass

    server = Server()
    server.hung = True
    app = sv.App(hung_db(server, call_timeout=0.5), sv.Bucket("b", SlowS3()))
    (status, body), elapsed = timed(app.readyz)
    assert status == 503 and body["db"].startswith("error: timeout")
    assert body["bucket"] == "error: bucket b: EndpointTimeout"
    assert elapsed < 0.9  # the slower check, not the sum


def test_shutdown_socket_wakes_a_blocked_reader():
    a, b = socket.socketpair()
    got = []
    reader = threading.Thread(target=lambda: got.append(a.recv(1)))
    reader.start()
    time.sleep(0.1)
    conn = type("C", (), {"pgconn": type("P", (), {"socket": a.fileno()})()})()
    sv.shutdown_socket(conn)
    reader.join(2)
    assert got == [b""] and not reader.is_alive()
    a.close()
    b.close()


# --- query ------------------------------------------------------------------


@pytest.mark.parametrize("raw", ["", "1,0,0", "1,0,0,0,0", "a,b,c,d", "nan,0,0,0", "inf,0,0,0"])
def test_query_rejects_bad_vectors(raw):
    app = sv.App(make_db(Store(GOOD), Server()), sv.Bucket(None))
    status, body = app.query({"v": [raw]})
    assert status == 400 and "v must be" in body["error"]


@pytest.mark.parametrize("k", ["0", "11", "x"])
def test_query_rejects_bad_k(k):
    app = sv.App(make_db(Store(GOOD), Server()), sv.Bucket(None))
    assert app.query({"v": ["1,0,0,0"], "k": [k]})[0] == 400


def test_query_returns_nearest():
    app = sv.App(make_db(Store(GOOD), Server()), sv.Bucket(None))
    status, body = app.query({"v": ["1,0,0,0"], "k": ["2"]})
    assert status == 200 and [r["id"] for r in body["results"]] == [1, 5]


def test_vector_literal():
    assert sv.vector_literal((1, 0.5, 0, 0)) == "[1.0,0.5,0.0,0.0]"


# --- configuration ----------------------------------------------------------


BASE = {"DB_HOST": "h", "DB_SSLMODE": "disable", "SECRET_BACKEND": "file", "SECRET_DIR": "/tmp/x"}


def test_config_needs_secret_id():
    with pytest.raises(sv.ConfigError, match="DB_SECRET_ID"):
        sv.app_from_env({**BASE, "S3_BUCKET": "b"})


def test_config_derives_expected_identity():
    app = sv.app_from_env({**BASE, "DB_SECRET_ID": SECRET, "BUCKET_CHECK": "off"})
    assert app.db.expect == IDENT_A
    app = sv.app_from_env({**BASE, "DB_SECRET_ID": SECRET, "BUCKET_CHECK": "off",
                           "SANDBOX_TENANT": "tenant-a", "SANDBOX_NAME": "s1"})
    assert app.db.expect == IDENT_A


@pytest.mark.parametrize("extra", [
    {"DB_SECRET_ID": "zero-drift/rag/platform/bootstrap"},
    {"DB_SECRET_ID": "other/tenant-a/s1"},
    {"DB_SECRET_ID": SECRET, "SANDBOX_TENANT": "tenant-b", "SANDBOX_NAME": "s1"},
    {"DB_SECRET_ID": SECRET, "SANDBOX_TENANT": "tenant-a"},
])
def test_config_rejects_secret_of_another_sandbox(extra):
    with pytest.raises(sv.ConfigError):
        sv.app_from_env({**BASE, "BUCKET_CHECK": "off", **extra})


def test_config_needs_bucket_unless_lab_turns_it_off():
    with pytest.raises(sv.ConfigError, match="S3_BUCKET"):
        sv.app_from_env({**BASE, "DB_SECRET_ID": SECRET})
    app = sv.app_from_env({**BASE, "DB_SECRET_ID": SECRET, "BUCKET_CHECK": "off"})
    assert app.bucket.name is None


def test_config_defaults_to_verify_full():
    with pytest.raises(RuntimeError, match="DB_SSLROOTCERT"):
        sv.app_from_env({**BASE, "DB_SECRET_ID": SECRET, "S3_BUCKET": "b", "DB_SSLMODE": "verify-full"})
    env = {k: v for k, v in BASE.items() if k != "DB_SSLMODE"}
    with pytest.raises(RuntimeError, match="DB_SSLROOTCERT"):
        sv.app_from_env({**env, "DB_SECRET_ID": SECRET, "S3_BUCKET": "b"})


# --- HTTP -------------------------------------------------------------------


@pytest.fixture
def http():
    server_db = Server()
    app = sv.App(make_db(Store(GOOD), server_db), sv.Bucket(None))
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), sv.make_handler(app))
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{httpd.server_address[1]}"

    def get(path):
        try:
            with urllib.request.urlopen(base + path, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    get.db = server_db
    yield get
    httpd.shutdown()
    httpd.server_close()


def test_http_endpoints(http):
    assert http("/healthz") == (200, {"status": "ok"})
    assert http("/readyz")[0] == 200
    status, body = http("/query?v=1,0,0,0&k=1")
    assert status == 200 and body["results"][0]["id"] == 1
    assert http("/query?v=1")[0] == 400
    assert http("/nope") == (404, {"error": "not found"})


def test_healthz_ignores_database(http):
    http.db.broken = True
    assert http("/healthz")[0] == 200
    assert http("/readyz")[0] == 503
