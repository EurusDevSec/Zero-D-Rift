#!/usr/bin/env bash
# Plan gate for the P2 root: network (DRF-8, ADR-0006) and EKS (DRF-9, ADR-0007).
# Reads a saved plan; changes nothing.
# Usage, from infra/terraform after: terraform plan -var-file=run.tfvars -out=tfplan
#   ./scripts/plan_assert.sh tfplan
# Inside an approved window (bootstrap_cluster_admin = true) the one admin
# association is expected instead of forbidden:
#   ADMIN_WINDOW=1 ./scripts/plan_assert.sh tfplan
# A P3 window plan (enable_p3_provider_role = true, DRF-36) adds the Crossplane
# provider IRSA role and its inline policy; check 13 then inspects them:
#   ADMIN_WINDOW=1 P3_WINDOW=1 ./scripts/plan_assert.sh tfplan
# A P4 window plan (enable_rag_platform = true, DRF-46) adds the shared RDS, its
# security group and ingress rule, five IRSA roles and six inline policies;
# checks 14-17 then inspect them:
#   ADMIN_WINDOW=1 P4_WINDOW=1 ./scripts/plan_assert.sh tfplan
# A P5 window plan (DRF-68) must also turn on NetworkPolicy in the vpc-cni
# add-on; check 18 inspects it:
#   ADMIN_WINDOW=1 P4_WINDOW=1 P5_WINDOW=1 ./scripts/plan_assert.sh tfplan
# A P6 window plan (enable_batch_platform = true, DRF-77; needs P4_WINDOW too)
# adds the batch queues, four batch roles, the Karpenter node and controller
# roles, instance profile, access entry, interruption queue and rules; checks
# 19-21 compare every P6 inline policy with tests/p6_approved_policies.json:
#   ADMIN_WINDOW=1 P4_WINDOW=1 P5_WINDOW=1 P6_WINDOW=1 ./scripts/plan_assert.sh tfplan
# --approved prints the approved P4 policy statements (fake account) for the
# guard tests. The plan JSON stays in a pipe: it is never written to disk or printed.
set -euo pipefail

# Approved P4 inline policies, statements normalised: Action and Resource sorted
# lists, account as ACCT, the RDS-managed master secret as rds!db-MASTER.
# Same content as modules/rag-identity; keep both in sync.
p4_approved='{
  "rag-db-admin": [
    {"Sid": "WriteBootstrapSecret", "Effect": "Allow",
     "Action": ["secretsmanager:CreateSecret", "secretsmanager:GetSecretValue", "secretsmanager:TagResource"],
     "Resource": ["arn:aws:secretsmanager:us-east-1:ACCT:secret:zero-drift/rag/platform/bootstrap-??????"]}],
  "rag-db-admin-master": [
    {"Sid": "ReadMasterSecret", "Effect": "Allow", "Action": ["secretsmanager:GetSecretValue"],
     "Resource": ["arn:aws:secretsmanager:us-east-1:ACCT:secret:rds!db-MASTER"]}],
  "rag-bootstrap": [
    {"Sid": "ManageSandboxSecrets", "Effect": "Allow",
     "Action": ["secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:GetSecretValue", "secretsmanager:TagResource"],
     "Resource": ["arn:aws:secretsmanager:us-east-1:ACCT:secret:zero-drift/rag/tenant-a/*", "arn:aws:secretsmanager:us-east-1:ACCT:secret:zero-drift/rag/tenant-b/*"]},
    {"Sid": "ReadBootstrapSecret", "Effect": "Allow", "Action": ["secretsmanager:GetSecretValue"],
     "Resource": ["arn:aws:secretsmanager:us-east-1:ACCT:secret:zero-drift/rag/platform/bootstrap-??????"]}],
  "rag-crossplane-s3": [
    {"Sid": "ForceDestroyObjects", "Effect": "Allow", "Action": ["s3:DeleteObject", "s3:DeleteObjectVersion"],
     "Resource": ["arn:aws:s3:::zero-drift-rag-*/*"]},
    {"Sid": "RagBuckets", "Effect": "Allow",
     "Action": ["s3:CreateBucket", "s3:DeleteBucket", "s3:GetAccelerateConfiguration", "s3:GetBucketAcl", "s3:GetBucketCORS",
                "s3:GetBucketLocation", "s3:GetBucketLogging", "s3:GetBucketObjectLockConfiguration", "s3:GetBucketPolicy",
                "s3:GetBucketRequestPayment", "s3:GetBucketTagging", "s3:GetBucketVersioning", "s3:GetBucketWebsite",
                "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:GetReplicationConfiguration", "s3:ListBucket", "s3:ListBucketVersions", "s3:PutBucketTagging"],
     "Resource": ["arn:aws:s3:::zero-drift-rag-*"]}],
  "rag-tenant-a": [
    {"Sid": "OwnBuckets", "Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": ["arn:aws:s3:::zero-drift-rag-tenant-a-*"]},
    {"Sid": "OwnSecrets", "Effect": "Allow", "Action": ["secretsmanager:GetSecretValue"],
     "Resource": ["arn:aws:secretsmanager:us-east-1:ACCT:secret:zero-drift/rag/tenant-a/*"]},
    {"Sid": "ReadOwnObjects", "Effect": "Allow", "Action": ["s3:GetObject"], "Resource": ["arn:aws:s3:::zero-drift-rag-tenant-a-*/*"]}],
  "rag-tenant-b": [
    {"Sid": "OwnBuckets", "Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": ["arn:aws:s3:::zero-drift-rag-tenant-b-*"]},
    {"Sid": "OwnSecrets", "Effect": "Allow", "Action": ["secretsmanager:GetSecretValue"],
     "Resource": ["arn:aws:secretsmanager:us-east-1:ACCT:secret:zero-drift/rag/tenant-b/*"]},
    {"Sid": "ReadOwnObjects", "Effect": "Allow", "Action": ["s3:GetObject"], "Resource": ["arn:aws:s3:::zero-drift-rag-tenant-b-*/*"]}]
}'
# P4 role -> condition operator and the only trusted subject.
p4_trust='{
  "zero-drift-rag-db-admin":      {"op": "StringEquals", "sub": "system:serviceaccount:zdr-platform:rag-db-admin"},
  "zero-drift-rag-bootstrap":     {"op": "StringEquals", "sub": "system:serviceaccount:zdr-platform:rag-bootstrap"},
  "zero-drift-rag-crossplane-s3": {"op": "StringEquals", "sub": "system:serviceaccount:crossplane-system:provider-aws-s3"},
  "zero-drift-rag-tenant-a":      {"op": "StringLike",   "sub": "system:serviceaccount:tenant-a:rag-*"},
  "zero-drift-rag-tenant-b":      {"op": "StringLike",   "sub": "system:serviceaccount:tenant-b:rag-*"}
}'
# P6 (SPEC-P6 A7): in a batch window the Crossplane S3 role also manages the
# zero-drift-batch- checkpoint buckets.
if [[ "${P6_WINDOW:-0}" == 1 ]]; then
    p4_approved="$(jq -c '(.["rag-crossplane-s3"][] | select(.Sid == "RagBuckets") | .Resource) |= (. + ["arn:aws:s3:::zero-drift-batch-*"] | sort)
        | (.["rag-crossplane-s3"][] | select(.Sid == "ForceDestroyObjects") | .Resource) |= (. + ["arn:aws:s3:::zero-drift-batch-*/*"] | sort)' <<< "$p4_approved")"
