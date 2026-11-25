#!/usr/bin/env bash
# Run the batchtraining unit tests (in-memory SQS and S3 fakes) in the pinned
# Python image; nothing is installed on the workstation.
#   bash workloads/batch-training/test.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1
PY=python:3.12-slim@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b
here="$(cd "$(dirname "$0")" && pwd)"
src="$(cygpath -w "$here" 2>/dev/null || echo "$here")"
docker run --rm -v "$src:/src:ro" -w /src -e PIP_DISABLE_PIP_VERSION_CHECK=1 -e PYTHONDONTWRITEBYTECODE=1 "$PY"   sh -c 'pip install -q --root-user-action=ignore -r requirements-dev.txt && python -m pytest -q -p no:cacheprovider'
