# DRF-7 — P2-T3 Terraform root, version locks and static checks — 2026-10-31

Issue: DRF-7 (Linear). Source: SPEC-P2 Task 3, ADR-0007,
`docs/evidence/p2/P2_T1_DECISION_REVIEW.md` (pin table), `docs/finops/COST_PLAN.md` §10 (tags).
Candidate: HEAD `c6ee4cb` plus uncommitted `.gitignore` change and the new untracked
`infra/terraform/` (13 files). Environment: Windows 11, Git Bash, Terraform 1.16.4
windows_amd64. Timezone: Asia/Saigon. Cost: 0 USD. Tier: L0/L1 static and local.

## Who did what

| Actor | Work |
|---|---|
| Owner | Asked Claude to write the skeleton (31/10); approved `init -backend=false` and the provider lock in chat ("OK chạy init") |
| Claude | Wrote all files, ran init/lock/test/check; implementer, not an independent reviewer |

## Delivered

| Path | Content |
|---|---|
| `infra/terraform/versions.tf` | `required_version = "= 1.16.4"`; aws 6.67.0, tls 4.4.1, time 0.14.2, cloudinit 2.4.1, null 3.3.2 exact; module pin list |
| `infra/terraform/.terraform.lock.hcl` | 5 providers, windows_amd64 and linux_amd64 `h1:` hashes plus registry `zh:` hashes |
| `infra/terraform/backend.tf`, `backend.hcl.example` | Empty `backend "s3" {}`; ADR-0007 key `zero-d-rift/p2/terraform.tfstate`, `encrypt`, `use_lockfile`; bucket private |
| `infra/terraform/providers.tf` | Region and `default_tags`; no profile, key or account ID |
| `infra/terraform/variables.tf` | TF-T01 guardrails plus EKS = 1.35, AZs within the Region, required `run_id` and `expires_at` |
| `infra/terraform/locals.tf`, `outputs.tf` | Six mandatory tags; subnet CIDR layout; safe outputs only |
| `infra/terraform/tests/guardrails.tftest.hcl` | 7 runs against a mocked AWS provider |
| `infra/terraform/scripts/check.sh` | Static gate (CLI pin, fmt, validate, test, lockfile, module pins, Git visibility, sensitive patterns) |
| `infra/terraform/main.tf`, `README.md`, `run.tfvars.example` | Placeholder for DRF-8/DRF-9; layout and init procedure |
| `.gitignore` | Terraform state, plans, `.terraform/`, `backend.hcl`, `*.tfvars`, overrides, CLI config |

## Commands and results (31/10)

| Time | Command | Exit | Result |
|---|---|---|---|
| 14:11:58 | `terraform init -backend=false -input=false` | 0 | 5 providers installed, each "signed by HashiCorp"; lockfile created |
| 14:12 | `terraform providers lock -platform=windows_amd64 -platform=linux_amd64` | 0 | linux_amd64 checksums added; windows already tracked |
| 14:12 | `terraform test` (AWS credential env vars unset, mocked provider) | 0 | 7 passed, 0 failed |
| 14:13:19 | `terraform init -backend=false -lockfile=readonly` | 0 | lockfile matches the configuration |
| 14:13+ | `infra/terraform/scripts/check.sh` | 0 | 8 PASS lines, `RESULT: PASS` |
| 14:13+ | negative: untracked `neg-test.tf` with a fake 12-digit ID and account ARN, then removed | 1 | gate reports `FAIL sensitive pattern`; the first scan version also flagged hex hashes in the lockfile, so the boundary was tightened and re-checked |

Ignored files (`terraform.tfstate`, `backend.hcl`, `run.tfvars`) created as probes were
not visible to Git; probes removed. `.terraform/` (878 MB provider cache) is ignored.
No AWS API call, credential, backend init or plan against AWS was made.

## Acceptance criteria

| AC | Result | Reason |
|---|---|---|
| AC-01 exact CLI/provider/module/transitive pins, lockfile with command evidence | PASS (static) | pins match the approved table; lockfile and readonly init above. Module pins are declared and enforced by `check.sh` but no module is called yet, so module download/resolution is pending for DRF-8/DRF-9 |
| AC-02 variables, validation, tags and outputs contract; nothing sensitive tracked | PASS (static) | 7 guardrail tests; outputs exclude IDs/ARNs; Git visibility and pattern checks pass |
| AC-03 fmt/validate/secret checks with exit codes; init split local/backend | PASS (static) | `check.sh` exit 0; backend init documented only, needs DRF-6 authority |
| AC-04 owner explains root/state/provider boundary | PASS (explanation) | owner v2 below; runtime boundaries stay pending until DRF-5/DRF-6 |

## Owner explain-back (AC-04)

The owner answered in chat on 31/10. Claude typed it in verbatim, with diacritics
as given. v1 had gaps on module state, the state location and the provider role;
Claude explained them, then the owner wrote v2:

1. "root là /infra/terraform, module không tự chạy, state của module nằm trong
   playground\runs\TF-T01-20261030-01\terraform.tfstate"
2. "state thật nằm ở s3 bucket trên aws, vì nếu laptop thật mất file state có nghĩa
   tài nguyên sẽ bị mồ côi mà vẫn tốn tiền; giờ chỉ -backend=false vì bucket chưa tồn
   tại (sẽ làm ở drf-6) và chưa có phiên đăng nhập mfa (sẽ làm ở drf-5)"
3. "provider aws là phiên dịch viên vì terraform không biết aws là gì cho nên provider
   dịch các code tf sang lời gọi api của aws, đó là file 878mb vừa tải về; credential
   lấy từ sts, hết hạn sau vài giờ (làm ở drf5) chứ không nằm trong code vì để người
   khác biết là sẽ mất tài khoản"

Claude review: answers 2 and 3 are correct. Answer 1 is correct about the root and
modules not running alone. Its state example is the lab's root state; the general
rule is that module resources live in the state of the root that calls them (for this
root, the S3 key after DRF-6). Accepted with that note.

## Limits

Static and mocked results prove nothing about AWS API behavior, credentials, provider
schemas against real accounts, plans or runtime. No module has been downloaded. No
GPG verification beyond Terraform's own "signed by HashiCorp" check. Nothing committed.

## Status and next action

Owner re-check, 31/10 16:22 in the owner's own terminal, on the same candidate
(HEAD `c6ee4cb`, no `infra/terraform` file changed after this evidence was
written): `terraform init -backend=false -lockfile=readonly` reused all 5 locked
providers with no lockfile change; `scripts/check.sh` printed 8 PASS lines and
`RESULT: PASS`. This was a re-run on the same Windows machine, not a Codex code
review and not a clean-machine or Linux reproduction.

`CANDIDATE_FOR_OWNER_ACCEPTANCE`: AC-01 to AC-04 are met within static scope. Next:
the owner accepts and moves DRF-7 to Done.
