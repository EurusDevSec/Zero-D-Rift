# P6 — one Codex review before the L3 window (2026-11-25)

> Requested by Claude for the owner (SPEC-P6 §9.3; L3 runbook §3 P4). One review
> for every P6 part where a mistake would give a **false PASS, a cost leak or too
> much IAM**. The owner pastes the prompt below into Codex and copies its verdict,
> verbatim, into §Result.

## In scope (and why)

| Part | PR / files | Why it needs a second agent |
|---|---|---|
| T3 Terraform IAM + Karpenter | PR #93 — `infra/terraform/modules/batch-platform/`, `modules/karpenter/`, `scripts/plan_assert.sh` (P6 checks), `scripts/batch_iam_check.sh`, `tests/batch_iam_matrix.json` | IAM breadth (`iam:PassRole`, EC2 create, SQS/S3 per tenant); node SG reach; cost (instances outside Terraform) |
| T2.2 RGD + static rules | PR #94 (merged 26/11, review on `main` `c7d779e`) — `gitops/platform/rgd/batch-training-job.yaml`, `gitops/platform/batch/`, `gitops/platform/apps/5{0,5,7}-*.yaml`, `gitops/check.sh` rules 19-23 | D5 (one Job), kro/KEDA label interaction (found on kind), NodePool limits/expiry, quota D9 |
| T4.1 suite + window helper | PR #96 — `gitops/tests/batch-suite.sh`, `infra/p6-window/window.sh` | Every B-case verdict: can any case PASS without the behaviour? Can a failed read become 0? Does any output leak an ID? |

