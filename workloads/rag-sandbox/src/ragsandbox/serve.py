"""``serve``: the reference application of one sandbox (SPEC-P4 P4-T3.1 A, D8).

Endpoints
- ``GET /healthz``: the process answers. Nothing else is checked, so a database
  outage restarts nothing.
- ``GET /readyz``: the sandbox is usable. The app queries the ``vector`` column of
  its own table in its own schema, and reaches its bucket. 200 only when both
  pass; otherwise 503 and the layer that failed. The RGD uses it as the
  Deployment's readiness probe, so the instance cannot be Ready on a fake.
- ``GET /query?v=1,0,0,0&k=3``: nearest seeded rows by L2 distance (pgvector
  ``<->``). There is no model call (D8, negative boundary 9): the caller passes
  the vector.

Credential (D5, needed again in P8): the connection comes from the secret named
in ``DB_SECRET_ID``. While the secret is missing, or after an authentication or
connection error, the app reads the secret again and reconnects. Reads are
spaced by ``SECRET_RELOAD_SECONDS`` so a failing probe does not hammer Secrets
Manager.

Time bound (DRF-51 finding 2): a hung server (process stopped, its kernel still
ACKs TCP) defeats ``tcp_user_timeout`` and keepalives, and a frozen backend cannot
apply its own ``statement_timeout``. So each database call has three bounds: the
server cancels a statement after ``STATEMENT_TIMEOUT_MS`` (a live but slow
server, a lock wait); a client watchdog shuts the socket down after
``CALL_TIMEOUT`` (a frozen server); a request waits at most ``LOCK_WAIT`` for the
one connection, then gets 503 ``busy`` instead of queueing. ``/readyz`` checks the
database and the bucket in parallel, so its time is the slower of the two.

Errors in ``/readyz``, ``/query`` and the log carry the exception class and a
code only (``errors.safe_reason``): an AWS message would name the role ARN, a
libpq message the database host.

Seed: on each new connection the app creates ``documents`` in its schema if it
is missing and inserts the seed rows it lacks. The sandbox role owns the table;
nothing else writes it.
"""

from __future__ import annotations

import json
import math
import os
import signal
import socket
import sys
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Mapping
from urllib.parse import parse_qs, urlsplit

from psycopg import sql

from .db import FAST_FAIL, Endpoint, connect, endpoint_from_env
from .errors import aws_error_code, safe_reason
from .names import DATABASE
from .secretstore import SecretStore, store_from_env

DIM = 4
TABLE = "documents"
K_MAX = 10

# Database time budget, well under the RGD readiness timeoutSeconds (8):
# LOCK_WAIT + CALL_TIMEOUT, about 3 s. Connecting is bounded by connect_timeout.
STATEMENT_TIMEOUT_MS = 2000
CALL_TIMEOUT = 2.5
LOCK_WAIT = 0.5
# serve only: db-init and bootstrap connect without a statement_timeout.
SERVE_CONNECT = {**FAST_FAIL, "options": f"-c statement_timeout={STATEMENT_TIMEOUT_MS}"}
SEED = (
    (1, "kro builds the sandbox graph", (1.0, 0.0, 0.0, 0.0)),
    (2, "Crossplane owns the bucket", (0.0, 1.0, 0.0, 0.0)),
    (3, "Terraform owns the shared database", (0.0, 0.0, 1.0, 0.0)),
    (4, "Argo CD syncs the request from Git", (0.0, 0.0, 0.0, 1.0)),
    (5, "kro waits for the bootstrap Job", (0.9, 0.1, 0.0, 0.0)),
    (6, "IRSA scopes the bucket to one tenant", (0.1, 0.9, 0.0, 0.0)),
)

