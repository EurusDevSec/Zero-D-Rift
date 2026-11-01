#!/usr/bin/env bash
# Print NOOP and exit 0 only when the Terraform plan has no changes.
# Usage: ./noop-check.sh [extra plan args, e.g. -var kubernetes_version=1.36]
set -euo pipefail

rc=0
terraform plan -detailed-exitcode -input=false "$@" > /dev/null || rc=$?

case "$rc" in
    0) echo "NOOP" ;;
    2) echo "DRIFT" ;;
    *) echo "ERROR (terraform exit $rc)" ;;
esac
exit "$rc"
