#!/usr/bin/env bash
# Read-only AWS inventory for a P2-P6 window (COST_PLAN §11.1, SPEC-P2 Task 6, DRF-46, DRF-77).
# Prints counts only, never IDs, ARNs or names, so the output can go into evidence.
# Run it before create, after verify, and after destroy.
# Usage: AWS_PROFILE=zdr-tf AWS_REGION=us-east-1 infra/terraform/scripts/inventory.sh
# Exit 0 only when nothing outside the retain allowlist exists (pre/post window).
set -euo pipefail

: "${AWS_REGION:?export AWS_REGION first}"
: "${AWS_PROFILE:?export AWS_PROFILE first}"
# Git Bash would rewrite /aws/eks into a Windows path; harmless elsewhere.
export MSYS_NO_PATHCONV=1

failed=0
# name, expected maximum (retain allowlist), command printing a number
check() {
    local name="$1" allowed="$2"; shift 2
    local n
    n="$("$@" 2>/dev/null)" || n="ERR"
    if [[ "$n" == "ERR" || -z "$n" || "$n" == "None" ]]; then
        echo "ERROR $name (read failed)"; failed=1
    elif (( n > allowed )); then
        echo "LEFT  $name=$n (allowed $allowed)"; failed=1
    else
        echo "OK    $name=$n"
    fi
}

echo "inventory $(date -u +%Y-%m-%dT%H:%M:%SZ) region=$AWS_REGION"

# Compute, Kubernetes and storage
check eks_clusters          0 aws eks list-clusters --query 'length(clusters)' --output text
check ec2_instances_live    0 aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping,stopped --query 'length(Reservations[].Instances[])' --output text
check launch_templates      0 aws ec2 describe-launch-templates --query 'length(LaunchTemplates)' --output text
check ebs_volumes           0 aws ec2 describe-volumes --query 'length(Volumes)' --output text
check ebs_snapshots_own     0 aws ec2 describe-snapshots --owner-ids self --query 'length(Snapshots)' --output text

# Network and public IPv4 (the hourly cost leakers)
check vpcs_non_default      0 aws ec2 describe-vpcs --filters Name=is-default,Values=false --query 'length(Vpcs)' --output text
check nat_gateways_live     0 aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available,deleting --query 'length(NatGateways)' --output text
check elastic_ips           0 aws ec2 describe-addresses --query 'length(Addresses)' --output text
check vpc_endpoints_live    0 aws ec2 describe-vpc-endpoints --filters Name=vpc-endpoint-state,Values=pendingAcceptance,pending,available,deleting --query 'length(VpcEndpoints)' --output text
check enis                  0 aws ec2 describe-network-interfaces --query 'length(NetworkInterfaces)' --output text
check sg_non_default        0 aws ec2 describe-security-groups --query "length(SecurityGroups[?GroupName!='default'])" --output text
check load_balancers_v2     0 aws elbv2 describe-load-balancers --query 'length(LoadBalancers)' --output text
check load_balancers_classic 0 aws elb describe-load-balancers --query 'length(LoadBalancerDescriptions)' --output text

# Data services (P3+, checked so a leftover cannot hide)
check rds_instances         0 aws rds describe-db-instances --query 'length(DBInstances)' --output text
check rds_snapshots_manual  0 aws rds describe-db-snapshots --snapshot-type manual --query 'length(DBSnapshots)' --output text
check rds_clusters          0 aws rds describe-db-clusters --query 'length(DBClusters)' --output text
check rds_cluster_snapshots_manual 0 aws rds describe-db-cluster-snapshots --snapshot-type manual --query 'length(DBClusterSnapshots)' --output text
check rds_subnet_groups     0 aws rds describe-db-subnet-groups --query 'length(DBSubnetGroups)' --output text
check sqs_queues            0 aws sqs list-queues --query 'length(QueueUrls || `[]`)' --output text
check secrets               0 aws secretsmanager list-secrets --query 'length(SecretList)' --output text