**Out of scope:** T2.1 worker (PR #92, merged; 65 unit tests, smoke on S3Mock),
docs and the kind lab files. Codex may still flag them if it sees a blocker.

## Prompt for Codex

```
Review, read-only, the P6 batch-training candidate of Zero-D-Rift. Do not run AWS,
kind or terraform apply. Read AGENTS.md and .agent/specs/SPEC-P6_BATCH_TRAINING_JOB.md
(§4 scenarios, §5 P6-T2.2/T3/T4, §9.5 teardown, D1-D14) first.

Scope: PR #93 (Terraform batch-platform + karpenter, plan_assert P6, batch_iam_check),
PR #94 (merged; read it on main c7d779e: RGD batch-training-job, KEDA/Karpenter apps, NodePools, gitops/check.sh 19-23),
and PR #96 (gitops/tests/batch-suite.sh, infra/p6-window/window.sh).

Answer for each, with file:line:
1. False PASS: can any of B01-B14 or any check.sh / plan_assert rule pass while the
   behaviour it claims is absent? (e.g. a READ_FAILED or empty read counted as 0,
   a missing object treated as "none", a stale marker from another attempt.)
2. IAM: is any role broader than SPEC D2/D6 (KEDA read-only on the queue, submit send +
   prefix list, tenant own bucket prefix + own queue ops, Karpenter no IAM write and
   PassRole only on the node role)?
3. Cost: can a Karpenter node or a Spot request outlive teardown §9.5, or start outside
   NodePool limits (2 vCPU per pool, expireAfter 2h, WhenEmpty 60s)?
4. Leaks: can any output, log line, ConfigMap in Git, or evidence field print an account
   ID, ARN, queue URL, IP, node or instance name?
5. Window helper: does annotate/batch-config/purge/cleanup refuse on a failed read and
   never run cleanup while the request still exists (D3)?

Verdict: APPROVE or REQUEST CHANGES; findings as HIGH/MEDIUM/LOW with a concrete fix.
```

## Result

### Round 1 (26/11/2026): REQUEST CHANGES

The owner ran Codex once and pasted the result into the chat on 26/11/2026. Claude records it verbatim and
changes only one thing: absolute file links on the owner's machine become repository paths.

> **REQUEST CHANGES — Codex review P6 trước L3**
>
> Revision đã review: **#93** `bfec6116e6a813272409c4e1ea25f6cd396092d1`, **#94** trên `main` tại `c7d779e8501ed79c25ad45012e70cbeb954b074b`, **#96** `0c3298c0517b0c2bdf6a851a4c960fd75368b640`.
>
> ### HIGH
>
> | PR | File:dòng | Finding và sửa tối thiểu |
> |---|---|---|
> | #93 | `infra/terraform/modules/karpenter/main.tf:195` | **IAM hiện tại chặn teardown.** Karpenter v1.15.3 gọi `ListInstanceProfiles` và đọc profile legacy trước khi xóa launch template, kể cả khi dùng profile tạo sẵn. AWS yêu cầu `Resource: "*"` cho đúng action list này. Thêm ngoại lệ chỉ đọc cho action đó và quyền `GetInstanceProfile` giới hạn vào tên legacy của cluster. Cập nhật `plan_assert` và matrix tương ứng, giữ nguyên cấm IAM write. [AWS IAM](https://docs.aws.amazon.com/service-authorization/latest/reference/list_iam.html) · [Karpenter v1.15.3](https://github.com/aws/karpenter-provider-aws/blob/v1.15.3/pkg/controllers/nodeclass/controller.go#L163-L218) |
> | #94 | `gitops/check.sh:677` | **Rule 22 chặn cả bước chuyển On-Demand lẫn thao tác dừng khẩn cấp.** Guard chỉ chấp nhận CPU `"2"`, trong khi E1 và H2 yêu cầu đặt `"0"`. Cho phép đúng `"0"` hoặc `"2"` và giữ trần 2. Kiểm offline xác nhận cấu hình tắt Spot hiện bị từ chối. |
> | #94/#96 | `docs/runbooks/P6_L3_WINDOW.md:102` · F2 `:205` | **Preflight và teardown dùng sai tên app.** Manifest tạo `zdr-batch`, còn runbook chờ và xóa `zdr-karpenter-nodepools`. B3 cũng chờ `EC2NodeClass Ready` trước khi gắn IRSA cho Karpenter. Gắn IRSA sau khi ServiceAccount tồn tại và trước khi chờ AWS readiness. Khi dọn, dừng reconcile của root và `zdr-batch`, xóa hai NodePool, xác nhận 0 NodeClaim và EC2 rồi mới xóa `EC2NodeClass`, app batch và controller. |
> | #96 | `gitops/tests/batch-suite.sh:280` · B07 `:299` · B09 `:309` | **B06/B07/B09 có thể PASS dù thao tác thử thất bại.** B06/B07 bỏ qua lỗi delete rồi chấp nhận một Pod khác có log resume. B09 chỉ chấm số Pod/NodeClaim dù extra submit thất bại. Stub xác nhận cả ba nhánh vẫn ghi PASS. Yêu cầu checkpoint và delete thành công, xác nhận Job thay thế thuộc đúng attempt, và chỉ chấm B09 sau khi xác nhận message thứ hai đã gửi trong lúc run còn hoạt động. |
> | #96 | `gitops/tests/batch-suite.sh:222` · B05 `:232` | **B05 có thể trượt ngay khi teardown chạy đúng.** Suite đợi visibility timeout 120 giây rồi mới đọc `providerID`; Node có thể đã được thu hồi với `consolidateAfter: 60s`. Giữ `providerID` trong bộ nhớ lúc đọc nhãn Node và chỉ coi Node đã mất khi API xác nhận `NotFound` hoặc một lần list thành công không còn Node đó. |
>
> ### MEDIUM
>
> | PR | File:dòng | Finding và sửa tối thiểu |
> |---|---|---|
> | #93 | `infra/terraform/scripts/inventory.sh:74` | Inventory lọc launch template bằng tag khác với bản Karpenter đã pin. Template còn sót có thể bị đếm `0`. Dùng tag cluster và NodeClass mà Karpenter thực sự gắn. [Karpenter v1.15.3](https://github.com/aws/karpenter-provider-aws/blob/v1.15.3/pkg/providers/launchtemplate/launchtemplate.go#L465-L481) |
> | #93 | `infra/terraform/scripts/plan_assert.sh:388` · `infra/terraform/scripts/batch_iam_check.sh:101` | Hai cổng IAM có thể PASS oan. So policy theo tên và nội dung bỏ sót việc gắn policy vào sai role. Matrix thiếu hoặc lỗi JSON làm vòng lặp bỏ qua mọi mô phỏng nhưng vẫn in PASS. Kiểm policy gắn đúng role và xác thực matrix đọc được, hợp lệ, có ít nhất một ca trước khi mô phỏng. |
> | #94 | `gitops/check.sh:642` | Rule 20 chỉ tìm chuỗi `c.type == "Complete"`. Kiểm offline xác nhận một biểu thức luôn đúng vẫn qua guard. So khớp điều kiện `Complete=True` đầy đủ. RGD hiện tại dùng điều kiện đúng. |
> | #96 | `gitops/tests/batch-suite.sh:247` · B03 `:187` · B08 `:329` · report `:429` | B01 dùng `lastActiveTime` thay cho bằng chứng scaler đã tạo Job. B03 chỉ ghi trạng thái in-flight vào evidence, nên queue đọc lỗi vẫn có thể PASS. B08 chấm tổng DLQ thay vì message của attempt. `report` cũng chấp nhận các dòng PASS từ lần chạy cũ. Dùng bằng chứng Job của run hiện tại cho B01, đưa in-flight vào điều kiện chấm B03, đối chiếu run key trong DLQ và buộc report thuộc đúng mode/window. [KEDA v2.21.1](https://raw.githubusercontent.com/kedacore/keda/v2.21.1/pkg/scaling/executor/scale_jobs.go) |
> | #96 | `infra/p6-window/window.sh:185` | Cleanup từ chối đúng khi request còn tồn tại hoặc lần đọc request/ScaledJob lỗi. Tuy nhiên stub xác nhận lần đọc cuối thấy `jobs=1` vẫn in `OK` và trả `0`. Chỉ báo thành công sau lần đọc cuối thành công và danh sách Job/Pod liên quan rỗng. |
> | #93/#94/#96 | `gitops/tests/batch-suite.sh:341` · `infra/p6-window/window.sh:119` · `gitops/check.sh:36` · `infra/terraform/scripts/batch_iam_check.sh:90` | **Có đường lọt thông tin qua lỗi.** Lỗi `kubectl` có thể đưa IP vào JSON vì `scrub` chưa che IP dạng số. Lỗi AWS CLI có thể in định danh và URL ra stderr, còn guard GitOps in nguyên dòng chứa URL/ARN bị từ chối. Dùng mã lỗi cố định cho evidence và thông báo thất bại. Guard chỉ in tên file và số dòng. |
>
> Các policy batch hiện tại đúng phạm vi SQS/S3 đã duyệt. `PassRole` giới hạn đúng node role và EC2. `batch-config` là cấu hình runtime. `purge` đợi 60 giây sau khi cả hai queue được purge thành công. Trần NodePool là cấu hình Karpenter kiểm theo trạng thái cập nhật bất đồng bộ, nên vẫn cần giữ điều kiện dừng khi xuất hiện node thứ hai và kiểm inventory sau teardown. [Karpenter NodePools](https://karpenter.sh/v1.15/concepts/nodepools/)
>
> **Kiểm tra:** `git diff --check` trên cả ba diff, `bash -n` cho hai script #96, `gitops/check.sh` và `check-context` đều qua. Đã dùng stub offline và fixture trong bộ nhớ cho các ca nêu trên. Review dựa trên Git diff và mã nguồn upstream đã pin vì Zero-D-Rift chưa có index GitNexus. Không sửa file, không chạy AWS, kind hay Terraform apply.

### Round 1 fixes

Claude applied every finding on 26/11; none was disputed. #93 fixes are on its own branch, #94 and #96 fixes on #96.

| # | Finding | Change | Checked |
|---|---|---|---|
| H1 | #93 Karpenter IAM blocks teardown | `iam:ListInstanceProfiles` on `*` (alone in its statement, read-only); `iam:GetInstanceProfile` on the node profile and the legacy name `zero-drift_*` (v1.15.3 `LegacyInstanceProfileName` = `<cluster>_<hash>`). No IAM write. Approved JSON, tftest, `plan_assert` no-iam-star (one named exception) and matrix (+4 rows: legacy read allowed, legacy delete/remove-role denied, other profile denied) follow | `infra/terraform/scripts/check.sh`, guard tests, offline matrix |
| H2 | #94 rule 22 refuses `cpu: "0"` | rule 22 accepts `limits.cpu` `"2"` or `"0"`, never above 2 | `check_guards.sh`: two allowed cases (E1, H2) PASS, limit `"4"` FAIL |
| H3 | runbook app name and IRSA order | B2 waits for `zdr-keda`, `zdr-karpenter`, then runs `annotate`; B3 waits for `zdr-batch` and `EC2NodeClass Ready`, then `batch-config` (with `export RUN_ID`). F2 stops `zdr-root` and `zdr-batch`, deletes only the two NodePools, counts 0 NodeClaim + 0 instance, then F3 deletes `EC2NodeClass`, app `zdr-batch`, controllers | read-through |
| H4 | B06/B07/B09 pass after a failed step | checkpoint wait, Pod/Job/node/NodeClaim reads and the delete must succeed, else the case and the ones after it record `blocked:<step>` (FAIL). The resumed Pod must carry this attempt's label and belong to a Job other than the deleted one (`backoffLimit: 0`). B09 needs `SUBMITTED` from the extra submit (fresh attempt number, never `ALREADY_SUBMITTED`), a Running Pod of this attempt at scoring, and visible+in-flight ≥ 2 | fake `kubectl`: failed delete → B06, B07, B09 `blocked:pod-delete-failed`, `report` FAIL |
| H5 | B05 reads `providerID` too late | `providerID` read with the Node labels while the Pod runs; node gone only on `NotFound` or a successful list without it | fake `kubectl`: present → not gone, NotFound → gone, connection error → not gone |
| M1 | #93 inventory launch template tag | filter `tag-key` `eks:eks-cluster-name` or `karpenter.k8s.aws/ec2nodeclass` (v1.15.3 `labels.go`); the account-wide `launch_templates` line stays | read-through |
| M2 | #93 IAM gates pass on wrong role or empty matrix | modules pass `role = aws_iam_role.X.name` (known in the plan); `plan_assert` "P6 policy attachment" needs policy NAME on role `zero-drift-NAME` (+2 guard cases). `batch_iam_check.sh` fails on an unreadable, invalid or empty matrix and when rows simulated ≠ rows in the matrix | guard tests |
| M3 | #94 rule 20 substring | `readyWhen` must equal the full `Complete && status == "True"` expression | guard case "submit readyWhen always true" FAIL |
| M4 | #96 B01/B03/B08/report | B01: a Complete KEDA Job of this attempt; B03: `inflight=1` in the verdict; B08: `dlq_own=1` from DLQ bodies matched on tenant/request/attempt; every row carries mode + `RUN_ID` (required on eks), `report` refuses rows of another run | DLQ parser stub (own=1 of 2); `report` refuses a row of run `old` and a row without run |
| M5 | #96 cleanup reports OK with jobs=1 | success only after a successful final read with 0 Jobs and 0 Pods | stub: none → OK rc 0; job left → FAIL rc 1; Pod left → FAIL rc 1 |
| M6 | leaks through errors | suite `scrub` masks numeric IPs; B11 errors are fixed codes; `window.sh` and `batch_iam_check.sh` discard aws/kubectl stderr and print fixed codes; `check.sh` prints only file:line for a refused ID or queue URL | scrub stub; guard case "refused secret reported by file:line only" |

Found while fixing (not in the review): on Windows, `OUT=$HOME/...` is a `/c/...` path that native `jq` cannot open, so `record` failed and the suite stopped without a message. The suite now converts `OUT` with `cygpath -m` and fails loudly if it cannot write.

### Round 2 (26/11/2026): REQUEST CHANGES

Codex re-checked, read-only, PR #93 at `9624ba5` and PR #96 at `181b033` against the upstream code pinned
for Karpenter v1.15.3. It ran `git diff --check`, `bash -n`, `gitops/check.sh`, `check-context` and offline stubs;
no AWS, kind or Terraform apply. Summary of its verdict (owner pasted it in Vietnamese; local links turned into repo paths):

| # | Status | Codex note |
|---|---|---|
| H1 | Closed | finalizer has the reads it needs with the pre-made profile; `ListInstanceProfiles` alone on `*`, `GetInstanceProfile` on the node profile and `zero-drift_*`; no IAM write, `PassRole` only for the node role via EC2 |
| H2 | Closed | Spot off and both pools off pass; CPU `"4"` refused |
| H3 | **Open, HIGH** | B2 still waits for `zdr-karpenter` Healthy before `annotate`, but v1.15.3 exits when its start-up EC2 check fails (`pkg/operator/operator.go` L104-120). Wait for Deployment and ServiceAccount to exist, annotate, then wait Healthy and `EC2NodeClass Ready` |
| H4 | **Open, HIGH** | B09 counts only Pods and NodeClaims: a stub with two active Jobs, one Pod and one NodeClaim passes. Require exactly one active Job (`gitops/tests/batch-suite.sh` B09) |
| H5 | Closed | `providerID` read while the Pod runs; node gone only on `NotFound` or a successful list without it |
| M1 | Closed | inventory uses the two pinned Karpenter launch template tags |
| M2 | Closed | attachment guard; missing or empty matrix `rc=1`; rows simulated = rows in the matrix |
| M3 | Closed | full `Complete=True` expression; always-true fixture refused |
| M4 | **Open, MEDIUM** | B08 passes with markers `1,3,4`: check exactly `1,2,3`. A `resume` rerun that fails leaves `report` PASS on the old rows of the same `RUN_ID`: invalidate a phase's rows when it starts |
| M5 | Closed | Job or Pod left, read error and request still present all `rc=1` |
| M6 | **Open, MEDIUM** | `rollout`, `wait`, `logs` in `infra/p6-window/window.sh` still pass `kubectl` stderr through; a connection-error stub printed an IP |
| new | MEDIUM | B03 can FAIL on a slow node: the 35 s start at Job creation; a worker that takes the message at 36 s fails. Wait for `inflight=1` within the start-up limit, then count three polls |
| new | LOW | the attachment guard prints the wrong role name; a role name holding an account ID would reach the log. Print only the policy name and `wrong-role` |

Least privilege (Codex): `ListInstanceProfiles` needs `*` (IAM has no resource scoping for it); `zero-drift_*` is narrow
enough for P6, though wider than the single legacy name derivable from region and EC2NodeClass name. Kept as is: the hash
is Karpenter's internal detail and pinning it would break on a region or name change.

### Round 2 fixes

| # | Change | Checked |
|---|---|---|
| H3 | runbook B2: wait only until `deploy/keda-operator`, `sa/keda-operator`, `deploy/karpenter`, `sa/karpenter` exist, run `annotate`, then wait for `zdr-keda`, `zdr-karpenter` Healthy; B3 unchanged (`zdr-batch`, `EC2NodeClass Ready`, `batch-config`) | read-through |
| H4 | B09 adds `jobs=N`: Jobs of the request's ScaledJob with `status.active > 0`; expected `jobs=1` (with `active=1` Running Pod of the attempt) | fixture: two active Jobs → 2, one active + one done → 1, none → 0 |
| M4 | B08 records the sorted `RECEIVED-n` set, expected `received=1,2,3`. Each phase first marks its old rows `RERUN_INCOMPLETE` (`invalidate`), so a rerun that stops early makes `report` FAIL | stubs: markers 1,3,4 → FAIL, 1,2,3 → PASS; 14 PASS rows + `dlq` stopped early → B08 `RERUN_INCOMPLETE`, `report` rc 1 |
| M6 | `window.sh` `rollout restart`, `rollout status`, `wait`, `logs` discard stderr and print `WRITE_FAILED`, `NOT_READY`, `NOT_COMPLETE`, `READ_FAILED`; no `kubectl` or `aws` call left without a redirect | grep of every call |
| B03 | B03 waits (≤ 20 min) for `inflight=1`, then three polls; never seeing it records `inflight-never-1` (FAIL) | stub: worker takes the message at the 8th stats read (~40 s) → B03 PASS |
| LOW | attachment guard prints `NAME:wrong-role` or `NAME:unknown-role`, never the role | guard case: role `zero-drift-<12 digits>` → `FAIL  P6 policy attachment: batch-keda:wrong-role` |
