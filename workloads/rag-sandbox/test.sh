#!/usr/bin/env bash
# Run the ragsandbox tests in the pinned Python image; nothing is installed on
# the workstation. With --integration, also start the pinned pgvector image on a
# private Docker network and run the PostgreSQL tests against it.
#   bash workloads/rag-sandbox/test.sh [--integration]
set -euo pipefail
export MSYS_NO_PATHCONV=1
PY=python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90
PG=pgvector/pgvector:0.8.2-pg17@sha256:feb68f4f15446397d8cac7f4fe48fe4586de83160d1fc48b46283312d1a33966
here="$(cd "$(dirname "$0")" && pwd)"
src="$(cygpath -w "$here" 2>/dev/null || echo "$here")"
run=(docker run --rm -v "$src:/src:ro" -w /src -e PIP_DISABLE_PIP_VERSION_CHECK=1 -e PYTHONDONTWRITEBYTECODE=1)
cmd='pip install -q --root-user-action=ignore -r requirements-dev.txt && python -m pytest -q -p no:cacheprovider'

if [[ "${1:-}" != "--integration" ]]; then
  "${run[@]}" "$PY" sh -c "$cmd"
  exit
fi

net=zdr-ragsandbox-test db=zdr-ragsandbox-pg
pw="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
trap 'docker rm -f "$db" >/dev/null 2>&1; docker network rm "$net" >/dev/null 2>&1' EXIT
docker network create "$net" >/dev/null
docker run -d --rm --name "$db" --network "$net" -e POSTGRES_PASSWORD="$pw" "$PG" >/dev/null
for _ in $(seq 1 30); do docker exec "$db" pg_isready -U postgres -q && break; sleep 1; done
"${run[@]}" --network "$net" -e RAG_TEST_PG_HOST="$db" -e RAG_TEST_PG_PASSWORD="$pw" "$PY" sh -c "$cmd"
