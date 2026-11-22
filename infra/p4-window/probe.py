# Window probe (DRF-56, SPEC-P4 §1 "independent verification", §4, P4-T4.1 B-D).
# Runs INSIDE a short-lived Pod of the pinned RAGSandbox image, started by
# window.sh with the ServiceAccount whose identity is under test. It uses the
# image's own secret store and connection helpers, but nothing of `serve`: the
# checks are made from outside the app Pod.
#
#   python -c "$(cat probe.py)" platform                 # SA rag-bootstrap, ns zdr-platform
#   python -c "$(cat probe.py)" sandbox TENANT NAME      # SA rag-NAME, ns TENANT
#   python -c "$(cat probe.py)" cross TENANT NAME OTHER  # SA rag-NAME, ns TENANT, against OTHER
#
# One line per case: PASS/FAIL, the case, what was expected, what was seen. Seen
# values are reduced by errors.safe_reason / aws_error_code, so no ARN, account
# ID, host or secret value is printed. Exit 1 when any case fails.
import json
import os
import socket
import sys
import urllib.error
import urllib.request

from ragsandbox import db
from ragsandbox.errors import aws_error_code, safe_reason
from ragsandbox.names import BOOTSTRAP_SECRET_DEFAULT, DATABASE, parse_sandbox
from ragsandbox.secretstore import store_from_env

ENV = os.environ
FILE_BACKEND = ENV.get("SECRET_BACKEND", "aws") == "file"
BUCKETS = ENV.get("PROBE_BUCKETS", "on") == "on"
BUCKET_PREFIX = "zero-drift-rag-"
failed = []


def report(ok, case, expected, seen):
    print(f"{'PASS' if ok else 'FAIL'}  {case}: expected {expected}; seen {seen}")
    if not ok:
        failed.append(case)


def skip(case, why):
    print(f"SKIP  {case}: {why}")


def store():
    return store_from_env(ENV)


def endpoint():
    return db.endpoint_from_env(ENV)


def usable(cred):
    """A credential counts as read only with a non-empty username and password
    (Codex C2: a secret holding {} must not pass and skip the later checks)."""
    return isinstance(cred, dict) and bool(cred.get("username")) and bool(cred.get("password"))


def seen_cred(cred):
    if cred is None:
        return "not found"
    return "read" if usable(cred) else "no username/password in the secret"


def imds_timed_out(exc):
    """Only the expected outcome counts: the hop limit drops the reply, so the
    request times out. Refused, DNS or other errors are not proof (Codex C2)."""
    if isinstance(exc, (TimeoutError, socket.timeout)):
        return True
    return isinstance(exc, urllib.error.URLError) and isinstance(exc.reason, (TimeoutError, socket.timeout))


def denied_aws(exc):
    code = aws_error_code(exc) or ""
    return code in ("AccessDenied", "AccessDeniedException", "403", "Forbidden")


def expect_secret_denied(case, name):
    """AWS: the identity's policy must refuse the read. File store (kind only):
    the volume of another tenant is not mounted, so the secret is not visible."""
    try:
        value = store().get(name)
    except Exception as exc:  # noqa: BLE001 - classify every failure
        report(denied_aws(exc), case, "AccessDenied", safe_reason(exc))
        return
    if FILE_BACKEND and value is None:
        report(True, case, "not visible (file store, kind)", "not found")
    else:
        report(False, case, "AccessDenied", "secret read" if value else "not found (no denial)")


def expect_sql_denied(case, conn, sql):
    import psycopg

    try:
        with conn.cursor() as cur:
            cur.execute(sql)
        report(False, case, "SQLSTATE 42501", "statement succeeded")
    except psycopg.errors.InsufficientPrivilege as exc:
        report(True, case, "SQLSTATE 42501", safe_reason(exc))
    except Exception as exc:  # noqa: BLE001
        report(False, case, "SQLSTATE 42501", safe_reason(exc))
    finally:
        conn.rollback()


