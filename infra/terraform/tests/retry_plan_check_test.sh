#!/usr/bin/env bash
# Offline tests for scripts/retry_plan_check.sh (H8, Codex 27/11 finding 1).
# Synthetic `terraform show -json` plans: a full plan, a good retry that only
# creates the missing access entry, and mutations that must each be refused.
# Usage, from infra/terraform: bash tests/retry_plan_check_test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

P=registry.terraform.io/hashicorp/aws
jq -n --arg p "$P" '{
  format_version: "1.2",
  variables: {run_id: {value: "P6-L3-TEST-01"}, system_node_desired_size: {value: 2}},
  configuration: {root_module: {module_calls: {karpenter: {module: {resources: [
    {address: "aws_eks_access_entry.node", expressions: {
      cluster_name: {references: ["var.access_entry_cluster_name"]},
      principal_arn: {references: ["aws_iam_role.node.arn", "aws_iam_role.node"]},
      type: {constant_value: "EC2_LINUX"}}}]}}}}},
  resource_changes: [
    {address: "module.karpenter[0].aws_iam_role.node", mode: "managed", type: "aws_iam_role", provider_name: $p,
     change: {actions: ["create"], after: {name: "zero-drift-karpenter-node", tags: {Project: "Zero-D-Rift"}},
              after_unknown: {arn: true, id: true}}},
    {address: "module.karpenter[0].aws_iam_role_policy.controller", mode: "managed", type: "aws_iam_role_policy", provider_name: $p,
     change: {actions: ["create"], after: {name: "karpenter-controller", policy: "{\"Statement\":[{\"Action\":\"ec2:CreateFleet\"}]}"},
              after_unknown: {id: true, role: true}}},
    {address: "module.cluster.module.eks.aws_eks_node_group.system", mode: "managed", type: "aws_eks_node_group", provider_name: $p,
     change: {actions: ["create"], after: {instance_types: ["m6i.large"], scaling_config: [{desired_size: 2, max_size: 2}]},
              after_unknown: {id: true, scaling_config: [{min_size: true}]}}},
    {address: "module.karpenter[0].aws_eks_access_entry.node", mode: "managed", type: "aws_eks_access_entry", provider_name: $p,
     change: {actions: ["create"], after: {cluster_name: "zero-drift", type: "EC2_LINUX", tags: {Project: "Zero-D-Rift"}},
              after_unknown: {principal_arn: true, id: true, kubernetes_groups: true}}},
    {address: "data.aws_caller_identity.current", mode: "data", type: "aws_caller_identity", provider_name: $p,
     change: {actions: ["read"], after: {}, after_unknown: {account_id: true}}}
  ]}' > "$tmp/full.json"

# Good retry: everything exists except the access entry, now with a resolved principal.
jq '.resource_changes |= map(
      if .mode == "data" then .
      elif .type == "aws_eks_access_entry" then
        .change.after += {principal_arn: "arn:aws:iam::000000000000:role/zero-drift-karpenter-node", kubernetes_groups: []}
        | .change.after_unknown = {id: true}
      else .change.actions = ["no-op"] | .change.after_unknown = {} end)' "$tmp/full.json" > "$tmp/good.json"

failed=0; n=0
expect() { # NAME pass|fail JQ-MUTATION-OF-good.json
    local name="$1" want="$2" got
    jq "$3" "$tmp/good.json" > "$tmp/case.json"
    if bash scripts/retry_plan_check.sh --json "$tmp/full.json" "$tmp/case.json" > "$tmp/out" 2>&1; then got=pass; else got=fail; fi
    n=$((n + 1))
    reason="$(grep -m1 "^FAIL" "$tmp/out" || true)"
    if [[ "$got" == "$want" && "$reason" == *unreadable* ]]; then got="fail-unreadable"; fi
    if [[ "$got" == "$want" ]]; then echo "ok    $name ($want) ${reason:+-- ${reason#FAIL  }}"; else echo "WRONG $name: got $got, want $want"; sed 's/^/      /' "$tmp/out"; failed=1; fi
}
ae='.resource_changes[] | select(.type == "aws_eks_access_entry")'