fi
# P6 roles -> the only trusted subject (all StringEquals). The approved inline
# policies live in a file shared with terraform test and the offline matrix.
p6_trust='{
  "zero-drift-batch-keda":           "system:serviceaccount:keda:keda-operator",
  "zero-drift-batch-submit":         "system:serviceaccount:zdr-platform:batch-submit",
  "zero-drift-batch-tenant-a":       "system:serviceaccount:tenant-a:batch-train",
  "zero-drift-batch-tenant-b":       "system:serviceaccount:tenant-b:batch-train",
  "zero-drift-karpenter-controller": "system:serviceaccount:karpenter:karpenter"
}'
p6_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tests/p6_approved_policies.json"
if [[ "${1:-}" == "--approved" ]]; then
    jq -c '(.. | strings) |= gsub("ACCT"; "000000000000")' <<< "$p4_approved"
    exit 0
fi

plan="${1:?usage: plan_assert.sh <saved-plan-file> | --approved}"
# A .json argument is read as plan JSON directly (used to test this script).
if [[ "$plan" == *.json ]]; then json="$(cat "$plan")"; else json="$(terraform show -json "$plan")"; fi

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }
q() { jq -r "$1" <<< "$json"; }
count() { q "[.resource_changes[] | select(.type == \"$1\")] | length"; }
after() { q ".resource_changes[] | select(.type == \"$1\") | .change.after | $2"; }

# 1. First plan only creates; nothing is updated, replaced or destroyed. Data
#    sources (mode "data") only read, so they are not counted.
other="$(q '[.resource_changes[] | select(.mode == "managed") | select(.change.actions != ["create"] and .change.actions != ["no-op"])] | length')"
[[ "$other" == 0 ]] && pass "only create actions" || fail "$other resource(s) change, replace or destroy"

# 2. Forbidden by default: NAT, Elastic IP, RDS, EC2 instance, customer KMS key,
#    access policy association (admin outside a window), interface endpoint.
#    A P4 window allows exactly one aws_db_instance (checks 3 and 14).
forbidden="aws_nat_gateway aws_eip aws_rds_cluster aws_instance aws_kms_key"
[[ "${P4_WINDOW:-0}" == 1 ]] || forbidden="$forbidden aws_db_instance"
[[ "${ADMIN_WINDOW:-0}" == 1 ]] || forbidden="$forbidden aws_eks_access_policy_association"
for t in $forbidden; do
    n="$(count "$t")"
    [[ "$n" == 0 ]] && pass "no $t" || fail "$n x $t planned"
done
iface="$(q '[.resource_changes[] | select(.type == "aws_vpc_endpoint" and .change.after.vpc_endpoint_type != "Gateway")] | length')"
[[ "$iface" == 0 ]] && pass "no interface endpoint" || fail "$iface non-Gateway endpoint(s)"

# 3. Approved managed resource counts: network 19 (2 AZs) + EKS 31 = 50,
#    plus the admin association in window mode.
#    P3 window: plus the provider IRSA role and its inline policy (DRF-36).
#    P4 window: plus the RDS instance, its security group and ingress rule,
#    five roles and six inline policies (DRF-46).
declare -A want=(
    [aws_cloudwatch_log_group]=1 [aws_db_subnet_group]=1 [aws_default_network_acl]=1
    [aws_default_route_table]=1 [aws_default_security_group]=1 [aws_eks_access_entry]=1
    [aws_eks_addon]=3 [aws_eks_cluster]=1 [aws_eks_node_group]=1 [aws_iam_openid_connect_provider]=1
    [aws_iam_role]=2 [aws_iam_role_policy_attachment]=4 [aws_internet_gateway]=1 [aws_launch_template]=1
    [aws_route]=1 [aws_route_table]=3 [aws_route_table_association]=4 [aws_security_group]=2
    [aws_security_group_rule]=12 [aws_subnet]=4 [aws_vpc]=1 [aws_vpc_endpoint]=1 [null_resource]=1 [time_sleep]=1
)
plus() { want[$1]=$(( ${want[$1]:-0} + $2 )); }
[[ "${ADMIN_WINDOW:-0}" == 1 ]] && plus aws_eks_access_policy_association 1
if [[ "${P3_WINDOW:-0}" == 1 ]]; then plus aws_iam_role 1; plus aws_iam_role_policy 1; fi
if [[ "${P4_WINDOW:-0}" == 1 ]]; then
    plus aws_db_instance 1; plus aws_security_group 1; plus aws_vpc_security_group_ingress_rule 1
    plus aws_iam_role 5; plus aws_iam_role_policy 6