def s3():
    import boto3
    from botocore.config import Config

    return boto3.client(
        "s3", config=Config(connect_timeout=3, read_timeout=3, retries={"max_attempts": 1})
    )


def http_get(url):
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode() or "{}")
    except Exception as exc:  # noqa: BLE001
        return None, {"error": safe_reason(exc)}


def platform():
    """Shared service, seen with the bootstrap identity (SA rag-bootstrap)."""
    try:
        cred = store().get(ENV.get("BOOTSTRAP_SECRET_ID", BOOTSTRAP_SECRET_DEFAULT))
    except Exception as exc:  # noqa: BLE001
        report(False, "bootstrap secret readable", "a credential", safe_reason(exc))
        return
    report(usable(cred), "bootstrap secret readable", "a credential", seen_cred(cred))
    if not usable(cred):
        return
    with db.connect(endpoint(), cred, DATABASE) as conn, conn.cursor() as cur:
        cur.execute("select ssl, version from pg_stat_ssl where pid = pg_backend_pid()")
        ssl, version = cur.fetchone()
        want_ssl = ENV.get("DB_SSLMODE", "verify-full") != "disable"
        report(ssl == want_ssl, "TLS on the connection", f"ssl={want_ssl}", f"ssl={ssl} {version or ''}".strip())
        cur.execute("select extversion from pg_extension where extname = 'vector'")
        row = cur.fetchone()
        report(row == ("0.8.2",), "pgvector installed by db-init", "0.8.2", row[0] if row else "absent")
        cur.execute(
            "select rolsuper, rolcreaterole, rolcreatedb, rolbypassrls, rolreplication"
            " from pg_roles where rolname = current_user"
        )
        sup, crole, cdb, bypass, repl = cur.fetchone()
        report(
            (sup, crole, cdb, bypass, repl) == (False, True, False, False, False),
            "rag_bootstrap attributes",
            "CREATEROLE only, not superuser",
            f"super={sup} createrole={crole} createdb={cdb} bypassrls={bypass} replication={repl}",
        )
        # Codex C9: bootstrap may pass on CONNECT to sandbox roles, but only use CREATE.
        cur.execute(
            "select has_database_privilege(current_user, current_database(), 'CONNECT WITH GRANT OPTION'),"
            " has_database_privilege(current_user, current_database(), 'CREATE'),"
            " has_database_privilege(current_user, current_database(), 'CREATE WITH GRANT OPTION')"
        )
        conn_go, create, create_go = cur.fetchone()
        report(
            (conn_go, create, create_go) == (True, True, False),
            "rag_bootstrap database grants",
            "CONNECT with grant option, CREATE without",
            f"connect_grant_option={conn_go} create={create} create_grant_option={create_go}",
        )
    master = ENV.get("MASTER_SECRET_ID")
    if master:
        expect_secret_denied("bootstrap identity cannot read the master secret", master)
    else:
        skip("bootstrap identity cannot read the master secret", "MASTER_SECRET_ID not given (kind)")


