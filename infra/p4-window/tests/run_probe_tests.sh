#!/usr/bin/env bash
# Run infra/p4-window/tests/test_probe.py in the pinned Python image of
# workloads/rag-sandbox/test.sh; nothing is installed on the workstation.
set -euo pipefail
export MSYS_NO_PATHCONV=1
PY=python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90
root="$(cd "$(dirname "$0")/../../.." && pwd)"
src="$(cygpath -w "$root" 2>/dev/null || echo "$root")"
docker run --rm -v "$src:/src:ro" -w /src -e PIP_DISABLE_PIP_VERSION_CHECK=1 -e PYTHONDONTWRITEBYTECODE=1 "$PY" \
  sh -c 'pip install -q --root-user-action=ignore -r workloads/rag-sandbox/requirements-dev.txt && python -m pytest -q -p no:cacheprovider infra/p4-window/tests/test_probe.py'
