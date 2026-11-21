#!/usr/bin/env bash
# Negative test for window.sh cleanup (Codex review C1, DRF-57): the cleanup Job
# drops a sandbox's schema, role and secret, so it may start only when the read of
# the request succeeded and returned NotFound. A stub kubectl plays each answer;
# the test fails if any case other than NotFound reaches "kubectl apply".
# Run from the repository root: bash infra/p4-window/tests/cleanup_guard.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/kubectl" <<'STUBEOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
case "$*" in
  *"get ragsandbox"*)
    case "$CASE" in
      exists)    echo "ragsandbox.kro.run/retry"; exit 0 ;;
      notfound)  echo 'Error from server (NotFound): ragsandboxes.kro.run "retry" not found' >&2; exit 1 ;;
      forbidden) echo 'Error from server (Forbidden): ragsandboxes.kro.run "retry" is forbidden' >&2; exit 1 ;;
      timeout)   echo 'Unable to connect to the server: dial tcp: i/o timeout' >&2; exit 1 ;;
      nocrd)     echo 'error: the server does not have a resource type "ragsandbox"' >&2; exit 1 ;;
    esac ;;
  *"get job"*) echo "Complete"; exit 0 ;;
  *"logs"*) echo '{"command": "cleanup"}'; exit 0 ;;
  apply*) cat >/dev/null; exit 0 ;;
  *) exit 0 ;;
esac
STUBEOF
chmod +x "$STUB/kubectl"
fail=0
check() { # case, expect_apply (yes/no)
  local log="$STUB/log.$1"; : > "$log"
  CASE=$1 STUB_LOG="$log" PATH="$STUB:$PATH" LAB=1 RUN_ID=P4-L3-20261121-01 EXPIRES_AT=2026-11-21T13:15:00Z \
    timeout 30 bash "$ROOT/infra/p4-window/window.sh" cleanup tenant-b retry </dev/null >/dev/null 2>&1
  local applied=no; grep -q '^apply' "$log" && applied=yes
  if [[ "$applied" == "$2" ]]; then echo "PASS  $1: cleanup Job applied=$applied"; else echo "FAIL  $1: cleanup Job applied=$applied, expected $2"; fail=1; fi
}
check exists no
check forbidden no
check timeout no
check nocrd no
check notfound yes
[[ $fail -eq 0 ]] && echo "RESULT: PASS" || { echo "RESULT: FAIL"; exit 1; }