def sandbox(tenant, name):
    """Independent check of one sandbox, with its own identity (SA rag-NAME)."""
    sb = parse_sandbox(tenant, name)
    try:
        cred = store().get(sb.secret_name)
    except Exception as exc:  # noqa: BLE001
        report(False, "own secret readable", "a credential", safe_reason(exc))
        return
    report(usable(cred), "own secret readable", "a credential", seen_cred(cred))
    if not usable(cred):
        return
    with db.connect(endpoint(), cred, DATABASE) as conn, conn.cursor() as cur:
        cur.execute(f'select count(*) from "{sb.schema}".documents')
        n = cur.fetchone()[0]
        report(n >= 6, "own schema queried", ">= 6 seeded rows", f"{n} rows")
        cur.execute(
            f"select id from \"{sb.schema}\".documents order by embedding <-> '[1,0,0,0]' limit 1"
        )
        top = cur.fetchone()
        report(top == (1,), "vector query in own schema", "nearest id 1", f"id {top[0] if top else None}")
    bucket = f"{BUCKET_PREFIX}{tenant}-{name}"
    if BUCKETS:
        try:
            s3().head_bucket(Bucket=bucket)
            report(True, "own bucket reachable (HeadBucket)", "200", "200")
        except Exception as exc:  # noqa: BLE001
            report(False, "own bucket reachable (HeadBucket)", "200", safe_reason(exc))
    else:
        skip("own bucket reachable (HeadBucket)", "no bucket on kind")
    base = f"http://rag-{name}.{tenant}.svc:8080"
    code, body = http_get(base + "/readyz")
    report(code == 200 and body.get("ready") is True, "app /readyz through the Service", "200 ready", f"{code} {body}")
    code, body = http_get(base + "/query?v=1,0,0,0&k=2")
    ids = [r.get("id") for r in body.get("results", [])]
    report(code == 200 and ids[:1] == [1], "app /query through the Service", "200, first id 1", f"{code} ids={ids}")


def cross(tenant, name, other):
    """Negatives for the identity of TENANT/NAME (SA rag-NAME in TENANT)."""
    own = parse_sandbox(tenant, name)
    theirs = parse_sandbox(other, name)
    expect_secret_denied(f"{tenant} reads {other}'s secret", theirs.secret_name)
    expect_secret_denied(f"{tenant} reads the bootstrap secret", BOOTSTRAP_SECRET_DEFAULT)
    if BUCKETS:
        try:
            s3().head_bucket(Bucket=f"{BUCKET_PREFIX}{other}-{name}")
            report(False, f"{tenant} reaches {other}'s bucket", "403", "200")
        except Exception as exc:  # noqa: BLE001
            report(denied_aws(exc), f"{tenant} reaches {other}'s bucket", "403", safe_reason(exc))
    else:
        skip(f"{tenant} reaches {other}'s bucket", "no bucket on kind")
    cred = store().get(own.secret_name)
    if not usable(cred):
        report(False, "own secret for the SQL cases", "a credential", seen_cred(cred))
    else:
        with db.connect(endpoint(), cred, DATABASE) as conn:
            expect_sql_denied(f"{tenant} reads {other}'s schema", conn, f'select 1 from "{theirs.schema}".documents limit 1')
            expect_sql_denied(f"{tenant} sandbox role runs CREATE ROLE", conn, "create role zdr_probe_should_fail")
            expect_sql_denied(f"{tenant} sandbox role creates a schema", conn, "create schema zdr_probe_should_fail")
    # IMDSv2: the node's hop limit 1 drops the reply to a Pod, so no token.
    req = urllib.request.Request(
        "http://169.254.169.254/latest/api/token",
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as r:
            report(False, f"{tenant} Pod gets an IMDS token", "no token", f"HTTP {r.status}")
    except urllib.error.HTTPError as exc:  # IMDS answered: the hop limit did not hold
        report(False, f"{tenant} Pod gets an IMDS token", "no answer", f"HTTP {exc.code}")
    except Exception as exc:  # noqa: BLE001
        report(imds_timed_out(exc), f"{tenant} Pod gets an IMDS token", "no token (timeout)", safe_reason(exc))


def main(argv):
    cmd, args = (argv[0], argv[1:]) if argv else ("", [])
    if cmd == "platform" and not args:
        platform()
    elif cmd == "sandbox" and len(args) == 2:
        sandbox(*args)
    elif cmd == "cross" and len(args) == 3:
        cross(*args)
    else:
        print("usage: probe.py platform | sandbox TENANT NAME | cross TENANT NAME OTHER", file=sys.stderr)
        return 2
    print(f"RESULT: {'FAIL' if failed else 'PASS'} ({len(failed)} failed)")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:  # noqa: BLE001 - never print a raw message
        print(f"FAIL  probe error: {safe_reason(exc)}")
        sys.exit(1)