_CREATE_TABLE = sql.SQL(
    "CREATE TABLE IF NOT EXISTS {} (id integer PRIMARY KEY, title text NOT NULL, "
    "embedding vector({}) NOT NULL)"
).format(sql.Identifier(TABLE), sql.Literal(DIM))
_INSERT_SEED = sql.SQL(
    "INSERT INTO {} (id, title, embedding) VALUES (%s, %s, %s::vector) ON CONFLICT (id) DO NOTHING"
).format(sql.Identifier(TABLE))
_SEED_LOCK = sql.SQL("SELECT pg_advisory_xact_lock(hashtext(current_schema()))")
_VECTOR_COLUMN = sql.SQL(
    "SELECT current_schema(), count(*) FROM information_schema.columns "
    "WHERE table_schema = current_schema() AND table_name = %s AND udt_name = 'vector'"
)
_NEAREST = sql.SQL(
    "SELECT id, title, embedding <-> %s::vector AS distance FROM {} ORDER BY 3, 1 LIMIT %s"
).format(sql.Identifier(TABLE))


class NotReady(Exception):
    """A dependency is not usable yet. The message never holds a secret value."""


class ConfigError(ValueError):
    pass


def vector_literal(values) -> str:
    return "[" + ",".join(repr(float(v)) for v in values) + "]"


def parse_vector(raw: str) -> tuple[float, ...]:
    try:
        values = tuple(float(p) for p in raw.split(","))
    except ValueError:
        raise ValueError(f"v must be {DIM} comma-separated numbers") from None
    if len(values) != DIM or not all(math.isfinite(v) for v in values):
        raise ValueError(f"v must be {DIM} comma-separated finite numbers")
    return values


def _retryable(exc: BaseException) -> bool:
    import psycopg
    from psycopg import errors

    # Authentication failures and lost connections are both OperationalError:
    # read the secret again and reconnect once. Not after a timeout: the server
    # is slow or hung, and a second wait would double what the probe waits.
    return isinstance(exc, psycopg.OperationalError) and not isinstance(
        exc, (errors.ConnectionTimeout, errors.QueryCanceled)
    )


def shutdown_socket(conn) -> None:
    """Wake a call blocked on a hung server: shut the connection's socket down, so
    libpq reads end-of-file and the call fails. The descriptor itself stays open;
    the thread that owns the connection closes it."""
    sock = socket.socket(fileno=os.dup(conn.pgconn.socket))
    try:
        sock.shutdown(socket.SHUT_RDWR)
    finally:
        sock.close()


class _Watchdog:
    """After ``seconds``, abort the connection the call is using (or the next one
    it opens). ``fired`` tells the call why it failed."""

    def __init__(self, seconds: float, abort: Callable[[object], None]):
        self.fired = False
        self._abort = abort
        self._conn = None
        self._mutex = threading.Lock()
        self._timer = threading.Timer(seconds, self._fire)
        self._timer.daemon = True
        self._timer.start()

    def _kill(self, conn) -> None:
        try:
            self._abort(conn)
        except Exception:  # already closed: nothing to wake
            pass

    def _fire(self) -> None:
        with self._mutex:
            self.fired, conn = True, self._conn
        if conn is not None:
            self._kill(conn)

    def watch(self, conn) -> None:
        with self._mutex:
            self._conn, fired = conn, self.fired
        if fired:
            self._kill(conn)

    def cancel(self) -> None:
        self._timer.cancel()
        with self._mutex:
            self._conn = None


