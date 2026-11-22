#!/usr/bin/env bash
# Negative test for window.sh cleanup (Codex review C1, DRF-57): the cleanup Job
# drops a sandbox's schema, role and secret, so it may start only when the read of
# the request succeeded and returned NotFound. A stub kubectl plays each answer;
# the test fails if any case other than NotFound reaches "kubectl apply".
# Cases "apinotfound" and "othername" (PR #58 review): a NotFound that does not
# name this request (stale discovery, another object) is not "gone".
# Case "reappear" (PR #55 review): NotFound before the Job, the request back after
# it (Git merge and Argo sync meanwhile). Cleanup must then exit non-zero with the
# recovery hint.
# Cases "after-forbidden" and "after-timeout" (Codex re-review 22/11): NotFound
# before the Job, then the read after it fails. Cleanup must not report success.
# Run from the repository root: bash infra/p4-window/tests/cleanup_guard.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WINDOW="${WINDOW_SH:-$ROOT/infra/p4-window/window.sh}"
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
      apinotfound) echo 'Error from server (NotFound): the server could not find the requested resource' >&2; exit 1 ;;
      othername) echo 'Error from server (NotFound): ragsandboxes.kro.run "other" not found' >&2; exit 1 ;;
      reappear)
        if grep -q '^apply' "$STUB_LOG"; then echo "ragsandbox.kro.run/retry"; exit 0; fi
        echo 'Error from server (NotFound): ragsandboxes.kro.run "retry" not found' >&2; exit 1 ;;
      after-forbidden)
        if grep -q '^apply' "$STUB_LOG"; then echo 'Error from server (Forbidden): ragsandboxes.kro.run "retry" is forbidden' >&2; exit 1; fi
        echo 'Error from server (NotFound): ragsandboxes.kro.run "retry" not found' >&2; exit 1 ;;
      after-timeout)
        if grep -q '^apply' "$STUB_LOG"; then echo 'Unable to connect to the server: dial tcp: i/o timeout' >&2; exit 1; fi
        echo 'Error from server (NotFound): ragsandboxes.kro.run "retry" not found' >&2; exit 1 ;;
    esac ;;
  *"get job"*) echo "Complete"; exit 0 ;;
  *"logs"*) echo '{"command": "cleanup"}'; exit 0 ;;
  apply*) cat >/dev/null; exit 0 ;;
  *) exit 0 ;;
esac
STUBEOF
chmod +x "$STUB/kubectl"
fail=0
check() { # case, expect_apply (yes/no), expect_exit (0/nonzero, optional), message for nonzero
  local log="$STUB/log.$1" err rc; : > "$log"
  err="$(CASE=$1 STUB_LOG="$log" PATH="$STUB:$PATH" LAB=1 RUN_ID=P4-L3-20261121-01 EXPIRES_AT=2026-11-21T13:15:00Z \
    timeout 30 bash "$WINDOW" cleanup tenant-b retry </dev/null 2>&1)"; rc=$?
  local applied=no; grep -q '^apply' "$log" && applied=yes
  if [[ "$applied" == "$2" ]]; then echo "PASS  $1: cleanup Job applied=$applied"; else echo "FAIL  $1: cleanup Job applied=$applied, expected $2"; fail=1; fi
  case "${3:-}" in
    0) [[ $rc -eq 0 ]] && echo "PASS  $1: exit 0" || { echo "FAIL  $1: exit $rc, expected 0"; fail=1; } ;;
    nonzero)
      local want="${4:-reappeared}"
      if [[ $rc -ne 0 ]] && grep -q "$want" <<<"$err"; then echo "PASS  $1: exit $rc, message '$want' shown"
      else echo "FAIL  $1: exit $rc, expected non-zero with '$want'"; fail=1; fi ;;
  esac
}
check exists no
check forbidden no
check timeout no
check nocrd no
check apinotfound no
check othername no
check notfound yes 0
check reappear yes nonzero
check after-forbidden yes nonzero 'cannot confirm request tenant-b/retry is still gone'
check after-timeout yes nonzero 'cannot confirm request tenant-b/retry is still gone'
[[ $fail -eq 0 ]] && echo "RESULT: PASS" || { echo "RESULT: FAIL"; exit 1; }
