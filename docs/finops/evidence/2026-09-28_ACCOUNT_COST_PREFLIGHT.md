# Task 5 account and price preflight evidence

- Observed date: 2026-09-28
- Region: `us-east-1`
- Evidence class: redacted read-only account/API output
- AWS resources created: none
- Quota increase requested: none

## Credit check

The account identifier was resolved in memory from STS and was not printed or
stored. The command shape was:

```text
aws billing get-credits \
  --account-id <redacted-current-account> \
  --start-date 2025-09-29T00:00:00Z \
  --region us-east-1
```

Observed result:

```json
{
  "type": "Promotion",
  "initialUsd": "100.000000",
  "remainingUsd": "100.000000",
  "estimatedUsd": "100.000000",
  "start": "2026-06-13T13:39:33+07:00",
  "end": "2027-06-13T13:39:33+07:00",
  "status": "ENABLED"
}
```

The returned applicable-product list contained the project-relevant services
below:

- Amazon Elastic Container Service for Kubernetes (EKS product name);
- Amazon Elastic Compute Cloud;
- Amazon Relational Database Service;
- Amazon Simple Storage Service;
- Amazon Simple Queue Service;
- Amazon Virtual Private Cloud;
- Amazon EC2 Container Registry (ECR);
- Elastic Load Balancing;
- AmazonCloudWatch and AWS CloudTrail;
- AWS Secrets Manager and AWS Key Management Service;
- AWS Data Transfer and AWS Budgets.

The owner reported a separate guide reward worth another 100 USD that has not
been completed. It is `UNVERIFIED` and is not included in the current balance or
the project's spending envelope.

## AWS Price List API check

The official `pricing get-products` API returned these On-Demand unit prices for
US East (N. Virginia):

| Item | Unit price (USD) |
| --- | ---: |
| Linux `m6i.large` | 0.096 per instance-hour |
| Linux `t3.medium` | 0.0416 per instance-hour |
| Linux `g4dn.xlarge` | 0.526 per instance-hour |
| RDS PostgreSQL Single-AZ `db.t4g.micro` | 0.016 per instance-hour |
| EBS gp3 | 0.08 per GB-month |
| RDS PostgreSQL Single-AZ gp3 | 0.115 per GB-month |
| Additional RDS PostgreSQL backup storage | 0.095 per GB-month |
| NAT Gateway | 0.045 per gateway-hour plus 0.045 per processed GB |
| PrivateLink interface endpoint | 0.01 per endpoint-hour plus 0.01 per GB up to 1 PB/month |
| In-use or idle public IPv4 | 0.005 per address-hour |

Price List API evidence proves the dated public unit price, not future capacity,
Spot availability, a final invoice, free-tier applicability or coverage of every
SKU by the promotional credit.