# P4 (DRF-46): the shared RDS and what the window creates around it. Secrets
# scheduled for deletion still exist (recoverable), so they are counted too:
# sandbox secrets are deleted without a recovery window, and the RDS-managed
# master secret must be gone after the instance is destroyed.
check rds_snapshots_automated 0 aws rds describe-db-snapshots --snapshot-type automated --query 'length(DBSnapshots)' --output text
check rds_automated_backups 0 aws rds describe-db-instance-automated-backups --query 'length(DBInstanceAutomatedBackups)' --output text
check p4_secrets_incl_pending 0 aws secretsmanager list-secrets --include-planned-deletion --filters Key=name,Values=zero-drift/rag/ --query 'length(SecretList)' --output text
check rds_managed_secrets_incl_pending 0 aws secretsmanager list-secrets --include-planned-deletion --filters Key=name,Values=rds! --query 'length(SecretList)' --output text
check p4_buckets            0 aws s3api list-buckets --query "length(Buckets[?starts_with(Name, 'zero-drift-rag-')])" --output text
check p4_iam_roles          0 aws iam list-roles --query "length(Roles[?starts_with(RoleName, 'zero-drift-rag-')])" --output text
check kms_customer_aliases  0 aws kms list-aliases --query "length(Aliases[?!starts_with(AliasName, 'alias/aws/')])" --output text

# P6 (DRF-77): batch queues and roles, and what Karpenter launches outside
# Terraform. Karpenter nodes, their launch templates and Spot requests are made
# by the controller, so a destroy cannot see them; count them here. Instances
# still shutting down are counted (they bill until terminated).
check p6_karpenter_instances 0 aws ec2 describe-instances --filters Name=tag-key,Values=karpenter.sh/nodepool Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped --query 'length(Reservations[].Instances[])' --output text
# v1.15.3 tags its launch templates eks:eks-cluster-name and karpenter.k8s.aws/ec2nodeclass
# (pkg/apis/v1/labels.go; DeleteAll filters on both). Either tag counts.
check p6_karpenter_launch_templates 0 aws ec2 describe-launch-templates --filters Name=tag-key,Values=eks:eks-cluster-name,karpenter.k8s.aws/ec2nodeclass --query 'length(LaunchTemplates)' --output text
check spot_requests_open    0 aws ec2 describe-spot-instance-requests --filters Name=state,Values=open,active --query 'length(SpotInstanceRequests)' --output text
check p6_iam_roles          0 aws iam list-roles --query "length(Roles[?starts_with(RoleName, 'zero-drift-batch-') || starts_with(RoleName, 'zero-drift-karpenter-')])" --output text
check p6_instance_profiles  0 aws iam list-instance-profiles --query "length(InstanceProfiles[?starts_with(InstanceProfileName, 'zero-drift-')])" --output text
check p6_eventbridge_rules  0 aws events list-rules --name-prefix zero-drift-karpenter --query 'length(Rules)' --output text
check p6_buckets            0 aws s3api list-buckets --query "length(Buckets[?starts_with(Name, 'zero-drift-batch-')])" --output text

# Logs and identity in the project boundary
check eks_log_groups        0 aws logs describe-log-groups --log-group-name-prefix /aws/eks --query 'length(logGroups)' --output text
check oidc_providers        0 aws iam list-open-id-connect-providers --query 'length(OpenIDConnectProviderList)' --output text
check p3_iam_roles          0 aws iam list-roles --query "length(Roles[?starts_with(RoleName, 'zero-drift-p3-')])" --output text

# Retain allowlist (COST_PLAN §11.3): the Terraform state bucket only.
check s3_buckets            1 aws s3api list-buckets --query 'length(Buckets)' --output text

# Everything still carrying the project tag, by service:type (names never printed;
# an S3 ARN holds only the bucket name, so it is shown as s3:bucket).
echo "tagged Project=Zero-D-Rift by type:"
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=Zero-D-Rift \
    --query 'ResourceTagMappingList[].ResourceARN' --output json \
    | jq -r '.[] | split(":") | if .[2] == "s3" then "s3:bucket" else "\(.[2]):\(.[5] | split("/")[0])" end' | sort | uniq -c | sed 's/^/  /'

echo
if (( failed )); then echo "RESULT: NOT CLEAN (see LEFT/ERROR lines)"; exit 1; fi
echo "RESULT: CLEAN (only the retain allowlist remains)"