class Database:
    """One connection, re-made from a freshly read secret after a failure."""

    def __init__(
        self,
        endpoint: Endpoint,
        store: SecretStore,
        secret_id: str,
        *,
        connect_fn: Callable[..., object] = connect,
        reload_seconds: float = 5.0,
        clock: Callable[[], float] = time.monotonic,
        connect_options: Mapping[str, object] | None = None,
        lock_wait: float = LOCK_WAIT,
        call_timeout: float = CALL_TIMEOUT,
        abort_fn: Callable[[object], None] = shutdown_socket,
    ):
        self.endpoint = endpoint
        self.store = store
        self.secret_id = secret_id
        self.connect_fn = connect_fn
        self.reload_seconds = reload_seconds
        self.clock = clock
        self.connect_options = dict(SERVE_CONNECT if connect_options is None else connect_options)
        self.lock_wait = lock_wait
        self.call_timeout = call_timeout
        self.abort_fn = abort_fn
        self._lock = threading.Lock()
        self._conn = None
        self._credential: dict | None = None
        self._read_at: float | None = None
        self.secret_reads = 0
        self.connects = 0

    # -- credential -----------------------------------------------------------
    def _credential_now(self, *, fresh: bool) -> dict:
        due = self._read_at is None or self.clock() - self._read_at >= self.reload_seconds
        if (fresh or self._credential is None) and due:
            self._read_at = self.clock()
            self.secret_reads += 1
            try:
                value = self.store.get(self.secret_id)
            except Exception as exc:  # e.g. AccessDeniedException: code only, no ARN
                raise NotReady(f"secret {self.secret_id}: {safe_reason(exc)}") from None
            if value is not None and not (value.get("username") and value.get("password")):
                value = None
            self._credential = value
        if self._credential is None:
            raise NotReady(f"secret {self.secret_id} not found or incomplete")
        return self._credential

    # -- connection -----------------------------------------------------------
    def _drop(self) -> None:
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
        self._conn = None

    def _open(self, *, fresh: bool, watch: Callable[[object], None]):
        credential = self._credential_now(fresh=fresh)
        conn = self.connect_fn(
            self.endpoint,
            credential,
            credential.get("dbname") or DATABASE,
            autocommit=True,
            **self.connect_options,
        )
        self.connects += 1
        watch(conn)
        try:
            ensure_seed(conn)
        except Exception:
            conn.close()
            raise
        self._conn = conn
        return conn

    def run(self, fn: Callable[[object], object]):
        """Run ``fn(conn)``. After a connection or authentication error, read the
        secret again, reconnect and try once more. Bounded in time: see the
        module docstring."""
        if not self._lock.acquire(timeout=self.lock_wait):
            raise NotReady("busy: an earlier database call has not finished")
        dog = _Watchdog(self.call_timeout, self.abort_fn)
        try:
            for attempt in (0, 1):
                try:
                    conn = self._conn
                    if conn is None:
                        conn = self._open(fresh=attempt == 1, watch=dog.watch)
                    else:
                        dog.watch(conn)
                    return fn(conn)
                except NotReady:
                    raise
                except Exception as exc:
                    self._drop()
                    if dog.fired:
                        raise NotReady(
                            f"timeout: no answer from the database within {self.call_timeout:g} s"
                        ) from None
                    if attempt == 1 or not _retryable(exc):
                        raise NotReady(safe_reason(exc)) from None
            raise AssertionError("unreachable")
        finally:
            dog.cancel()
            self._lock.release()

    def close(self) -> None:
        with self._lock:
            self._drop()


def ensure_seed(conn) -> None:
    with conn.transaction():
        conn.execute(_SEED_LOCK)
        conn.execute(_CREATE_TABLE)
        for row_id, title, vector in SEED:
            conn.execute(_INSERT_SEED, (row_id, title, vector_literal(vector)))


def check_schema(conn) -> dict:
    schema, columns = conn.execute(_VECTOR_COLUMN, (TABLE,)).fetchone()
    if columns != 1:
        raise NotReady(f"table {TABLE} in schema {schema} has no vector column")
    nearest = conn.execute(_NEAREST, (vector_literal(SEED[0][2]), 1)).fetchone()
    if nearest is None:
        raise NotReady(f"table {TABLE} in schema {schema} is empty")
    return {"schema": schema}


def nearest(conn, vector, k: int) -> list[dict]:
    rows = conn.execute(_NEAREST, (vector_literal(vector), k)).fetchall()
    return [{"id": r[0], "title": r[1], "distance": float(r[2])} for r in rows]


class Bucket:
    """``HeadBucket`` with the pod's IRSA credentials: the bucket exists and this
    role may list it. ``None`` name means the check is off (kind lab only)."""

    def __init__(self, name: str | None, client=None):
        self.name = name
        self._client = client

    def _s3(self):
        if self._client is None:
            import boto3
            from botocore.config import Config

            self._client = boto3.client(
                "s3",
                config=Config(connect_timeout=3, read_timeout=3, retries={"max_attempts": 1}),
            )
        return self._client

    def check(self) -> str:
        if self.name is None:
            return "skipped"
        try:
            self._s3().head_bucket(Bucket=self.name)
        except Exception as exc:
            code = aws_error_code(exc)
            raise NotReady(f"bucket {self.name}: {code or safe_reason(exc)}") from None
        return "ok"


