# A synthetic P6 window plan that passes plan_assert checks 19-21 (DRF-77).
# Input: $ok = tests/p6_approved_policies.json .policies with ACCT replaced by
# the fake account. Used only by tests/plan_assert_guards.sh; holds no real value.
def iss: "oidc.eks.us-east-1.amazonaws.com/id/TEST";
def acct: "000000000000";
def trust(sub):
  {Version: "2012-10-17", Statement: [{
    Effect: "Allow", Action: "sts:AssumeRoleWithWebIdentity",
    Principal: {Federated: ("arn:aws:iam::" + acct + ":oidc-provider/" + iss)},
    Condition: {StringEquals: {(iss + ":aud"): "sts.amazonaws.com", (iss + ":sub"): sub}}}]} | tojson;
def rc(type; name; after): {mode: "managed", type: type, name: name, address: ("module.x." + type + "." + name),
  change: {actions: ["create"], after: after, after_unknown: {}}};
def kar(type; name; after): rc(type; name; after) | .address = ("module.karpenter[0]." + type + "." + name);
def qarn(n): "arn:aws:sqs:us-east-1:" + acct + ":" + n;
def tls(n): {Sid: "DenyInsecureTransport", Effect: "Deny", Principal: "*", Action: "sqs:*", Resource: qarn(n),
  Condition: {Bool: {"aws:SecureTransport": "false"}}};

{resource_changes: (([
  rc("aws_sqs_queue"; "main"; {name: "zero-drift-batch", visibility_timeout_seconds: 120, message_retention_seconds: 3600,
     sqs_managed_sse_enabled: true, redrive_policy: ({deadLetterTargetArn: qarn("zero-drift-batch-dlq"), maxReceiveCount: 3} | tojson)}),
  rc("aws_sqs_queue"; "dlq"; {name: "zero-drift-batch-dlq", visibility_timeout_seconds: 30, message_retention_seconds: 3600, sqs_managed_sse_enabled: true}),
  kar("aws_sqs_queue"; "interruption"; {name: "zero-drift-karpenter", visibility_timeout_seconds: 30, message_retention_seconds: 300, sqs_managed_sse_enabled: true}),
  rc("aws_sqs_queue_policy"; "main"; {policy: ({Version: "2012-10-17", Statement: [tls("zero-drift-batch")]} | tojson)}),
  rc("aws_sqs_queue_policy"; "dlq"; {policy: ({Version: "2012-10-17", Statement: [tls("zero-drift-batch-dlq")]} | tojson)}),
  kar("aws_sqs_queue_policy"; "interruption"; {policy: ({Version: "2012-10-17", Statement: [
     {Sid: "AllowEventBridge", Effect: "Allow", Principal: {Service: ["events.amazonaws.com", "sqs.amazonaws.com"]},
      Action: "sqs:SendMessage", Resource: qarn("zero-drift-karpenter")},
     {Sid: "DenyHTTP", Effect: "Deny", Principal: "*", Action: "sqs:*", Resource: qarn("zero-drift-karpenter"),
      Condition: {Bool: {"aws:SecureTransport": "false"}}}]} | tojson)}),
  rc("aws_iam_role"; "keda"; {name: "zero-drift-batch-keda", assume_role_policy: trust("system:serviceaccount:keda:keda-operator")}),
  rc("aws_iam_role"; "submit"; {name: "zero-drift-batch-submit", assume_role_policy: trust("system:serviceaccount:zdr-platform:batch-submit")}),
  rc("aws_iam_role"; "tenant-a"; {name: "zero-drift-batch-tenant-a", assume_role_policy: trust("system:serviceaccount:tenant-a:batch-train")}),
  rc("aws_iam_role"; "tenant-b"; {name: "zero-drift-batch-tenant-b", assume_role_policy: trust("system:serviceaccount:tenant-b:batch-train")}),
  kar("aws_iam_role"; "controller"; {name: "zero-drift-karpenter-controller", assume_role_policy: trust("system:serviceaccount:karpenter:karpenter")}),
  kar("aws_iam_role"; "node"; {name: "zero-drift-karpenter-node", assume_role_policy: ({Version: "2012-10-17", Statement: [
     {Sid: "EC2Only", Effect: "Allow", Principal: {Service: "ec2.amazonaws.com"}, Action: "sts:AssumeRole"}]} | tojson)}),
  kar("aws_iam_role_policy_attachment"; "node1"; {policy_arn: "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"}),
  kar("aws_iam_role_policy_attachment"; "node2"; {policy_arn: "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"}),
  kar("aws_iam_role_policy_attachment"; "node3"; {policy_arn: "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"}),
  kar("aws_iam_instance_profile"; "node"; {name: "zero-drift-karpenter-node", role: "zero-drift-karpenter-node"}),
  kar("aws_eks_access_entry"; "node"; {type: "EC2_LINUX"}),
  rc("aws_subnet"; "public"; {tags: {Tier: "public", "karpenter.sh/discovery": "zero-drift"}}),
  rc("aws_subnet"; "public"; {tags: {Tier: "public", "karpenter.sh/discovery": "zero-drift"}}),
  rc("aws_subnet"; "database"; {tags: {Tier: "db"}}),
  rc("aws_security_group"; "node"; {tags: {"karpenter.sh/discovery": "zero-drift"}})
]
+ ([["AWS Health Event", "aws.health"], ["EC2 Spot Instance Interruption Warning", "aws.ec2"],
   ["EC2 Instance Rebalance Recommendation", "aws.ec2"], ["EC2 Instance State-change Notification", "aws.ec2"]]
  | map(.[0] as $d | .[1] as $s
        | kar("aws_cloudwatch_event_rule"; $d; {event_pattern: ({source: [$s], "detail-type": [$d]} | tojson)}),
          kar("aws_cloudwatch_event_target"; $d; {arn: qarn("zero-drift-karpenter")}))))
+ [$ok | to_entries[] | rc("aws_iam_role_policy"; .key; {name: .key, role: ("zero-drift-" + .key), policy: ({Version: "2012-10-17", Statement: .value} | tojson)})]
)}
