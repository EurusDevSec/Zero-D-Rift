# DRF-6 — P2 Terraform state backend (S3) — 2026-10-31

Issue: DRF-6 (Linear). Source: ADR-0007 "Decision — state backend", COST_PLAN §7.4, §11.3.
Procedure: `docs/runbooks/P2_STATE_BACKEND.md`.
Candidate: `main` at `c3044d1` plus this untracked documentation. Timezone: Asia/Saigon.
Redaction: account ID `<ACCOUNT>`, bucket name `<BUCKET>`.

## AC-01 — procedure, gross exposure, lifecycle owner

Claude wrote the procedure and `infra/iam/tfstate-bucket-policy.json.example`.
No AWS command was run while writing it.

| Item | Where in the runbook |
|---|---|
| Creation: name, `backend.hcl`, `create-bucket`, 5 controls, TLS-only policy | Steps 1–4 |
| Verification: 8 read-back commands with expected values | Step 5 |
| Terraform backend init and two-terminal lock test, no state written | Steps 6–7 |
| Recovery: stuck lock (`force-unlock` with approval), version restore by copy | Khôi phục |
| Cleanup: private state capture, delete all versions and markers, multipart check, delete bucket, 404 check | Dọn bucket |
| Gross exposure < 0.05 USD to 03/11, inside the P2 5 USD cap | Chi phí |
| Lifecycle owner and recovery custodian: HoangLV; 7-day review; checkpoint 03/11 | Chi phí, D2 |

Static checks: the policy JSON parses (`jq`); no 12-digit number in the new files.
Untested: every AWS step. Prices are list prices to recheck before approval.

Owner approved the procedure in chat on 31/10 ("Duyệt D1–D4"), with the recommended
decisions: D1 random-suffix bucket name kept only in `backend.hcl`; D2 `ExpiresAt`
tag at the 03/11 checkpoint (metadata only); D3 owner types the commands, Claude
reviews redacted output; D4 TLS-only bucket policy.
This approves the procedure only, not bucket creation (AC-02).

AC-01: PASS.

## AC-02 — fresh checks and creation approval

Step 0, owner-run 31/10 20:47–20:48 Asia/Saigon (redacted):

| Check | Command / place | Observed |
|---|---|---|
| Identity | `get-caller-identity --profile zdr-bootstrap` (MFA code entered) | `arn:aws:sts::<ACCOUNT>:assumed-role/zero-drift-bootstrap/hoang-bootstrap` |
| Session time | `jq .Credentials.Expiration` on the CLI cache | `2026-10-31T14:47:55+00:00` (21:47 local), ~60 min left |
| Bucket count | `aws s3api list-buckets --query 'length(Buckets)'` (profile `zdr-tf`) | `0`: no existing bucket, far below quota |
| Bills | Console Billing → Bills, October 2026 | Status Pending; total USD 0.00; tax 0.00 |
| Budget | Console Billing → Budgets | `zero-d-rift-project` 100.00 USD, used 0.00, health OK |

Creation approval: the owner wrote "Duyệt DRF-6 tạo bucket" in chat on 31/10, after the
step 0 results. Scope: runbook steps 1–7 (one dedicated bucket, 5 controls, TLS policy,
backend init, lock test). The owner types the commands (D3).

AC-02: PASS.

## AC-03 — physical controls and lock test

Authority: after the creation approval, the owner asked Claude in chat to finish the
issue ("hãy hoàn thành issue này luôn"). This changes D3 for this run: Claude ran
steps 1–7 with the owner's cached MFA session (`zdr-tf`, expiry 14:47:55Z). Claude
entered no MFA code.

Steps 1–4, Claude 31/10 13:54:35–13:54:51 UTC (20:54 local):

