# RAGSandbox reference workload

One image, four entry points (SPEC-P4 §1, ADR-0008, D8). DRF-45 built the
platform commands; DRF-50 added `serve`, the image and its publication.

| Command | Credential | When | Does |
|---|---|---|---|
| `python -m ragsandbox db-init` | master (RDS-managed secret) | once per window | database `rag`, pgvector, role `rag_bootstrap` (CREATEROLE, not superuser), revokes `PUBLIC` defaults, writes the bootstrap secret |
| `python -m ragsandbox bootstrap --tenant T --name N` | bootstrap | per request (Job in `zdr-platform`) | schema and login role `rag_<T>__<N>`, grants on that schema only, writes secret `zero-drift/rag/<T>/<N>`; re-run keeps the password |
| `python -m ragsandbox cleanup --tenant T --name N` | bootstrap | operator-run (D9) | drops schema (with its tables) and role, deletes the secret |
| `python -m ragsandbox serve` (image default) | sandbox | the app Deployment | HTTP on `PORT`: `/healthz`, `/readyz`, `/query` |

The platform commands print one JSON line without secret values. Exit 2 =
invalid input or configuration, 1 = other error.

## `serve`

| Path | 200 means | Otherwise |
|---|---|---|
| `/healthz` | the process answers; nothing else is checked | — |
| `/readyz` | the app queried the `vector` column of `documents` in its own schema **and** `HeadBucket` on its bucket passed | 503 with the failing layer, for example `"db": "error: OperationalError: password authentication failed …"` |
| `/query?v=1,0,0,0&k=3` | nearest seeded rows by L2 distance (`<->`); `v` has 4 numbers, `k` 1–10 | 400 bad input, 503 database not usable |

- On each new connection the app creates `documents (id, title, embedding vector(4))`
  in its schema if missing and inserts the 6 seed rows it lacks (advisory lock, so
  replicas do not race). No model call: the caller passes the vector (D8).
- The connection comes from the secret in `DB_SECRET_ID`. While that secret is
  missing, or after an authentication or connection error, the app reads it again
  (at most every `SECRET_RELOAD_SECONDS`) and reconnects, so a rotated password or
  a late bootstrap Job heals without a restart (also needed in P8).
- Connections fail fast on a dead peer (`connect_timeout` 2 s, `tcp_user_timeout`
  3 s, TCP keepalives), so `/readyz` answers within a few seconds during an outage.
  Use a readiness `timeoutSeconds` of at least 8.
- `/healthz`, `/readyz` with 200 are not logged; other responses and every
  `/query` are logged as one line to stderr. No secret value is logged.

## Environment

| Variable | Meaning | Default |
|---|---|---|
| `DB_HOST`, `DB_PORT` | endpoint from `platform-config` | —, `5432` |
| `DB_SSLMODE`, `DB_SSLROOTCERT` | TLS; `verify-*` needs the RDS CA bundle | `verify-full`; the image sets `/opt/rds/us-east-1-bundle.pem` |
| `SECRET_BACKEND` | `aws` (Secrets Manager via IRSA) or `file` (labs only) | `aws` |
| `SECRET_DIR` | root for `file` | — |
| `SECRET_TAGS` | tags on created secrets, `K=V,K=V` | — |
| `MASTER_SECRET_ID` | master secret (db-init only) | — |
| `BOOTSTRAP_SECRET_ID` | bootstrap secret | `zero-drift/rag/platform/bootstrap` |
| `MASTER_DBNAME` | database db-init connects to first | `postgres` |
| `SANDBOX_TENANT`, `SANDBOX_NAME` | instead of `--tenant`, `--name` | — |
| `DB_SECRET_ID` | sandbox secret (`serve`) | — (required) |
| `S3_BUCKET` | sandbox bucket (`serve`) | — (required unless `BUCKET_CHECK=off`) |
| `BUCKET_CHECK` | `on`, or `off` for the kind lab, which has no bucket; `/readyz` then says `"bucket": "skipped"` | `on` |
| `SECRET_RELOAD_SECONDS` | minimum gap between secret reads after a failure | `5` |
| `PORT` | HTTP port | `8080` |

Names: tenant `tenant-a` or `tenant-b`; sandbox name 1–32 chars of `[a-z0-9-]`,
letter first, letter or digit last, no `--` (`src/ragsandbox/names.py`).

## Image

`Dockerfile` (context: this directory):
- base `python:3.13-slim` pinned by digest;
- dependencies from `requirements.txt`, installed with `--require-hashes` and wheels only;
- RDS CA bundle added with `--checksum` (the build fails if AWS rotates the file);
- bytecode compiled at build time, user `10001`, so it runs with a read-only root
  filesystem and no capabilities;
- no secret, credential or endpoint in the image; everything comes from the environment.

Published by `.github/workflows/rag-sandbox-image.yml` to
`ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox` on `main` only. Consumers use the
digest from the run summary (`@sha256:…`), recorded in `docs/VERSION_MATRIX.md` §8.

## Scripts

All run inside pinned images; nothing is installed on the workstation.

```bash
bash workloads/rag-sandbox/test.sh                 # unit tests
bash workloads/rag-sandbox/test.sh --integration   # plus PostgreSQL 17 + pgvector in Docker
bash workloads/rag-sandbox/smoke.sh                # build the image, run it hardened end to end
bash workloads/rag-sandbox/lock.sh                 # regenerate the hashed requirements from *.in
```

Integration and smoke need a superuser master, because pgvector 0.8.2 is not a
trusted extension. On RDS the master is `rds_superuser`.