class App:
    def __init__(self, db: Database, bucket: Bucket):
        self.db = db
        self.bucket = bucket

    def readyz(self) -> tuple[int, dict]:
        body: dict = {"ready": False}
        bucket: dict = {}

        def check_bucket():
            try:
                bucket["bucket"] = self.bucket.check()
            except NotReady as exc:
                bucket["bucket"] = f"error: {exc}"
            except Exception as exc:
                bucket["bucket"] = f"error: {safe_reason(exc)}"

        # In parallel: the probe waits for the slower check, not for their sum.
        worker = threading.Thread(target=check_bucket, daemon=True)
        worker.start()
        try:
            body.update(self.db.run(check_schema))
            body["db"] = "ok"
        except NotReady as exc:
            body["db"] = f"error: {exc}"
        worker.join()
        body.update(bucket)
        body["ready"] = body["db"] == "ok" and not body["bucket"].startswith("error")
        return (200 if body["ready"] else 503), body

    def query(self, params: Mapping[str, list[str]]) -> tuple[int, dict]:
        try:
            vector = parse_vector((params.get("v") or [""])[0])
            k = int((params.get("k") or ["3"])[0])
            if not 1 <= k <= K_MAX:
                raise ValueError(f"k must be between 1 and {K_MAX}")
        except ValueError as exc:
            return 400, {"error": str(exc)}
        try:
            return 200, {"results": self.db.run(lambda c: nearest(c, vector, k))}
        except NotReady as exc:
            return 503, {"error": str(exc)}

    def handle(self, path: str, query: str) -> tuple[int, dict]:
        if path == "/healthz":
            return 200, {"status": "ok"}
        if path == "/readyz":
            return self.readyz()
        if path == "/query":
            return self.query(parse_qs(query))
        return 404, {"error": "not found"}


def make_handler(app: App):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ragsandbox"
        sys_version = ""

        def do_GET(self):  # noqa: N802 (http.server naming)
            url = urlsplit(self.path)
            try:
                status, body = app.handle(url.path, url.query)
            except Exception as exc:  # never a traceback to the client
                status, body = 500, {"error": type(exc).__name__}
            payload = json.dumps(body, sort_keys=True).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            if status != 200 or url.path == "/query":
                sys.stderr.write(f"{self.command} {url.path} {status} {json.dumps(body, sort_keys=True)}\n")

        def log_message(self, format, *args):  # access log handled above
            pass

    return Handler


def app_from_env(env: Mapping[str, str]) -> App:
    secret_id = env.get("DB_SECRET_ID")
    if not secret_id:
        raise ConfigError("DB_SECRET_ID is not set")
    check = env.get("BUCKET_CHECK", "on")
    if check not in ("on", "off"):
        raise ConfigError("BUCKET_CHECK must be on or off")
    bucket = env.get("S3_BUCKET") or None
    if check == "on" and not bucket:
        raise ConfigError("S3_BUCKET is not set (BUCKET_CHECK=off is for the kind lab only)")
    endpoint = endpoint_from_env(env)
    db = Database(
        endpoint,
        store_from_env(env),
        secret_id,
        reload_seconds=float(env.get("SECRET_RELOAD_SECONDS", "5")),
    )
    return App(db, Bucket(bucket if check == "on" else None))


def run(app: App, port: int) -> int:
    server = ThreadingHTTPServer(("0.0.0.0", port), make_handler(app))
    server.daemon_threads = True

    def stop(signum, frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    sys.stderr.write(
        f"ragsandbox serve: port {port}, secret {app.db.secret_id}, "
        f"bucket {app.bucket.name or 'check off (lab)'}, tls {app.db.endpoint.sslmode}\n"
    )
    try:
        server.serve_forever()
    finally:
        server.server_close()
        app.db.close()
    return 0
