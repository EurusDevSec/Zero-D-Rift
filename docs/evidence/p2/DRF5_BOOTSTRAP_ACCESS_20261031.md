# DRF-5 — P2 bootstrap access: MFA, temporary session and recovery — 2026-10-31

Issue: DRF-5 (Linear). Source: ADR-0007, COST_PLAN §7.4.
Procedure: `docs/runbooks/P2_BOOTSTRAP_ACCESS.md`.
Candidate: `main` at `8fe999b`. Environment: owner's Windows machine, AWS CLI,
us-east-1. Timezone: Asia/Saigon. Cost: 0 USD.
Redaction: account ID shown as `<ACCOUNT>`, IAM user name as `<USER>`.

## AC-01 — fresh identity and MFA observation (owner-run, read-only)

| Time | Command | Observed (redacted) |
|---|---|---|
| 31/10 ~17:05 | `aws sts get-caller-identity --query Arn` | `arn:aws:iam::<ACCOUNT>:user/<USER>` (IAM user, not a role) |
| 31/10 ~17:05 | `aws iam list-mfa-devices --query 'length(MFADevices)'` | `0` |
| 31/10 ~17:05 | `aws configure list-profiles` | `default` only |
| 31/10 17:08 | `aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled'` | `1` (root MFA on) |
| 31/10 17:09 | `aws iam list-attached-user-policies --user-name <USER>` | `AdministratorAccess` |
| 31/10 17:09 | `aws iam list-groups-for-user --user-name <USER>` | `[]` |

Reading: the CLI and Terraform currently use a long-lived IAM-user key that has full
admin rights and no MFA. This confirms the 02/10 snapshot (MFA=0) is still true. The
root account has MFA, so a last-resort recovery path exists. No federation profile
is configured; Identity Center was not checked in the console.

AC-01: PASS (redacted, owner-run).

## AC-02 — procedure review

Claude wrote the procedure (`docs/runbooks/P2_BOOTSTRAP_ACCESS.md`). The owner
approved it in chat on 31/10 ("Duyệt"), with the recommended decisions:
- D1: the role uses `AdministratorAccess` for now (no escalation over the user).
- D2: admin stays on the user until the role and recovery login are tested.
- D3: 1-hour sessions.

The approval lets the owner carry out steps 1–7. AC-02: PASS.

## AC-03 / AC-04

Owner execution log (owner-run, redacted):

| Step | Command / action | Observed |
|---|---|---|
| 1 MFA | Console: assign authenticator-app MFA `zdr-phone` to `<USER>` (owner) | `list-mfa-devices` count `1`; serial `arn:aws:iam::<ACCOUNT>:mfa/zdr-phone` |
| 2 trust file | `sed` placeholders → `~/zdr-trust.json` (owner); deleted by Claude after use | Principal `user/<USER>`, MFA present, MFA age < 3600 |
| 2 role | First owner attempt with `file://$HOME/...` failed (Windows CLI cannot read Git Bash `/c/...` paths). Claude at 19:31:57: `create-role` from `~` with a relative path, exit 0 | `get-role`: `MaxSessionDuration 3600`; tags Project/Owner/Environment/ManagedBy=manual; trust as above |
| 2 policy | Claude: `attach-role-policy AdministratorAccess` (D1), exit 0 | `list-attached-role-policies`: `AdministratorAccess` |
| 4 negative | Claude: `sts assume-role` as `<USER>` without MFA | `AccessDenied ... not authorized to perform: sts:AssumeRole`, exit 254: the MFA condition is enforced |
| 3 profiles | Claude: backed up `~/.aws/config` to `config.bak-20261031`, appended `zdr-bootstrap` (role, `source_profile=default`, `mfa_serial`, 3600 s) and `zdr-tf` (`credential_process` via `export-credentials`) | `list-profiles`: default, zdr-bootstrap, zdr-tf |
| 5 no-session | Claude: `zdr-tf get-caller-identity` with an empty cache, `timeout 20` | Hangs waiting for MFA (exit 124), no prompt: renew with `zdr-bootstrap` before Terraform |

| 4 session | Owner 19:41:21: `get-caller-identity --profile zdr-bootstrap`, entered MFA code | `arn:aws:sts::<ACCOUNT>:assumed-role/zero-drift-bootstrap/hoang-bootstrap` |
| 4 terraform profile | Owner 19:41:42: `get-caller-identity --profile zdr-tf` (no prompt) | Same assumed-role ARN: `zdr-tf` reuses the cached MFA session |
| 4 expiry | Owner 19:41:50: `jq .Credentials.Expiration` on the CLI cache | `2026-10-31T13:41:22+00:00` (20:41 Asia/Saigon): 1-hour session |

| 5 renewal | Owner: deleted `~/.aws/cli/cache/*.json`, re-ran `get-caller-identity --profile zdr-bootstrap` | A new MFA code was asked for and an ARN was printed (the owner pasted it truncated as `arn:aw`). Renewal route = re-run `zdr-bootstrap` with a fresh code |
| 6 pre-check | Claude: `iam get-login-profile --user-name <USER>` (read-only) | `NoSuchEntity`: the IAM user had no console password, so root was the only console path |
| 6 console | Owner, 31/10 evening: enabled console access for `<USER>` (own password, no reset), signed in through the IAM-user sign-in URL in a private window with password + MFA, opened EC2 in us-east-1 | The Instances page loaded (owner report). An independent recovery login path now exists |

Note: the CLI MFA prompt prints the MFA serial, including the account ID, on stderr,
so the `sed` redaction does not cover it. Never paste that prompt line into Git or Linear.

Authority: from step 2 on, the owner asked Claude in chat to run the steps itself
("hãy chạy luôn ... tôi cấp quyền phạm vi project này"). Claude cannot enter MFA
codes, so the owner must run the MFA session tests (4 positive, 5 renewal, 6 console).

AC-03: PASS (owner-run session, renewal and console recovery login; Terraform uses `zdr-tf` with no long-lived key in code).

## AC-04 — EKS access entries and elevation cleanup plan

Written by Claude as documentation only: `docs/runbooks/P2_BOOTSTRAP_ACCESS.md`, section
"Kế hoạch quyền vào EKS và gỡ quyền admin (AC-04)". It covers:
- the identity map: bootstrap role, observer role (not created), break-glass `<USER>`
  console + MFA through the EKS API, and root as the last resort;
- the required cluster settings: `authentication_mode = "API"`, creator admin off, a
  stable role ARN and a variable-controlled admin association;
- an elevation record template, then grant → use → disassociate → bounded wait →
  empty association list → a real admin action returns `Forbidden`;
- the destroy-whole-cluster shortcut;
- accepted limits: the role can self-escalate on EKS; a second human backup is SHOULD,
  not MUST; admin rights are temporary.

AC-04: PASS (plan). Runtime verification belongs to DRF-9 (code) and DRF-11 (window).

## Status

`CANDIDATE_FOR_OWNER_ACCEPTANCE`. Changes made in AWS on 31/10:
- the owner added the MFA device and user console access;
- Claude created role `zero-drift-bootstrap` with `AdministratorAccess` attached;
- the CLI profiles `zdr-bootstrap` and `zdr-tf` were added.

Open risks: admin on both role and user (D1/D2), the long-lived source key, no
observer role, no second human. Nothing is committed. An independent reviewer
(Codex or the owner) should check this file and the runbook before acceptance.
