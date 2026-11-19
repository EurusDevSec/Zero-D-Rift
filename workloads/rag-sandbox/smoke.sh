#!/usr/bin/env bash
# Build the image and run it the way the cluster will: non-root, read-only root
# filesystem, no capabilities, against the pinned pgvector image. Secrets are lab
# files on a Docker volume (SECRET_BACKEND=file); no AWS, no TLS, bucket check off.
#   bash workloads/rag-sandbox/smoke.sh [image]     (default: build ragsandbox:smoke)
# Everything it starts is removed on exit.
set -euo pipefail
export MSYS_NO_PATHCONV=1
PG=pgvector/pgvector:0.8.2-pg17@sha256:feb68f4f15446397d8cac7f4fe48fe4586de83160d1fc48b46283312d1a33966
here="$(cd "$(dirname "$0")" && pwd)"
ctx="$(cygpath -w "$here" 2>/dev/null || echo "$here")"
img="${1:-}"
if [[ -z "$img" ]]; then
  img=ragsandbox:smoke
  docker build --load -q -t "$img" "$ctx" >/dev/null
fi
net=zdr-smoke db=zdr-smoke-pg app=zdr-smoke-app vol=zdr-smoke-secrets
cleanup() { docker rm -f "$app" "$db" >/dev/null 2>&1 || true; docker volume rm "$vol" >/dev/null 2>&1 || true; docker network rm "$net" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
pw="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
docker network create "$net" >/dev/null
docker volume create "$vol" >/dev/null
docker run -d --name "$db" --network "$net" -e POSTGRES_PASSWORD="$pw" "$PG" >/dev/null
for _ in $(seq 1 30); do docker exec "$db" pg_isready -U postgres -q && break; sleep 1; done

# Lab master secret, owned by the image user. Value is passed on stdin, not argv.
printf '{"username":"postgres","password":"%s"}' "$pw" | docker run --rm -i -v "$vol:/s" --user 0 --entrypoint sh "$img" -c \
  'mkdir -p /s/lab && cat > /s/lab/master.json && chown -R 10001:10001 /s && chmod 0600 /s/lab/master.json'

hardened=(--network "$net" --read-only --cap-drop ALL --security-opt no-new-privileges -v "$vol:/secrets"
  -e SECRET_BACKEND=file -e SECRET_DIR=/secrets -e DB_HOST="$db" -e DB_SSLMODE=disable)
step() { echo "== $*"; }

step "user and root filesystem"
docker run --rm "${hardened[@]}" --entrypoint sh "$img" -c 'id -u; touch /probe 2>&1 | sed "s/^/  /" || true'
step "RDS CA bundle readable by the image user"
docker run --rm "${hardened[@]}" --entrypoint sh "$img" -c 'sha256sum "$DB_SSLROOTCERT"; grep -c "BEGIN CERTIFICATE" "$DB_SSLROOTCERT"'
step db-init
docker run --rm "${hardened[@]}" -e MASTER_SECRET_ID=lab/master "$img" db-init
step bootstrap
docker run --rm "${hardened[@]}" "$img" bootstrap --tenant tenant-a --name s1
step "serve (BUCKET_CHECK=off)"
docker run -d --name "$app" "${hardened[@]}" -e DB_SECRET_ID=zero-drift/rag/tenant-a/s1 -e BUCKET_CHECK=off "$img" >/dev/null

get() {
  docker run --rm --network "$net" --entrypoint python "$img" -c '
import sys, urllib.request, urllib.error
try:
    r = urllib.request.urlopen("http://'"$app"':8080" + sys.argv[1], timeout=10); print(r.status, r.read().decode())
except urllib.error.HTTPError as e:
    print(e.code, e.read().decode())
except OSError as e:
    print("down", type(e).__name__)' "$1"
}
for _ in $(seq 1 20); do [[ "$(get /healthz)" == 200* ]] && break; sleep 1; done
for path in /healthz /readyz "/query?v=1,0,0,0&k=2" "/query?v=1"; do echo "GET $path -> $(get "$path")"; done
step "serve log"
docker logs "$app" 2>&1 | sed 's/^/  /'
step "secret values in log?"
if docker logs "$app" 2>&1 | grep -qF "$pw"; then echo "  FAIL: master password in log"; exit 1; else echo "  none"; fi

step "database stopped: readyz must fail, healthz must not"
docker stop -t 5 "$db" >/dev/null
echo "GET /healthz -> $(get /healthz)"
echo "GET /readyz -> $(get /readyz)"
step "database back: app reconnects by itself"
docker start "$db" >/dev/null
for _ in $(seq 1 30); do docker exec "$db" pg_isready -U postgres -q && break; sleep 1; done
for _ in $(seq 1 10); do r="$(get /readyz)"; [[ "$r" == 200* ]] && break; sleep 2; done
echo "GET /readyz -> $r"
[[ "$r" == 200* ]] || { echo "FAIL: app did not recover"; exit 1; }
echo "SMOKE PASS"
