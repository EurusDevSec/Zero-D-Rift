#!/usr/bin/env bash
# Static gate for infra/terraform (SPEC-P2 Task 3). Touches no AWS and no backend.
# Usage: infra/terraform/scripts/check.sh   (from anywhere in the repo)
# Exit 0 only when every check passes. Run init -backend=false once before it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(git -C "$root" rev-parse --show-toplevel)"
cd "$root"

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }

# 1. Exact CLI pin.
version="$(terraform version -json | jq -r '.terraform_version')"
[[ "$version" == "1.16.4" ]] && pass "terraform CLI 1.16.4" || fail "terraform CLI is $version, expected 1.16.4"

# 2. Formatting.
terraform fmt -check -recursive > /dev/null && pass "fmt -check" || fail "fmt -check (run: terraform fmt -recursive)"

# 3. Validate. Needs a backend-free init; the lockfile must already match.
if [[ ! -d .terraform ]]; then
    fail "validate skipped: run 'terraform init -backend=false -lockfile=readonly' first"
elif terraform validate -no-color > /dev/null; then
    pass "validate"
else
    fail "validate"
fi

# 3b. Guardrail contract tests (mock AWS provider, no credentials used).
if [[ -d .terraform ]]; then
    terraform test -no-color > /dev/null 2>&1 && pass "terraform test (guardrails, mocked AWS)" || fail "terraform test (run it directly to see why)"
fi

# 4. Provider lockfile exists and pins exactly the approved builds.
expected="aws=6.67.0 cloudinit=2.4.1 null=3.3.2 time=0.14.2 tls=4.4.1"
if [[ -f .terraform.lock.hcl ]]; then
    locked="$(grep -A1 '^provider "registry.terraform.io/hashicorp/' .terraform.lock.hcl \
        | sed -nE 's#^provider "registry.terraform.io/hashicorp/([a-z]+)".*#\1#p; s#^ *version *= *"([^"]+)".*#\1#p' \
        | paste -d= - - | sort | tr '\n' ' ' | sed 's/ $//')"
    [[ "$locked" == "$expected" ]] && pass "lockfile pins: $locked" || fail "lockfile pins '$locked', expected '$expected'"
else
    fail "missing .terraform.lock.hcl"
fi

# 5. Module calls use only approved exact versions.
bad_modules="$(grep -rhn --include='*.tf' -A1 'source *= *"terraform-aws-modules/' . \
    | grep -E 'version *=' \
    | grep -v -E '"(= )?(6\.7\.3|21\.26\.0|4\.0\.0)"' || true)"
[[ -z "$bad_modules" ]] && pass "module version pins" || fail "unapproved module version: $bad_modules"

# 6. No state, plan, private backend config, tfvars or provider cache tracked or unignored.
leaks="$(git -C "$repo" ls-files --cached --others --exclude-standard -- infra/terraform \
    | grep -E '(\.tfstate|\.tfplan$|/tfplan$|/\.terraform/|/backend\.hcl$|\.tfvars(\.json)?$|crash.*\.log$)' || true)"
[[ -z "$leaks" ]] && pass "no state/plan/backend.hcl/tfvars visible to Git" || fail "visible to Git: $leaks"

# 7. Sensitive patterns in files Git would see: AWS keys, account IDs, ARNs with
#    an account, private keys, secret assignments. This script holds the patterns,
#    so it is excluded from its own scan.
pattern='(AKIA|ASIA)[A-Z0-9]{16}|arn:aws[a-z-]*:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}|(^|[^0-9A-Za-z])[0-9]{12}([^0-9A-Za-z]|$)|BEGIN [A-Z ]*PRIVATE KEY|aws_secret_access_key|aws_session_token'
hits="$(git -C "$repo" ls-files --cached --others --exclude-standard -z -- infra/terraform ':!infra/terraform/scripts/check.sh' \
    | (cd "$repo" && xargs -0 grep -n -I -E "$pattern" -- 2>/dev/null) || true)"
[[ -z "$hits" ]] && pass "no AWS key/account ID/private key patterns" || fail "sensitive pattern: $hits"

echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (static only; proves nothing about AWS)"
