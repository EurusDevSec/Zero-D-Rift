#!/usr/bin/env bash
# Regenerate requirements.txt and requirements-dev.txt with hashes for every
# package in the tree, inside the pinned Python image (nothing installed on the
# workstation). Review the diff before committing.
#   bash workloads/batch-training/lock.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1
PY=python:3.12-slim@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b
PIP_TOOLS=pip-tools==7.7.0
here="$(cd "$(dirname "$0")" && pwd)"
src="$(cygpath -w "$here" 2>/dev/null || echo "$here")"
docker run --rm -v "$src:/src" -w /src -e PIP_DISABLE_PIP_VERSION_CHECK=1 "$PY" sh -c "
  pip install -q --root-user-action=ignore $PIP_TOOLS &&
  opts='--quiet --generate-hashes --allow-unsafe --strip-extras --no-emit-index-url' &&
  pip-compile \$opts --output-file requirements.txt requirements.in &&
  pip-compile \$opts --output-file requirements-dev.txt requirements-dev.in"
