# A synthetic P4 window plan that passes plan_assert checks 14-17 (DRF-46).
# Input: $ok = approved policies from plan_assert.sh --approved (fake account).
# Used only by tests/plan_assert_guards.sh; holds no real value.
def iss: "oidc.eks.us-east-1.amazonaws.com/id/TEST";
def trust(op; sub):
  {Version: "2012-10-17", Statement: [{
    Effect: "Allow", Action: "sts:AssumeRoleWithWebIdentity",
    Principal: {Federated: ("arn:aws:iam::000000000000:oidc-provider/" + iss)},
    Condition: (if op == "StringEquals"
      then {StringEquals: {(iss + ":aud"): "sts.amazonaws.com", (iss + ":sub"): sub}}
      else {StringEquals: {(iss + ":aud"): "sts.amazonaws.com"}, StringLike: {(iss + ":sub"): sub}} end)}]} | tojson;
def role(n; op; sub):
  {mode: "managed", type: "aws_iam_role",
   change: {actions: ["create"], after: {name: n, assume_role_policy: trust(op; sub)}, after_unknown: {}}};

{resource_changes: ([
  {mode: "managed", type: "aws_db_instance", change: {actions: ["create"], after: {
    engine: "postgres", engine_version: "17.11", instance_class: "db.t4g.micro",
    allocated_storage: 20, max_allocated_storage: 0, storage_type: "gp3", multi_az: false,
    storage_encrypted: true, publicly_accessible: false, manage_master_user_password: true,
    iam_database_authentication_enabled: false, backup_retention_period: 0,
    skip_final_snapshot: true, deletion_protection: false, auto_minor_version_upgrade: false}}},
  {mode: "managed", type: "aws_vpc_security_group_ingress_rule", change: {actions: ["create"],
    after: {ip_protocol: "tcp", from_port: 5432, to_port: 5432, cidr_ipv4: null, cidr_ipv6: null,
            prefix_list_id: null, referenced_security_group_id: null},
    after_unknown: {referenced_security_group_id: true}}},
  role("zero-drift-rag-db-admin"; "StringEquals"; "system:serviceaccount:zdr-platform:rag-db-admin"),
  role("zero-drift-rag-bootstrap"; "StringEquals"; "system:serviceaccount:zdr-platform:rag-bootstrap"),
  role("zero-drift-rag-crossplane-s3"; "StringEquals"; "system:serviceaccount:crossplane-system:provider-aws-s3"),
  role("zero-drift-rag-tenant-a"; "StringLike"; "system:serviceaccount:tenant-a:rag-*"),
  role("zero-drift-rag-tenant-b"; "StringLike"; "system:serviceaccount:tenant-b:rag-*")
] + [$ok | to_entries[] | {mode: "managed", type: "aws_iam_role_policy",
  change: {actions: ["create"], after_unknown: {},
    after: {name: .key, policy: ({Version: "2012-10-17", Statement: .value} | tojson | gsub("rds!db-MASTER"; "rds!db-TEST-AbCdEf"))}}}])}