fi
#    P6 window: batch queue, DLQ and Karpenter interruption queue with their
#    policies and the redrive allow policy; four batch roles plus the
#    Karpenter controller and node roles; five inline policies; three node
#    policy attachments; instance profile; EC2_LINUX access entry; four
#    EventBridge rules and targets (DRF-77).
if [[ "${P6_WINDOW:-0}" == 1 ]]; then
    plus aws_sqs_queue 3; plus aws_sqs_queue_policy 3; plus aws_sqs_queue_redrive_allow_policy 1
    plus aws_iam_role 6; plus aws_iam_role_policy 5; plus aws_iam_role_policy_attachment 3
    plus aws_iam_instance_profile 1; plus aws_eks_access_entry 1
    plus aws_cloudwatch_event_rule 4; plus aws_cloudwatch_event_target 4
fi
expected="$(for t in "${!want[@]}"; do echo "$t=${want[$t]}"; done | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
actual="$(q '[.resource_changes[] | select(.mode == "managed") | .type] | group_by(.) | map("\(.[0])=\(length)") | join(" ")')"
[[ "$actual" == "$expected" ]] && pass "resource counts: $(q '[.resource_changes[] | select(.mode == "managed")] | length') managed" || fail "resource counts: $actual"

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
# Statement 2 may read objects only in the listed layer buckets (DRF-37: quay.io and
# registry.k8s.io store layers in S3 us-east-1). The set must equal the list:
# any other bucket, or a missing one, fails (Codex review 14/11).
layer_allow='["arn:aws:s3:::prod-us-east-1-starport-layer-bucket/*","arn:aws:s3:::al2023-repos-us-east-1-de612dc2/*","arn:aws:s3:::quayio-production-s3/*","arn:aws:s3:::prod-registry-k8s-io-us-east-1/*"]'
if jq -e --argjson allow "$layer_allow" '.Statement | length == 2 and (.[0].Condition.StringEquals["aws:ResourceAccount"] | type == "string")
        and (.[1].Action == "s3:GetObject") and (([.[1].Resource] | flatten | sort) == ($allow | sort))' <<< "$pol" > /dev/null 2>&1; then
    pass "endpoint policy bounded (own account + read-only layer buckets)"
else
    fail "endpoint policy is missing or not bounded"
fi

# 8. EKS control plane (DRF-9): version, standard support, API auth, no creator
#    admin, private endpoint on, public endpoint only for /24-or-narrower CIDRs,
#    no customer KMS encryption, audit+authenticator logs kept 3 days.
cl="$(after aws_eks_cluster '"\(.version) \(.upgrade_policy[0].support_type) \(.access_config[0].authentication_mode) \(.access_config[0].bootstrap_cluster_creator_admin_permissions)"')"
[[ "$cl" == "1.35 STANDARD API false" ]] && pass "EKS 1.35, standard support, API auth, no creator admin" || fail "EKS cluster: $cl"
ep="$(after aws_eks_cluster '.vpc_config[0] | "\(.endpoint_private_access) \(all(.public_access_cidrs[]; (split("/")[1] | tonumber) >= 24))"')"
[[ "$ep" == "true true" ]] && pass "private endpoint on; public endpoint bounded" || fail "endpoint: $ep"
lg="$(after aws_eks_cluster '"\(.enabled_cluster_log_types | sort | join(",")) \(.encryption_config | length)"') $(after aws_cloudwatch_log_group '.retention_in_days')"
[[ "$lg" == "audit,authenticator 0 3" ]] && pass "logs audit+authenticator, 3 days; no customer KMS" || fail "logs/encryption: $lg"

# 9. System nodes: AL2023 with a pinned release, priced type, at most 2 On-Demand
#    nodes (5 vCPU quota), IMDSv2 only with hop limit 1.
ng="$(after aws_eks_node_group '"\(.ami_type) \(.release_version | test("^1[.]35[.][0-9]+-[0-9]{8}$")) \(.instance_types | join(",")) \(.capacity_type) \(.scaling_config[0].max_size <= 2)"')"
[[ "$ng" == "AL2023_x86_64_STANDARD true m6i.large ON_DEMAND true" ]] && pass "node group AL2023 pinned, m6i.large, max 2" || fail "node group: $ng"
md="$(after aws_launch_template '.metadata_options[0] | "\(.http_tokens) \(.http_put_response_hop_limit)"')"
[[ "$md" == "required 1" ]] && pass "IMDSv2 required, hop limit 1" || fail "metadata options: $md"

# 10. Add-ons pinned to exact versions; one STANDARD access entry for the bootstrap
#     role (stable role ARN, not a session); OIDC provider for later IRSA.
ad="$(q '[.resource_changes[] | select(.type == "aws_eks_addon") | .change.after | "\(.addon_name)=\(.addon_version // "" | test("^v[0-9.]+-eksbuild[.][0-9]+$"))"] | sort | join(" ")')"
[[ "$ad" == "coredns=true kube-proxy=true vpc-cni=true" ]] && pass "add-ons pinned: coredns, kube-proxy, vpc-cni" || fail "add-ons: $ad"
# The P6 Karpenter EC2_LINUX entry is checked in check 21.
ae="$(q '[.resource_changes[] | select(.type == "aws_eks_access_entry" and .change.after.type != "EC2_LINUX") | .change.after | "\(.type) \(.principal_arn | test(":role/zero-drift-bootstrap$"))"] | join(",")')"
[[ "$ae" == "STANDARD true" ]] && pass "access entry: bootstrap role (STANDARD)" || fail "access entry: $ae"
[[ "$(count aws_iam_openid_connect_provider)" == 1 ]] && pass "OIDC provider for IRSA" || fail "OIDC provider missing"

# 11. Every taggable planned resource carries the mandatory tags (COST_PLAN §10).
untagged="$(q '[.resource_changes[] | select(.change.after | has("tags_all")) | select(.change.after.tags_all == null
    or ([.change.after.tags_all | has("Project", "Owner", "Environment", "ManagedBy", "RunId", "ExpiresAt")] | all | not)) | .address] | join(" ")')"
