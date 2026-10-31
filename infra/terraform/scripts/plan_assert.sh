#!/usr/bin/env bash
# Plan gate for the P2 network (DRF-8, ADR-0006). Reads a saved plan; changes nothing.
# Usage, from infra/terraform after: terraform plan -var-file=run.tfvars -out=tfplan
#   ./scripts/plan_assert.sh tfplan
# The plan JSON stays in a pipe: it is never written to disk or printed.
set -euo pipefail

plan="${1:?usage: plan_assert.sh <saved-plan-file>}"
# A .json argument is read as plan JSON directly (used to test this script).
if [[ "$plan" == *.json ]]; then json="$(cat "$plan")"; else json="$(terraform show -json "$plan")"; fi

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }
q() { jq -r "$1" <<< "$json"; }
count() { q "[.resource_changes[] | select(.type == \"$1\")] | length"; }

# 1. First plan only creates; nothing is updated, replaced or destroyed.
other="$(q '[.resource_changes[] | select(.change.actions != ["create"] and .change.actions != ["no-op"])] | length')"
[[ "$other" == 0 ]] && pass "only create actions" || fail "$other resource(s) change, replace or destroy"

# 2. Forbidden by default: NAT, Elastic IP, RDS, EC2 instance, interface endpoint.
for t in aws_nat_gateway aws_eip aws_db_instance aws_rds_cluster aws_instance; do
    n="$(count "$t")"
    [[ "$n" == 0 ]] && pass "no $t" || fail "$n x $t planned"
done
iface="$(q '[.resource_changes[] | select(.type == "aws_vpc_endpoint" and .change.after.vpc_endpoint_type != "Gateway")] | length')"
[[ "$iface" == 0 ]] && pass "no interface endpoint" || fail "$iface non-Gateway endpoint(s)"

# 3. Approved resource counts (2 AZs: 2 public + 2 DB subnets).
expected="aws_db_subnet_group=1 aws_default_network_acl=1 aws_default_route_table=1 aws_default_security_group=1 aws_internet_gateway=1 aws_route=1 aws_route_table=3 aws_route_table_association=4 aws_subnet=4 aws_vpc=1 aws_vpc_endpoint=1"
actual="$(q '[.resource_changes[].type] | group_by(.) | map("\(.[0])=\(length)") | join(" ")')"
[[ "$actual" == "$expected" ]] && pass "resource counts: 19" || fail "resource counts: $actual"

# 4. The only route is public 0.0.0.0/0 -> IGW; DB route tables have no route out.
route="$(q '[.resource_changes[] | select(.type == "aws_route") | "\(.name)=\(.change.after.destination_cidr_block)"] | join(" ")')"
[[ "$route" == "public_internet_gateway=0.0.0.0/0" ]] && pass "only route: public -> IGW" || fail "routes: $route"

# 5. Public subnets give a public IPv4; DB subnets never do.
pub="$(q '[.resource_changes[] | select(.type == "aws_subnet") | "\(.name)=\(.change.after.map_public_ip_on_launch)"] | sort | join(" ")')"
[[ "$pub" == "database=false database=false public=true public=true" ]] && pass "public IPv4 only on public subnets" || fail "map_public_ip_on_launch: $pub"

# 6. No inbound from the Internet and no SSH in any security group or rule.
open_in="$(q '[.resource_changes[]
    | if .type == "aws_vpc_security_group_ingress_rule" then .change.after
      elif (.type == "aws_security_group" or .type == "aws_default_security_group") then (.change.after.ingress // [])[]
      elif .type == "aws_security_group_rule" and .change.after.type == "ingress" then .change.after
      else empty end
    | select(((.cidr_blocks // []) | index("0.0.0.0/0")) or (.cidr_ipv4 == "0.0.0.0/0") or (.from_port == 22))] | length')"
[[ "$open_in" == 0 ]] && pass "no Internet ingress, no SSH" || fail "$open_in open ingress rule(s)"
dsg="$(q '[.resource_changes[] | select(.type == "aws_default_security_group") | .change.after | ((.ingress // []) + (.egress // [])) | length] | add')"
[[ "$dsg" == 0 ]] && pass "default security group has no rules" || fail "default security group has $dsg rule(s)"

# 7. S3 endpoint: Gateway, on the public route table, policy bounded to this account.
ep="$(q '.resource_changes[] | select(.type == "aws_vpc_endpoint") | .change.after.service_name')"
[[ "$ep" == "com.amazonaws.us-east-1.s3" ]] && pass "S3 gateway endpoint service" || fail "endpoint service: $ep"
pol="$(q '.resource_changes[] | select(.type == "aws_vpc_endpoint") | .change.after.policy // ""')"
if jq -e '.Statement | length == 2 and (.[0].Condition.StringEquals["aws:ResourceAccount"] | type == "string") and (.[1].Action == "s3:GetObject")' <<< "$pol" > /dev/null 2>&1; then
    pass "endpoint policy bounded (own account + AWS-owned read-only)"
else
    fail "endpoint policy is missing or not bounded"
fi

# 8. Every taggable planned resource carries the mandatory tags (COST_PLAN §10).
untagged="$(q '[.resource_changes[] | select(.change.after | has("tags_all")) | select(.change.after.tags_all == null
    or ([.change.after.tags_all | has("Project", "Owner", "Environment", "ManagedBy", "RunId", "ExpiresAt")] | all | not)) | .address] | join(" ")')"
[[ -z "$untagged" ]] && pass "mandatory tags on every taggable resource" || fail "missing tags: $untagged"

echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (plan only; proves nothing about AWS runtime)"