| Step | Command | Observed |
|---|---|---|
| 1 | name `zero-d-rift-tfstate-<8 hex>`, `backend.hcl` from the example | Placeholder gone (count 0); `git check-ignore`: `.gitignore:22:backend.hcl` |
| 2 | `aws s3api create-bucket --bucket <BUCKET>` | `"Location": "/<BUCKET>"`, exit 0 |
| 3 | public access block, ownership controls, SSE-S3, versioning, tagging | All 5 exit 0 |
| 4 | `put-bucket-policy` from `infra/iam/tfstate-bucket-policy.json.example` (temp file removed) | exit 0 |

Step 5 read-back (all match the runbook's expected values):

| Control | Observed |
|---|---|
| Location | `None` (us-east-1) |
| Public access block | `True True True True` |
| Object ownership | `BucketOwnerEnforced` |
| Default encryption | `AES256` (SSE-S3) |
| Versioning | `Enabled` |
| Policy status `IsPublic` | `False` |
| Policy | `DenyNonTlsAccess  Deny  aws:SecureTransport=false` |
| Tags | Project=Zero-D-Rift, Owner=HoangLV, Environment=PoC, ManagedBy=manual, RunId=DRF-6, Retain=true, RetainReason=terraform-state-backend, ExpiresAt=2026-11-03T10:00:00Z |

Not tested on purpose: a plain-HTTP request, because it would send the session token
unencrypted. The policy read-back is the evidence for the TLS rule.

Step 6, Claude 13:55 UTC:
- `run.tfvars` was made from the example with `run_id = DRF6-LOCKTEST-01`; `git check-ignore` shows it is ignored by `.gitignore:23:*.tfvars`.
- `terraform init -input=false -backend-config=backend.hcl -lockfile=readonly` exited 0; `.terraform/terraform.tfstate` records `"type": "s3"`.
- The bucket was empty after init.

Step 7, lock test with two processes on the same backend, Claude 13:55:53–13:56:56 UTC:

| Process | Action | Observed |
|---|---|---|
| T1 | `terraform apply -var-file=run.tfvars`, left waiting at `Enter a value:` | Holds the lock: `aws s3 ls` shows `terraform.tfstate.tflock` (265 B) |
| T2 | `terraform plan -var-file=run.tfvars -lock-timeout=5s` | `Error acquiring the state lock`; S3 `PutObject` 412 `PreconditionFailed`; Lock Info `Operation: OperationTypeApply`, `Version: 1.16.4`; exit 1 |
| T1 | answered `no` | `Apply cancelled.` `Releasing state lock`; exit 1 (expected for a cancelled apply) |
| T2 | `aws s3 ls .../zero-d-rift/p2/` | Empty: lock released, no state written |
| T2 | `terraform plan ... -lock-timeout=5s` | Runs (`Changes to Outputs`), exit 0 |

Left in the bucket by versioning: 2 noncurrent `.tflock` versions (264 B, 265 B) and
2 delete markers. No state object. No multipart uploads. No resource other than the
bucket was created. No lock file was deleted by hand.

AC-03: PASS.

## AC-04 — retention

Read back on the bucket: `Retain=true`, `RetainReason=terraform-state-backend`,
`ExpiresAt=2026-11-03T10:00:00Z` (metadata only). There is no lifecycle rule and no
automatic deletion. The bucket is created by CLI, outside any Terraform root, so an EKS
destroy cannot remove it. Review every 7 days; the 03/11 checkpoint is a review, not a
delete. Cleanup only after the orphan inventory and explicit approval (runbook "Dọn bucket").

AC-04: PASS (controls in place; the 03/11 review itself is a future action for the owner).

## Status

`CANDIDATE_FOR_OWNER_ACCEPTANCE`. AWS changes on 31/10: one S3 bucket (`<BUCKET>`)
with the 5 controls, TLS policy and 8 tags. Local private files, both gitignored:
`infra/terraform/backend.hcl` and `infra/terraform/run.tfvars`. The `infra/terraform`
working directory is now initialised with the S3 backend.

Expected cost: < 0.05 USD to 03/11. Open risks are listed in the runbook section
"Rủi ro còn mở". No independent reviewer yet: the owner or Codex should check this file.
