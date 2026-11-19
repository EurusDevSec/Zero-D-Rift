# RAGSandbox reference workload

One image, several entry points (SPEC-P4 §1, ADR-0008). DRF-45 delivers the
platform commands; `serve` and the published image come in DRF-50.

| Command | Credential | When | Does |
|---|---|---|---|
| `python -m ragsandbox db-init` | master (RDS-managed secret) | once per window | database `rag`, pgvector, role `rag_bootstrap` (CREATEROLE, not superuser), revokes `PUBLIC` defaults, writes the bootstrap secret |
| `python -m ragsandbox bootstrap --tenant T --name N` | bootstrap | per request (Job in `zdr-platform`) | schema and login role `rag_<T>__<N>`, grants on that schema only, writes secret `zero-drift/rag/<T>/<N>`; re-run keeps the password |
| `python -m ragsandbox cleanup --tenant T --name N` | bootstrap | operator-run (D9) | drops schema (with its tables) and role, deletes the secret |

Output is one JSON line without secret values. Exit 2 = invalid input, 1 = other error.

## Environment

| Variable | Meaning | Default |
|---|---|---|
| `DB_HOST`, `DB_PORT` | endpoint from `platform-config` | —, `5432` |
| `DB_SSLMODE`, `DB_SSLROOTCERT` | TLS; `verify-*` needs the RDS CA bundle | `verify-full`, — |
| `SECRET_BACKEND` | `aws` (Secrets Manager via IRSA) or `file` (labs only) | `aws` |
| `SECRET_DIR` | root for `file` | — |
| `SECRET_TAGS` | tags on created secrets, `K=V,K=V` | — |
| `MASTER_SECRET_ID` | master secret (db-init only) | — |
| `BOOTSTRAP_SECRET_ID` | bootstrap secret | `zero-drift/rag/platform/bootstrap` |
| `MASTER_DBNAME` | database db-init connects to first | `postgres` |
| `SANDBOX_TENANT`, `SANDBOX_NAME` | instead of `--tenant`, `--name` | — |

Names: tenant `tenant-a` or `tenant-b`; sandbox name 1–32 chars of `[a-z0-9-]`,
letter first, letter or digit last, no `--` (`src/ragsandbox/names.py`).

## Tests

```bash
bash workloads/rag-sandbox/test.sh                 # unit tests
bash workloads/rag-sandbox/test.sh --integration   # plus PostgreSQL 17 + pgvector in Docker
```

Both run inside the pinned Python image; nothing is installed on the workstation.
Integration needs a superuser master, because pgvector 0.8.2 is not a trusted
extension. On RDS the master is `rds_superuser`.
