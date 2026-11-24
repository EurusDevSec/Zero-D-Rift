#!/usr/bin/env bash
# L1 gate (SPEC-P5 P5-T2.2 A, L1 in §8): run the kyverno test cases in
# gitops/tests/kyverno/ with the pinned kyverno-cli v1.20.0 image, the same
# digest the chart uses (docs/evidence/p5/P5-T1_PINS_20261122.md).
# Then a self-test: one expected result is flipped in a copy, and the run must
# fail, so a CLI that passes everything cannot turn this gate green.
# Needs Docker. No network inside the container, the repo is mounted read-only.
# Usage: bash gitops/tests/kyverno_test.sh
set -euo pipefail

IMG="reg.kyverno.io/kyverno/kyverno-cli@sha256:bd2b8b7c9d550ecf04e0bacaf351adce2f82ce67fd3f291075edcee7f8ab4ab4"
cd "$(dirname "$0")/.."   # gitops/

# run DIR: prints the CLI summary, returns 0 only on "N passed and 0 failed", N >= 1.
run() {
  local src out rc summary
  src="$(cd "$1" && { pwd -W 2>/dev/null || pwd; })"   # Git Bash needs the Windows path for -v
  out="$(MSYS_NO_PATHCONV=1 docker run --rm --network none -v "$src:/g:ro" -w /g/tests/kyverno "$IMG" test . 2>&1)" && rc=0 || rc=$?
  summary="$(printf '%s\n' "$out" | grep -E '^Test Summary: ' | tail -n 1 || true)"
  echo "exit $rc: ${summary:-no summary}"
  if [[ $rc -eq 0 && "$summary" =~ ^Test\ Summary:\ [1-9][0-9]*\ tests\ passed\ and\ 0\ tests\ failed$ ]]; then
    return 0
  fi
  printf '%s\n' "$out" | tail -n 40
  return 1
}

echo "== kyverno test (gitops/tests/kyverno)"
run . || { echo "FAIL kyverno test"; exit 1; }

echo "== self-test: one flipped expectation must fail"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/platform" "$tmp/tests"
cp -R platform/policies "$tmp/platform/"
cp -R tests/kyverno "$tmp/tests/"
f="$tmp/tests/kyverno/kyverno-test.yaml"
n="$(grep -c '^  result: pass$' "$f" || true)"
[[ "$n" -ge 1 ]] || { echo "FAIL self-test: no 'result: pass' to flip"; exit 1; }
sed -i '0,/^  result: pass$/s//  result: fail/' "$f"
# mktemp -d is 0700; the CLI image runs as a non-root user and must read the copy.
chmod -R a+rX "$tmp"
r=0; s="$(run "$tmp")" || r=$?
first="${s%%$'\n'*}"
echo "$first"
if [[ $r -eq 0 ]]; then
  echo "FAIL self-test: flipped expectation still passed"
  exit 1
fi
# The run must fail because of the flipped case, not because it could not run.
if [[ ! "$first" =~ tests\ passed\ and\ [1-9][0-9]*\ tests\ failed$ ]]; then
  printf '%s\n' "$s"
  echo "FAIL self-test: the flipped run did not report failed cases"
  exit 1
fi
echo "PASS kyverno test and self-test"
