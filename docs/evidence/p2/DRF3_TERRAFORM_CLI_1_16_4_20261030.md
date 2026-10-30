# DRF-3 — Terraform CLI exact pin 1.16.4 install and verification — 2026-10-30

Issue: DRF-3 (Linear). Sources: SPEC-P2 Task 1–2, `P2_T1_DECISION_REVIEW.md`.
Candidate: HEAD `e8f6d69` plus uncommitted workflow/documentation diff (no
infrastructure or Terraform configuration change). Timezone: Asia/Saigon.
Implementer: owner (owner terminal). Reviewer: Claude (independent re-check below).

## Authority

Owner explicitly chose to install DRF-3 themself on 2026-10-30 after the bash
procedure was reviewed in session. Scope: download, checksum-verify and place
the Windows amd64 binary only. No provider/module download, `init`, lab, AWS,
IAM/backend/quota mutation, commit or push was part of this authority.

## Procedure and owner observations (21:28–21:31)

Official source: `https://releases.hashicorp.com/terraform/1.16.4/`.

| Step | Command (bash) | Observed result |
|---|---|---|
| Download | `curl -fLO .../terraform_1.16.4_windows_amd64.zip` | 36,761,827 bytes |
| Checksums | `curl -fLO .../terraform_1.16.4_SHA256SUMS` | 1,592 bytes |
| Verify | `sha256sum -c --ignore-missing terraform_1.16.4_SHA256SUMS` | `terraform_1.16.4_windows_amd64.zip: OK` |
| Extract | `unzip -o terraform_1.16.4_windows_amd64.zip -d bin` | `LICENSE.txt`, `terraform.exe` |
| Keep rollback | `mv <tools>/Terraform/terraform.exe <tools>/Terraform/terraform-1.14.8.exe` | exit 0 |
| Install | `cp bin/terraform.exe <tools>/Terraform/terraform.exe` | exit 0 |

`<tools>` is an owner-local tool directory already on PATH, outside the user
profile; no administrator rights were needed. Download directory redacted.

## Independent reviewer re-check (Claude, Git Bash, after install)

| Check | Result |
|---|---|
| `hash -r; command -v terraform` | resolves to `<tools>/Terraform/terraform` |
| `terraform version` | `Terraform v1.16.4` / `on windows_amd64` |
| Re-run `sha256sum -c --ignore-missing` on the downloaded zip | `OK` |
| `cmp` extracted binary vs installed binary | identical |
| SHA-256 of installed `terraform.exe` | `d1f5754b41b44c7e4ce7283780d2ccb9492f2c32c9629555686fc29fa8067349` |
| Rollback binary `terraform-1.14.8.exe version` | `Terraform v1.14.8` / `on windows_amd64` |
| CLI config | no `.terraformrc` / `terraform.rc`; `%APPDATA%/terraform.d` holds only checkpoint files |
| Warnings | only the upgrade notice (latest 1.17.1); no `terraform.d` Access denied warning |

The upgrade notice is expected: the pin stays exactly 1.16.4 and is not
auto-upgraded. The earlier Codex `terraform.d` Access denied observation remains
classified `CODEX_EXECUTION_BOUNDARY_ONLY / NOT_REPRODUCED_OWNER_TERMINAL`; this
record does not reclassify it, since Claude's shell is not the Codex sandbox.

## Acceptance criteria

| AC | Result | Evidence |
|---|---|---|
| AC-01 source/checksum/version/path reviewed before execution | PASS | official release URL, SHA256SUMS, Windows amd64, existing PATH directory |
| AC-02 separate owner approval | PASS | owner chose and ran the install themself on 2026-10-30 |
| AC-03 version/path/checksum/warning recorded; Codex observation separate | PASS | tables above |
| AC-04 no learning promotion; sanitized evidence | PASS | learning levels unchanged; no account ID, secret or user-profile path |

## Findings and limits

1. Low — the SHA256SUMS file was verified only by HTTPS origin, not by its
   HashiCorp GPG signature (`terraform_1.16.4_SHA256SUMS.sig`). Optional hardening;
   not required by the DRF-3 acceptance criteria.
2. Process — no work-claim comment was recorded on DRF-3 before execution. The
   install touched only an owner-local directory, so no file overlap occurred.
3. Step 1 (pre-install `terraform version`) output was not captured; the kept
   rollback binary reporting 1.14.8 confirms the prior version.

Not covered: provider/module downloads, `terraform init`, lockfile, any AWS or
L3 claim. Learning: installing a binary does not raise Terraform above
Foundation/basic; P2-T2 (DRF-4) lab remains READY_NOT_STARTED.

Status: CANDIDATE_FOR_OWNER_ACCEPTANCE. Owner accepts closure on Linear.