[[ -z "$untagged" ]] && pass "mandatory tags on every taggable resource" || fail "missing tags: $untagged"

# 12. IAM stays inside the R1 Terraform policy scope: roles only under the
#     zero-drift-cluster-/zero-drift-system-node- prefixes, attachments only the
#     four EKS managed policies (infra/iam/zero-drift-terraform-policy.json).
#     A P3 window adds exactly one role, zero-drift-p3-crossplane-s3 (check 13).
roles="$(q '[.resource_changes[] | select(.type == "aws_iam_role") | .change.after | (.name_prefix // .name)] | sort | join(" ")')"
atts="$(q '[.resource_changes[] | select(.type == "aws_iam_role_policy_attachment") | .change.after.policy_arn | split("/") | last] | sort | join(" ")')"
#     A P4 window adds exactly the five zero-drift-rag- roles (checks 16-17).
want_roles="zero-drift-cluster- zero-drift-system-node-"
[[ "${P3_WINDOW:-0}" == 1 ]] && want_roles="$want_roles zero-drift-p3-crossplane-s3"
[[ "${P4_WINDOW:-0}" == 1 ]] && want_roles="$want_roles $(jq -r 'keys | join(" ")' <<< "$p4_trust")"
[[ "${P6_WINDOW:-0}" == 1 ]] && want_roles="$want_roles $(jq -r 'keys | join(" ")' <<< "$p6_trust") zero-drift-karpenter-node"
want_roles="$(tr ' ' '\n' <<< "$want_roles" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
want_atts="AmazonEC2ContainerRegistryReadOnly AmazonEKSClusterPolicy AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy"
[[ "${P6_WINDOW:-0}" == 1 ]] && want_atts="AmazonEC2ContainerRegistryPullOnly AmazonEC2ContainerRegistryReadOnly AmazonEKSClusterPolicy AmazonEKSWorkerNodePolicy AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEKS_CNI_Policy"
[[ "$roles" == "$want_roles" && "$atts" == "$want_atts" ]] \
    && pass "IAM within scope (roles: $want_roles; managed policies: $want_atts)" || fail "IAM scope: roles='$roles' attachments='$atts'"

# 13. P3 provider IRSA role (DRF-36, SPEC-P3 Task 4). Default plan: no inline
#     role policy. P3 window: web identity trust for exactly the provider-aws-s3
#     ServiceAccount with audience sts.amazonaws.com; S3 actions only (never IAM)
#     on arn:aws:s3:::zero-drift-p3-* only; within the 10240-char limit. That
#     resource also matches object ARNs (* crosses "/"), so every action must be
#     in the approved bucket-level list below: an object action such as
#     s3:DeleteObject has no wildcard yet still fails (Codex review 14/11).
#     Same list as tests/p3_irsa.tftest.hcl; keep both in sync.
#     Inline policies are told apart by name: p3-buckets (P3), rag-* (P4).
inline="$(q '[.resource_changes[] | select(.type == "aws_iam_role_policy") | .change.after.name // "?"] | sort | join(" ")')"
want_inline=""
[[ "${P3_WINDOW:-0}" == 1 ]] && want_inline="p3-buckets"
[[ "${P4_WINDOW:-0}" == 1 ]] && want_inline="$want_inline $(jq -r 'keys | join(" ")' <<< "$p4_approved")"
[[ "${P6_WINDOW:-0}" == 1 ]] && want_inline="$want_inline $(jq -r '.policies | keys | join(" ")' "$p6_file")"
want_inline="$(tr ' ' '\n' <<< "$want_inline" | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
[[ "$inline" == "$want_inline" ]] && pass "inline role policies: ${want_inline:-none}" || fail "inline role policies: '$inline', expected '${want_inline:-none}'"
if [[ "${P3_WINDOW:-0}" == 1 ]]; then
    # On a first plan the trust policy is unknown: it embeds the OIDC provider of
    # a cluster that does not exist yet (seen 05/11, P3-L3-20261105-01). Then it
    # is covered by terraform test (p3_irsa) and, after apply, by
    # p3_iam_check.sh --principal, which reads the live trust document.
    role_sel='.resource_changes[] | select(.type == "aws_iam_role" and .change.after.name == "zero-drift-p3-crossplane-s3")'
    if [[ "$(q "$role_sel | .change.after_unknown.assume_role_policy // false")" == true ]]; then
        echo "INFO  P3 role trust unknown until the cluster OIDC exists: verify after apply with p3_iam_check.sh --principal"
    else
        trust="$(q "$role_sel | .change.after.assume_role_policy")"
        tr_ok="$(jq -r '[(.Statement | length == 1),
            (.Statement[0] | .Effect == "Allow" and .Action == "sts:AssumeRoleWithWebIdentity"
                and (.Principal.Federated | test(":oidc-provider/oidc[.]eks[.]us-east-1[.]amazonaws[.]com/id/"))
                and ([.Condition.StringEquals | to_entries[] | select(.key | endswith(":sub")) | .value] == ["system:serviceaccount:crossplane-system:provider-aws-s3"])
                and ([.Condition.StringEquals | to_entries[] | select(.key | endswith(":aud")) | .value] == ["sts.amazonaws.com"]))] | all' <<< "$trust" 2>/dev/null || echo false)"
        [[ "$tr_ok" == true ]] && pass "P3 role trust: one web identity statement, sub provider-aws-s3, aud sts" || fail "P3 role trust policy is not the approved shape"
    fi
    perm="$(q '.resource_changes[] | select(.type == "aws_iam_role_policy" and .change.after.name == "p3-buckets") | .change.after.policy')"
    p3_actions='["s3:CreateBucket","s3:DeleteBucket","s3:ListBucket","s3:PutBucketTagging","s3:GetBucket*","s3:GetAccelerateConfiguration","s3:GetEncryptionConfiguration","s3:GetLifecycleConfiguration","s3:GetReplicationConfiguration"]'
    pm_ok="$(jq -r --argjson allow "$p3_actions" '[.Statement[] | .Effect == "Allow"
        and ([.Resource] | flatten == ["arn:aws:s3:::zero-drift-p3-*"])
        and ([.Action] | flatten | all(. as $a | $allow | index($a)))] | all' <<< "$perm" 2>/dev/null || echo false)"
    [[ "$pm_ok" == true ]] && pass "P3 role policy: approved bucket-level S3 actions only, on arn:aws:s3:::zero-drift-p3-* only" || fail "P3 role policy: wildcard resource, or an action outside the approved bucket-level list (object, IAM or wildcard)"
    size="$(jq -c . <<< "$perm" | tr -d ' \r\n\t' | wc -c)"
    (( size <= 10240 )) && pass "P3 role policy size $size/10240" || fail "P3 role policy is $size chars, limit 10240"