expect "retry only the missing access entry"         pass '.'
expect "retry also recreates the identical policy"   pass '(.resource_changes[] | select(.type == "aws_iam_role_policy") | .change) |= (.actions = ["create"] | .after_unknown = {id: true})'
expect "access entry type EC2_LINUX -> STANDARD"     fail "($ae | .change.after.type) = \"STANDARD\""
expect "principal from another reference"            fail '.configuration.root_module.module_calls.karpenter.module.resources[0].expressions.principal_arn.references = ["aws_iam_role.other.arn"]'
expect "cluster name changed"                        fail "($ae | .change.after.cluster_name) = \"other\""
expect "known value became unknown"                  fail "($ae | .change) |= (del(.after.cluster_name) | .after_unknown.cluster_name = true)"
expect "policy recreated with another document"      fail '(.resource_changes[] | select(.type == "aws_iam_role_policy") | .change) |= (.actions = ["create"] | .after.policy = "{\"Statement\":[{\"Action\":\"iam:*\"}]}")'
expect "node group recreated with a bigger type"     fail '(.resource_changes[] | select(.type == "aws_eks_node_group") | .change) |= (.actions = ["create"] | .after.instance_types = ["m6i.xlarge"])'
ng='.resource_changes[] | select(.type == "aws_eks_node_group") | .change'
# Codex 27/11 round 2: growing or shrinking a known array or object must be refused.
expect "node group gains an instance type element"   fail "($ng) |= (.actions = [\"create\"] | .after.instance_types += [\"m6i.xlarge\"])"
expect "node group loses its instance type element"  fail "($ng) |= (.actions = [\"create\"] | .after.instance_types = [])"
expect "node group gains a scaling_config block"     fail "($ng) |= (.actions = [\"create\"] | .after.scaling_config += [{desired_size: 2, max_size: 2}])"
expect "access entry gains a tag key"                fail "($ae | .change.after.tags) += {Extra: \"yes\"}"
expect "access entry loses a tag key"                fail "($ae | .change.after.tags) |= del(.Project)"
expect "access entry gains a new top-level key"      fail "($ae | .change.after) += {user_name: \"someone\"}"
expect "node group resolves a nested unknown"        pass "($ng) |= (.actions = [\"create\"] | .after.scaling_config[0].min_size = 1)"
expect "input variable changed (node count)"        fail '.variables.system_node_desired_size.value = 3'
expect "update of an existing role"                  fail '(.resource_changes[] | select(.type == "aws_iam_role") | .change.actions) = ["update"]'
expect "delete of an existing role"                  fail '(.resource_changes[] | select(.type == "aws_iam_role") | .change.actions) = ["delete"]'
expect "replacement of the node group"               fail '(.resource_changes[] | select(.type == "aws_eks_node_group") | .change.actions) = ["delete", "create"]'
expect "create of an address not in the full plan"   fail '.resource_changes += [{address: "aws_iam_role.extra", mode: "managed", type: "aws_iam_role", provider_name: "registry.terraform.io/hashicorp/aws", change: {actions: ["create"], after: {}, after_unknown: {}}}]'
expect "retry creates nothing"                       fail "($ae | .change.actions) = [\"no-op\"]"
expect "retry is not a plan (empty object)"         fail '{}'

# The output never prints a value, only addresses and paths.
jq "($ae | .change.after.principal_arn) = \"arn:aws:iam::000000000000:role/zero-drift-karpenter-node\" | ($ae | .change.after.type) = \"STANDARD\"
    | ($ae | .change.after.tags) += {Extra: \"tagvalue-x\"} | ($ng) |= (.actions = [\"create\"] | .after.instance_types += [\"m6i.xlarge\"])" "$tmp/good.json" > "$tmp/case.json"
bash scripts/retry_plan_check.sh --json "$tmp/full.json" "$tmp/case.json" > "$tmp/out" 2>&1 || true
n=$((n + 1))
if grep -q -E '000000000000|STANDARD|EC2_LINUX|m6i|tagvalue-x' "$tmp/out"; then echo "WRONG output prints a value"; failed=1; else echo "ok    output prints no value"; fi

echo
if (( failed )); then echo "RESULT: FAIL ($n cases)"; exit 1; fi
echo "RESULT: PASS ($n cases)"
