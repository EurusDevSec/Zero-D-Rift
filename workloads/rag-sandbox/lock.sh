#!/usr/bin/env bash
# Regenerate requirements.txt and requirements-dev.txt with hashes for every
# package in the tree, inside the pinned Python image (nothing installed on the
# workstation). Review the diff before committing.
#   bash workloads/rag-sandbox/lock.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1
PY=python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90
PIP_TOOLS=pip-tools==7.7.0
here="$(cd "$(dirname "$0")" && pwd)"
src="$(cygpath -w "$here" 2>/dev/null || echo "$here")"
docker run --rm -v "$src:/src" -w /src -e PIP_DISABLE_PIP_VERSION_CHECK=1 "$PY" sh -c "
  pip install -q --root-user-action=ignore $PIP_TOOLS &&
  opts='--quiet --generate-hashes --allow-unsafe --strip-extras --no-emit-index-url' &&
  pip-compile \$opts --output-file requirements.txt requirements.in &&
  pip-compile \$opts --output-file requirements-dev.txt requirements-dev.in"