fi

# 14-17: P4 window only (DRF-46, SPEC-P4 P4-T2.2). Outside it, checks 2, 3, 12
#        and 13 already forbid every P4 resource.
if [[ "${P4_WINDOW:-0}" == 1 ]]; then
    # 14. Shared RDS per D2: private, encrypted, RDS-managed master password, and
    #     destroyable in the window (no backup, no final snapshot, no deletion
    #     protection); minor version pinned and not auto-upgraded.
    priv="$(after aws_db_instance '"\(.publicly_accessible) \(.storage_encrypted) \(.manage_master_user_password) \(.iam_database_authentication_enabled)"')"
    [[ "$priv" == "false true true false" ]] && pass "P4 RDS private: not public, encrypted, RDS-managed master password" \
        || fail "P4 RDS private: publicly_accessible storage_encrypted manage_master_user_password iam_auth = $priv"
    shape="$(after aws_db_instance '"\(.engine) \(.engine_version) \(.instance_class) \(.allocated_storage) \(.max_allocated_storage) \(.storage_type) \(.multi_az) \(.backup_retention_period) \(.skip_final_snapshot) \(.deletion_protection) \(.auto_minor_version_upgrade)"')"
    [[ "$shape" == "postgres 17.11 db.t4g.micro 20 0 gp3 false 0 true false false" ]] \
        && pass "P4 RDS shape: postgres 17.11, db.t4g.micro, 20 GiB gp3, Single-AZ, no backup/final snapshot/deletion protection, no auto minor upgrade" \
        || fail "P4 RDS shape: $shape"

    # 15. Exactly one way in: one ingress rule, 5432/tcp, from a security group
    #     (the node SG; its ID is unknown on a first plan), never from a CIDR or
    #     prefix list. The instance's own group has no inline rule.
    ing="$(q '[.resource_changes[] | select(.type == "aws_vpc_security_group_ingress_rule") | .change as $c | $c.after
        | "\(.ip_protocol) \(.from_port) \(.to_port) \(.cidr_ipv4 == null and .cidr_ipv6 == null and .prefix_list_id == null) \(.referenced_security_group_id != null or ($c.after_unknown.referenced_security_group_id // false))"] | join(",")')"
    [[ "$ing" == "tcp 5432 5432 true true" ]] && pass "P4 RDS ingress: one rule, 5432/tcp from a security group only" || fail "P4 RDS ingress: $ing"

    # 16. P4 inline policies: each known policy equals the approved statements
    #     (account masked). A policy that embeds an unknown value (the master
    #     secret ARN before the instance exists) is reported and covered by
    #     terraform test and rag_iam_check.sh --principal after apply.
    p4pol="$(q '[.resource_changes[] | select(.type == "aws_iam_role_policy" and (.change.after.name // "" | startswith("rag-")))
        | {name: .change.after.name, unknown: (.change.after_unknown.policy // false), policy: (.change.after.policy // null)}]')"
    unknown="$(jq -r '[.[] | select(.unknown) | .name] | join(" ")' <<< "$p4pol")"
    [[ -n "$unknown" ]] && echo "INFO  P4 policies unknown until apply (verify with rag_iam_check.sh --principal): $unknown"
    known="$(jq -c '[.[] | select(.unknown | not) | {name, doc: (.policy | fromjson)}]' <<< "$p4pol" 2>/dev/null || echo '[{"name":"unparsable"}]')"
    star="$(jq -r '[.[] | .doc.Statement[] | [.Resource] | flatten[] | select(. == "*")] | length' <<< "$known" 2>/dev/null || echo 1)"
    [[ "$star" == 0 ]] && pass "P4 policies no-star: no resource \"*\"" || fail "P4 policies no-star: $star statement resource(s) are \"*\""
    iamx="$(jq -r '[.[] | .doc.Statement[] | [.Action] | flatten[] | select(test("^(iam|sts):|\\*"; "i"))] | unique | join(" ")' <<< "$known" 2>/dev/null || echo unparsable)"
    [[ -z "$iamx" ]] && pass "P4 policies no-iam: no IAM/STS action, no wildcard action" || fail "P4 policies no-iam: forbidden action(s): $iamx"
    diffs="$(jq -r --argjson ok "$p4_approved" '[.[]
        | .name as $n
        | (.doc.Statement | map({Sid, Effect, Action: ([.Action] | flatten | sort), Resource: ([.Resource] | flatten | sort)})
            | map(.Resource |= map(gsub(":[0-9]{12}:"; ":ACCT:") | gsub("secret:rds!db-.*$"; "secret:rds!db-MASTER"))) | sort_by(.Sid)) as $got
        | select($got != ($ok[$n] // "missing")) | $n] | join(" ")' <<< "$known" 2>/dev/null || echo unparsable)"
    [[ -z "$diffs" ]] && pass "P4 policies approved: every known policy equals its approved statements (exact actions and resources)" \
        || fail "P4 policies approved: not the approved statements: $diffs"
    cross="$(jq -r '[.[] | select(.name | test("^rag-tenant-")) | (.name | ltrimstr("rag-")) as $t
        | .doc.Statement[] | [.Resource] | flatten[] | select(([scan("tenant-[a-z]")] | unique) != [$t])] | length' <<< "$known" 2>/dev/null || echo 1)"
    [[ "$cross" == 0 ]] && pass "P4 tenant separation: a tenant policy names only its own tenant" || fail "P4 tenant separation: $cross resource(s) name another tenant or no tenant"
    big="$(jq -r '[.[] | select((.doc | tojson | gsub("[ \r\n\t]"; "") | length) > 10240) | .name] | join(" ")' <<< "$known" 2>/dev/null || echo unparsable)"
    [[ -z "$big" ]] && pass "P4 policies size: within the 10240-char inline limit" || fail "P4 policies size: over the limit: $big"

    # 17. P4 trust: one web identity statement from the cluster issuer, audience
    #     sts.amazonaws.com, and the sub condition only as approved: platform and
    #     Crossplane roles one exact ServiceAccount (StringEquals, never a
    #     pattern), tenant roles rag-* in their own namespace (StringLike).
    #     Unknown before the cluster OIDC exists (as in check 13).
    # Word list from $(...), not `read`: jq on Windows ends lines with CRLF and
    # read would keep the \r (command substitution drops it).
    for name in $(jq -r 'keys | join(" ")' <<< "$p4_trust"); do
        sel=".resource_changes[] | select(.type == \"aws_iam_role\" and .change.after.name == \"$name\")"
        if [[ -z "$(q "$sel | .change.after.name")" ]]; then fail "P4 trust $name: role missing"; continue; fi
        if [[ "$(q "$sel | .change.after_unknown.assume_role_policy // false")" == true ]]; then
            echo "INFO  P4 trust $name: unknown until the cluster OIDC exists, verify after apply with rag_iam_check.sh --principal"; continue
        fi
        ok="$(q "$sel | .change.after.assume_role_policy" | jq -r --argjson want "$(jq -c --arg n "$name" '.[$n]' <<< "$p4_trust")" '
            .Statement as $s | ($s[0].Condition // {}) as $c
            | ($want.op) as $op | (if $op == "StringEquals" then "StringLike" else "StringEquals" end) as $other
            | [($s | length == 1), $s[0].Effect == "Allow", $s[0].Action == "sts:AssumeRoleWithWebIdentity",
               ($s[0].Principal.Federated | test(":oidc-provider/oidc[.]eks[.]us-east-1[.]amazonaws[.]com/id/")),
               ([$c.StringEquals // {} | to_entries[] | select(.key | endswith(":aud")) | .value] == ["sts.amazonaws.com"]),
               ([$c[$op] // {} | to_entries[] | select(.key | endswith(":sub")) | .value] == [$want.sub]),
               ([$c[$other] // {} | to_entries[] | select(.key | endswith(":sub"))] | length == 0),
               (($c | keys) - ["StringEquals", "StringLike"] | length == 0)] | all' 2>/dev/null || echo false)"
        [[ "$ok" == true ]] && pass "P4 trust $name: $(jq -r --arg n "$name" '.[$n] | "\(.op) \(.sub)"' <<< "$p4_trust")" \
            || fail "P4 trust $name: not the approved web identity, audience or subject"
    done
fi

# 18. P5 (DRF-68, SPEC-P5 D5): the vpc-cni add-on enforces NetworkPolicy in
#     standard mode. Without it every NetworkPolicy is accepted and ignored.
if [[ "${P5_WINDOW:-0}" == 1 ]]; then
    cni="$(q '[.resource_changes[] | select(.type == "aws_eks_addon" and .change.after.addon_name == "vpc-cni") | .change.after.configuration_values // "null"] | first // "null"')"
    ok="$(jq -r '(.enableNetworkPolicy == "true") and (.env.NETWORK_POLICY_ENFORCING_MODE == "standard")' <<< "$cni" 2>/dev/null || echo false)"
    [[ "$ok" == true ]] && pass "P5 vpc-cni: NetworkPolicy on, standard mode" \
        || fail "P5 vpc-cni: needs enableNetworkPolicy \"true\" and NETWORK_POLICY_ENFORCING_MODE standard"
fi

# 19-21: P6 window only (DRF-77, SPEC-P6 P6-T3). Outside it, checks 3, 12 and
#        13 already forbid every P6 resource (enable_batch_platform off).
if [[ "${P6_WINDOW:-0}" == 1 ]]; then
    # 19. Queues per D8: shared queue 120 s visibility, 1 h retention, SSE-SQS,
    #     redrive to the DLQ after 3 receives; DLQ 1 h, SSE; Karpenter
    #     interruption queue 300 s, SSE. No queue policy allows any principal
    #     "*" or an AWS principal (not public); every queue policy denies HTTP.
    qs="$(q '[.resource_changes[] | select(.type == "aws_sqs_queue") | .change.after
        | "\(.name):\(.visibility_timeout_seconds // "-"):\(.message_retention_seconds):\(.sqs_managed_sse_enabled):\((.redrive_policy // "{}") | fromjson | .maxReceiveCount // "-")"] | sort | join(" ")')"
    [[ "$qs" == "zero-drift-batch-dlq:30:3600:true:- zero-drift-batch:120:3600:true:3 zero-drift-karpenter:30:300:true:-" ]] \
        && pass "P6 queue settings: batch 120 s/1 h/SSE/maxReceive 3, DLQ 1 h/SSE, interruption 300 s/SSE" || fail "P6 queue settings: $qs"
    redrive="$(q '[.resource_changes[] | select(.type == "aws_sqs_queue" and .change.after.name == "zero-drift-batch") | (.change.after.redrive_policy // "{}") | fromjson | (.deadLetterTargetArn // "") | test(":zero-drift-batch-dlq$")] | (length == 1 and all)')"
    [[ "$redrive" == true ]] && pass "P6 redrive target: zero-drift-batch-dlq" || fail "P6 redrive target is not zero-drift-batch-dlq"
    qp="$(q '[.resource_changes[] | select(.type == "aws_sqs_queue_policy") | (.change.after.policy // "{\"Statement\":[]}") | fromjson
        | [(.Statement | any(.Effect == "Deny" and .Condition.Bool["aws:SecureTransport"] == "false")),
           (.Statement | all(.Effect == "Deny" or ((.Principal | type) == "object" and (.Principal | has("AWS") | not)
              and ([.Principal.Service] | flatten | all(. == "events.amazonaws.com" or . == "sqs.amazonaws.com")))))] | all] | (length == 3 and all)')"
    [[ "$qp" == true ]] && pass "P6 queues not public: no Allow to \"*\" or an AWS principal; HTTP denied on all three" \
        || fail "P6 queues not public: a queue policy allows a broad principal or does not deny HTTP"

    # 20. P6 inline policies equal tests/p6_approved_policies.json (account
    #     masked as ACCT), plus named guards so a failure says what broke.
    p6pol="$(q '[.resource_changes[] | select(.type == "aws_iam_role_policy" and ((.change.after.name // "") | test("^(batch-|karpenter-controller$)")))
        | {name: .change.after.name, role: (.change.after.role // null), unknown: (.change.after_unknown.policy // false), doc: (.change.after.policy // "{\"Statement\":[]}" | fromjson)}]')"
    # The right policy on the wrong role is as bad as a wrong policy (Codex P6 R1):
    # policy NAME must sit on role zero-drift-NAME. The modules pass the role name,
    # which is known in the plan. Only the policy name and a fixed code are printed:
    # a wrong role name could hold an account ID (Codex P6 R2).
    wrongrole="$(jq -r '[.[] | select(.role != ("zero-drift-" + .name)) | "\(.name):\(if .role == null then "unknown-role" else "wrong-role" end)"] | join(" ")' <<< "$p6pol" 2>/dev/null || echo unparsable)"
    [[ -z "$wrongrole" ]] && pass "P6 policy attachment: each policy NAME on role zero-drift-NAME" || fail "P6 policy attachment: $wrongrole"
    unknown="$(jq -r '[.[] | select(.unknown) | .name] | join(" ")' <<< "$p6pol")"
    [[ -z "$unknown" ]] && pass "P6 policies known in the plan" || fail "P6 policies known in the plan: unknown (they are built from names): $unknown"
    norm='map(.doc.Statement |= (map(.Action |= ([.] | flatten | sort)
            | .Resource |= ([.] | flatten | map(gsub(":[0-9]{12}:"; ":ACCT:")) | sort)
            | (if .Condition then .Condition |= (tojson | gsub(":[0-9]{12}:"; ":ACCT:") | fromjson) else . end)) | sort_by(.Sid)))'
    diffs="$(jq -r --slurpfile ok "$p6_file" "$norm"' | [.[] | .name as $n | select(.doc.Statement != ($ok[0].policies[$n] // [] | sort_by(.Sid))) | $n] | join(" ")' <<< "$p6pol" 2>/dev/null || echo unparsable)"
    have="$(jq -r '[.[].name] | sort | join(" ")' <<< "$p6pol")"
    [[ -z "$diffs" && "$have" == "$(jq -r '.policies | keys | sort | join(" ")' "$p6_file")" ]] \
        && pass "P6 policies approved: every P6 policy equals tests/p6_approved_policies.json" || fail "P6 policies approved: differ or missing: ${diffs:-$have}"
    iamw="$(jq -r '[.[] | .doc.Statement[] | [.Action] | flatten[] | select(test("^iam:|^\\*$"; "i"))
        | select(. != "iam:PassRole" and . != "iam:GetInstanceProfile" and . != "iam:ListInstanceProfiles")] | unique | join(" ")' <<< "$p6pol" 2>/dev/null || echo unparsable)"
    [[ -z "$iamw" ]] && pass "P6 karpenter no-iam-write: only PassRole, GetInstanceProfile, ListInstanceProfiles" || fail "P6 karpenter no-iam-write: $iamw"
    # One exception: a statement whose only action is the read-only
    # iam:ListInstanceProfiles (IAM has no resource scope for it).
    iamstar="$(jq -r '[.[] | .doc.Statement[] | select([.Action] | flatten | any(test("^(iam|sts):"; "i")))
        | select(([.Action] | flatten) != ["iam:ListInstanceProfiles"]) | [.Resource] | flatten[] | select(. == "*")] | length' <<< "$p6pol" 2>/dev/null || echo 1)"
    [[ "$iamstar" == 0 ]] && pass "P6 no-iam-star: no IAM action on resource \"*\" (except ListInstanceProfiles alone)" || fail "P6 no-iam-star: $iamstar IAM statement resource(s) are \"*\""
    pass_ok="$(jq -r '[.[] | .doc.Statement[] | select([.Action] | flatten | index("iam:PassRole"))
        | (([.Resource] | flatten) as $r | ($r | length == 1) and ($r[0] | test(":role/zero-drift-karpenter-node$"))
           and (.Condition.StringEquals["iam:PassedToService"] == "ec2.amazonaws.com"))] | (length == 1 and all)' <<< "$p6pol" 2>/dev/null || echo false)"
    [[ "$pass_ok" == true ]] && pass "P6 PassRole: only zero-drift-karpenter-node, only to ec2.amazonaws.com" || fail "P6 PassRole: not exactly the node role to EC2"
    cross="$(jq -r '[.[] | select(.name | test("^batch-tenant-")) | (.name | ltrimstr("batch-")) as $t
        | .doc.Statement[] | [.Resource] | flatten[] | select(test("^arn:aws:s3:")) | select(([scan("tenant-[a-z]")] | unique) != [$t])] | length' <<< "$p6pol" 2>/dev/null || echo 1)"
    [[ "$cross" == 0 ]] && pass "P6 tenant separation: a tenant policy names only its own buckets" || fail "P6 tenant separation: $cross bucket resource(s) name another tenant or no tenant"
    sub_ok="$(jq -r '[.[] | select(.name == "batch-submit") | .doc.Statement[]] as $s
        | ($s | length > 0)
          and ([$s[] | [.Action] | flatten[]] | index("s3:GetObject") == null)
          and ([$s[] | select([.Action] | flatten | index("s3:ListBucket"))] | length == 1 and all(.Condition.StringLike["s3:prefix"] | [.] | flatten == ["runs/*/submitted"]))' <<< "$p6pol" 2>/dev/null || echo false)"
    [[ "$sub_ok" == true ]] && pass "P6 submit list: s3:ListBucket only with s3:prefix runs/*/submitted; no s3:GetObject" || fail "P6 submit list: missing prefix condition or has s3:GetObject"

    # 21. Trust, node role and discovery. P6 IRSA roles: one web identity
    #     statement, audience sts.amazonaws.com, one exact subject (StringEquals,
    #     never a pattern); unknown before the cluster OIDC exists. Node role:
    #     EC2 trust, three EKS worker policies, no SSM; instance profile of that
    #     role; EC2_LINUX access entry; four interruption rules with targets;
    #     discovery tag on both public subnets and the node security group only.
    for name in $(jq -r 'keys | join(" ")' <<< "$p6_trust"); do
        sel=".resource_changes[] | select(.type == \"aws_iam_role\" and .change.after.name == \"$name\")"
        if [[ -z "$(q "$sel | .change.after.name")" ]]; then fail "P6 trust $name: role missing"; continue; fi
        if [[ "$(q "$sel | .change.after_unknown.assume_role_policy // false")" == true ]]; then
            echo "INFO  P6 trust $name: unknown until the cluster OIDC exists, verify after apply with batch_iam_check.sh --principal"; continue
        fi
        ok="$(q "$sel | .change.after.assume_role_policy" | jq -r --arg sub "$(jq -r --arg n "$name" '.[$n]' <<< "$p6_trust")" '
            .Statement as $s | ($s[0].Condition // {}) as $c
            | [($s | length == 1), $s[0].Effect == "Allow", $s[0].Action == "sts:AssumeRoleWithWebIdentity",
               ($s[0].Principal.Federated | test(":oidc-provider/oidc[.]eks[.]us-east-1[.]amazonaws[.]com/id/")),
               ([$c.StringEquals // {} | to_entries[] | select(.key | endswith(":aud")) | .value] == ["sts.amazonaws.com"]),
               ([$c.StringEquals // {} | to_entries[] | select(.key | endswith(":sub")) | .value] == [$sub]),
               (($c | keys) == ["StringEquals"])] | all' 2>/dev/null || echo false)"
        [[ "$ok" == true ]] && pass "P6 trust $name: StringEquals $(jq -r --arg n "$name" '.[$n]' <<< "$p6_trust")" \
            || fail "P6 trust $name: not the approved web identity, audience or subject"
    done
    node="$(q '[.resource_changes[] | select(.type == "aws_iam_role" and .change.after.name == "zero-drift-karpenter-node") | .change.after.assume_role_policy | fromjson
        | (.Statement | length == 1) and .Statement[0].Principal.Service == "ec2.amazonaws.com" and .Statement[0].Action == "sts:AssumeRole"] | (length == 1 and all)')"
    natt="$(q '[.resource_changes[] | select(.type == "aws_iam_role_policy_attachment" and (.address | test("module[.]karpenter"))) | .change.after.policy_arn | split("/") | last] | sort | join(" ")')"
    prof="$(q '[.resource_changes[] | select(.type == "aws_iam_instance_profile") | .change.after | "\(.name)=\(.role)"] | join(" ")')"
    ent="$(q '[.resource_changes[] | select(.type == "aws_eks_access_entry" and .change.after.type == "EC2_LINUX") | .address | test("module[.]karpenter")] | map(tostring) | join(" ")')"
    [[ "$node" == true && "$natt" == "AmazonEC2ContainerRegistryPullOnly AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy" \
       && "$prof" == "zero-drift-karpenter-node=zero-drift-karpenter-node" && "$ent" == "true" ]] \
        && pass "P6 node role: EC2 trust, 3 worker policies (no SSM), pre-created profile, one EC2_LINUX entry" \
        || fail "P6 node role: trust=$node attachments='$natt' profile='$prof' ec2_linux_entries='$ent'"
    rules="$(q '[.resource_changes[] | select(.type == "aws_cloudwatch_event_rule") | .change.after.event_pattern | fromjson | .["detail-type"][0]] | sort | join("|")')"
    tgts="$(q '[.resource_changes[] | select(.type == "aws_cloudwatch_event_target") | .change.after.arn // "" | test(":zero-drift-karpenter$")] | (length == 4 and all)')"
    [[ "$rules" == "AWS Health Event|EC2 Instance Rebalance Recommendation|EC2 Instance State-change Notification|EC2 Spot Instance Interruption Warning" && "$tgts" == true ]] \
        && pass "P6 interruption: 4 rules, all targets on zero-drift-karpenter" || fail "P6 interruption: rules='$rules' targets=$tgts"
    disc="$(q '[.resource_changes[] | select((.type == "aws_subnet" or .type == "aws_security_group") and ((.change.after.tags // {}) | has("karpenter.sh/discovery")))
        | "\(.type):\(.name):\(.change.after.tags["karpenter.sh/discovery"])"] | sort | join(" ")')"
    [[ "$disc" == "aws_security_group:node:zero-drift aws_subnet:public:zero-drift aws_subnet:public:zero-drift" ]] \
        && pass "P6 discovery tag: 2 public subnets and the node security group only" || fail "P6 discovery tag: $disc"
fi

echo
if (( failed )); then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS (plan only; proves nothing about AWS runtime)"
