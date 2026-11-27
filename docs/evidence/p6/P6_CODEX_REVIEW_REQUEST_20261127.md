# P6 — Codex review after the L3 window (2026-11-27)

> Requested by Claude for the owner (SPEC-P6 §5 P6-T4.3 "second-agent review").
> Scope: only what changed in or after window `P6-L3-20261126-01` where a mistake
> would give a **false PASS, too much IAM, or a broken next window**. The owner pastes
> the prompt below into Codex and copies its verdict, verbatim, into §Result.
> The pre-window review (rounds 1–4, APPROVE at `58c9982`) is in
> `P6_CODEX_REVIEW_REQUEST_20261125.md` and is not repeated.

## In scope (and why)

| Part | PR / files | Why it needs a second agent |
|---|---|---|
| IAM check fix | PR #105 (merged in the window, `407b751`) — `infra/terraform/scripts/batch_iam_check.sh`, `tests/batch_iam_matrix.json` | Merged under window time pressure. The matrix row `karpenter iam:ListInstanceProfiles` now simulates on `*`: could that hide a real over-grant? Can the `jq -r` path print or pass a wrong policy? |
| Karpenter access entry ordering | PR #108 — `infra/terraform/main.tf`, `modules/karpenter/main.tf`, `modules/karpenter/variables.tf` | Window error 3. The fix must make the access entry wait for the cluster without changing names, IAM or the plan shape |
| Runbook gate changes | PR #107 — `docs/runbooks/P6_L3_WINDOW.md` §4 (profile row), B1, C2, K3, F4, §6 H8 | H8 relaxes the gate for an S2 retry plan: is the replacement rule strong enough? Does any new command print an ID? |
| Window evidence | PR #107 — `docs/evidence/p6/P6-T4.2_L3_WINDOW_20261126.md` | Does any claim go beyond the recorded output (suite JSON, logs)? Is anything counted as PASS that was not? |

**Out of scope:** PR #99–#104 (window request PRs, one-line changes checked with
`git merge-tree`), PR #106 (P1g, two request files byte-identical to `8692146`).

## Prompt for Codex

```
Review, read-only, the post-window P6 changes of Zero-D-Rift. Do not run AWS, kind or
terraform apply. Read AGENTS.md, .agent/specs/SPEC-P6_BATCH_TRAINING_JOB.md (§5 P6-T4,
§9.5, D6) and docs/evidence/p6/P6-T4.2_L3_WINDOW_20261126.md §9 (errors) first.

Scope: PR #105 (merged; read on main 407b751), PR #108, PR #107.

Answer for each, with file:line:
1. False PASS: can batch_iam_check.sh pass while a role is broader than D2/D6? Is the
   ListInstanceProfiles row on "*" a real check or a hole? Can H8 (S2 retry plan) let a
   plan through that adds or changes something outside the approved full plan?
2. Terraform: does access_entry_cluster_name = module.cluster.cluster_name make
   aws_eks_access_entry.node wait for the cluster? Does it change any name, any IAM
   document, the plan shape hash, or make a value unknown at plan time? Is a cycle possible?
3. Runbook: does every new command fail loudly (READ_FAILED, not 0 or None counted as a
   pass)? K3 with length(Contents[]) prints None on an empty prefix: is that handled?
4. Evidence: is any statement in the T4.2 evidence not backed by the suite JSON or the
   logs it cites? Is any account ID, ARN, IP, queue URL, node or instance name present?
5. Anything else that would make the next window fail or cost more.

Verdict: APPROVE, or CHANGES with a numbered list (severity HIGH/MEDIUM/LOW, file:line, fix).
```

## Result

### Round 1 (27/11) — verbatim, as the owner pasted it

> REQUEST CHANGES — review sau window P6.
> Đã review #105 tại merge `407b751`, #108 tại `788ddbb`, #107 tại `05aa47f`. Có 2 finding cần sửa, đều trong phạm vi yêu cầu.
>
> 1. HIGH — H8 chưa bảo đảm retry giữ nguyên nội dung plan đã duyệt. Quy tắc hiện chỉ so địa chỉ, resource type và hành động create. Fixture đổi `principal_arn` và loại access entry từ `EC2_LINUX` sang `STANDARD` vẫn thỏa H8.
> Sửa tối thiểu: yêu cầu mỗi resource create trong retry giữ nguyên các giá trị đã biết của plan đầy đủ, gồm principal, loại access entry, IAM policy và cấu hình chi phí. Giá trị computed mới được giải quyết phải được đối chiếu theo reference tương ứng. Tiếp tục chặn mọi update, delete và replacement.
> Kiểm lại: retry nguyên resource thiếu phải qua. Cùng địa chỉ nhưng đổi principal, policy hoặc instance type phải bị chặn trước apply. [P6_L3_WINDOW.md:350](https://github.com/EurusDevSec/Zero-D-Rift/blob/05aa47f/docs/runbooks/P6_L3_WINDOW.md#L350)
> 2. MEDIUM — Evidence gán sai mốc bắt đầu cho thời gian B05 tenant-a. Evidence ghi Job xong khoảng `14:38:26`, nhưng B05 kết thúc `14:41:28`. Số 50/53 giây trong suite tính từ lúc bắt đầu B05, sau B04 và thời gian chờ queue, nên câu “50/53 giây sau Job” vượt dữ liệu.
> Sửa tối thiểu: tại dòng 124 và 173, ghi “50/53 giây từ lúc bắt đầu kiểm B05”, giữ mốc Job hoàn tất riêng và ghi chưa đo trực tiếp khoảng Job-complete → terminated. Đồng thời sửa B09 dòng 128 thành message của request `b09-extra`, vì message đó có run key khác run đang train.
> Kiểm lại: đối chiếu câu đã sửa với JSON B04/B05 và `timeline-c.log`, không cần mở window mới. [Evidence:124](https://github.com/EurusDevSec/Zero-D-Rift/blob/05aa47f/docs/evidence/p6/P6-T4.2_L3_WINDOW_20261126.md#L124) · [Evidence:173](https://github.com/EurusDevSec/Zero-D-Rift/blob/05aa47f/docs/evidence/p6/P6-T4.2_L3_WINDOW_20261126.md#L173) · [Evidence:128](https://github.com/EurusDevSec/Zero-D-Rift/blob/05aa47f/docs/evidence/p6/P6-T4.2_L3_WINDOW_20261126.md#L128)
>
> Các phần còn lại đạt trong phạm vi review
>
> * #105: `jq -r` lấy đúng policy object. Dòng `ListInstanceProfiles` trên `*` khớp action đã duyệt. PR không thay quyền IAM. Matrix là kiểm mẫu, còn `plan_assert` tiếp tục kiểm policy bằng approved JSON.
> * #108: dependency đi từ access entry qua output tới resource EKS. Không thấy vòng phụ thuộc. Tên, IAM document và cấu trúc action/address dùng tính shape hash giữ nguyên.
> * K3: chỉ giá trị `1` đạt yêu cầu. Runbook đã ghi rõ prefix rỗng không được tính đạt.
> * Hai JSON cục bộ xác nhận 14 PASS tenant-a, 5 PASS tenant-b. Quét các tài liệu #107 trong phạm vi không thấy định danh nhạy cảm.
>
> Đã chạy kiểm diff, syntax, `terraform validate`, format, IAM offline 87 ca/0 sai và fixture cục bộ. Bills dựa trên số owner ghi trong evidence. Không chạy AWS, kind hay Terraform apply. `terraform graph` chưa hoàn tất vì bước xác thực backend, nên kết luận dependency dựa trên source của module đã pin.

### Fixes after round 1 (Claude, 27/11, PR #107)

| # | Fix | Check |
|---|---|---|
| 1 HIGH | New `infra/terraform/scripts/retry_plan_check.sh`, wired into H8. It refuses a retry plan whose configuration or input variables differ from the full plan; any update, delete, replace or forget; a create not in the full plan, or not a create there; and any value the full plan already knew that differs (principal reference, access entry type, IAM policy, instance type, node count). Values unknown in the full plan must come from the same expressions (configuration equal) over resources that the retry does not change. It prints addresses and paths only. The runbook keeps the approved `tfplan` and saves the retry as `retry.tfplan` (gitignored) | `tests/retry_plan_check_test.sh`, 16 cases, in `scripts/check.sh` 3e: the missing access entry alone passes, and so does an identical recreated policy; `EC2_LINUX`→`STANDARD`, another principal reference, a changed cluster name, a known value turned unknown, another policy document, `m6i.xlarge`, node count 3, update, delete, replace, a foreign address, an empty retry and a non-plan input are each refused for their own reason; the output holds no value. **Not run on a real plan** (the window plans are gone) |
| 2 MEDIUM | Evidence §4 and §6: B05 is timed from the start of the B05 check (after B04), not from Job end; Job end is a separate row; Job end → `terminated` is marked not measured, with the `timeline-c.log` poll bound (about 3 minutes). B09 is a message of request `b09-extra`, another run key. New error row 10. `gitops/tests/batch-suite.sh` labels fixed ("from B05 start (after B04), not from Job end"; "request b09-extra, another run key") | checked against the suite JSON (B04 14:40:35Z, B05 14:41:28Z; tenant-b 15:47:56Z, 15:48:02Z), `timeline-c.log` (Pod `Succeeded` 14:38:26Z, `InstanceTerminating` 14:41:17Z, no NodeClaim 14:41:40Z) and the B05/B09 code (`t0=$SECONDS` at the start of B05; `REQUEST_ID=b09-extra`) |

### Prompt for round 2

```
Round 2, read-only, of the post-window P6 review (Zero-D-Rift). Your round-1 findings and
Claude's fixes are in docs/evidence/p6/P6_CODEX_REVIEW_REQUEST_20261127.md §Result. Review
PR #107 at its new head only for those fixes:
1. infra/terraform/scripts/retry_plan_check.sh and tests/retry_plan_check_test.sh: can a retry
   plan pass that changes a value, a reference, an input variable or an action of the approved
   full plan? Can an unreadable or empty input pass? Does any output print a value?
2. docs/runbooks/P6_L3_WINDOW.md H8: is the order (keep tfplan, plan retry.tfplan,
   plan_fingerprint, retry_plan_check) enough before apply?
3. Evidence §4, §6, §9 row 10 and gitops/tests/batch-suite.sh B05/B09 labels: do they now
   match the suite JSON, timeline-c.log and the code?
Verdict: APPROVE, or CHANGES with a numbered list (severity, file:line, fix).
```

### Round 2 (27/11) — verbatim, as the owner pasted it

> REQUEST CHANGES — #107 tại `9819ae2d1a83b78c7cbb50a52ed79e276edf2062`. Còn 1 finding MEDIUM trong script mới.
>
> * MEDIUM — Retry vẫn PASS khi mở rộng mảng hoặc object đã biết. `known_paths()` chỉ so các phần tử cũ. Fixture thêm `"m6i.xlarge"` vào `instance_types: ["m6i.large"]` vẫn trả `RESULT: PASS`. Thêm tag cũng được cho qua. [retry_plan_check.sh:36](https://github.com/EurusDevSec/Zero-D-Rift/blob/9819ae2/infra/terraform/scripts/retry_plan_check.sh#L36)
> Sửa gốc: so sánh đệ quy cả cấu trúc. Với subtree hoàn toàn đã biết, yêu cầu bằng nhau toàn bộ, gồm key và chiều dài mảng. Chỉ cho phép khác biệt hoặc bổ sung dưới đường dẫn được `after_unknown` của plan đầy đủ đánh dấu.
> Kiểm lại trong một lượt: giữ các ca hợp lệ hiện có, gồm principal vừa được resolve. Thêm ca âm cho phần tử mảng mới, key object mới và phần tử bị xóa. Các ca này phải FAIL, output chỉ nêu đường dẫn.
>
> B05/B09 — Closed. Evidence §4, §6, dòng lỗi 10 và nhãn suite đã khớp cách đo, timeline và request `b09-extra`. H8 đã giữ riêng hai file plan và đặt các lệnh kiểm trước apply, nhưng còn phụ thuộc vào finding trên.
> Đã chạy 16 test đi kèm — PASS, fixture bổ sung, `bash -n` và `git diff --check`. Fixture bổ sung tái hiện PASS oan nêu trên. Không sửa workspace, không chạy AWS, kind hay Terraform apply.

### Fixes after round 2 (Claude, 27/11, PR #107)

| # | Fix | Check |
|---|---|---|
| 1 MEDIUM | `known_paths()` replaced by a recursive `diff($o; $c; $u)` in `retry_plan_check.sh`. Outside a path the full plan's `after_unknown` marks `true`, objects must have the same keys, arrays the same length, leaves the same value. A missing, added or changed key or element is reported by path only. Runbook H8 says so | `tests/retry_plan_check_test.sh`, now 23 cases: the 16 earlier ones unchanged (missing access entry with a resolved principal still passes); new FAIL cases for an added instance type element (the Codex fixture), a removed element, an added `scaling_config` block, an added tag key, a removed tag key and a new top-level key; a new PASS case resolves a nested value the full plan marks unknown (`scaling_config[0].min_size`). The no-value check now also covers `m6i` and a tag value. **Still not run on a real plan** |

### Prompt for round 3

```
Round 3, read-only, of the post-window P6 review (Zero-D-Rift). Your round-2 finding and
Claude's fix are in docs/evidence/p6/P6_CODEX_REVIEW_REQUEST_20261127.md §Result. Review
PR #107 at its new head only for infra/terraform/scripts/retry_plan_check.sh (diff()) and
tests/retry_plan_check_test.sh: can a retry still pass that adds, removes or changes a key
or element outside the full plan's after_unknown? Does a legitimate retry (resolved
principal, nested unknown resolved) still pass? Does any output print a value?
Verdict: APPROVE, or CHANGES with a numbered list (severity, file:line, fix).
```

### Round 3 (27/11) — verbatim, as the owner pasted it

> **APPROVE** — #107 tại `a6cc55a31492d0fc27b8aa26bf3d25050244ff68`.
>
> **Finding MEDIUM vòng 2 — Closed.** `diff()` đã kiểm cả key, chiều dài mảng và giá trị ngoài các đường dẫn `after_unknown`. Các ca thêm, xóa hoặc đổi phần tử bị chặn. Principal và giá trị unknown lồng nhau được resolve vẫn qua. Không thấy PASS oan mới hay giá trị bị in ra trong các ca đã kiểm. [retry_plan_check.sh:41](https://github.com/EurusDevSec/Zero-D-Rift/blob/a6cc55a/infra/terraform/scripts/retry_plan_check.sh#L41)
>
> Đã chạy **23 test đi kèm và 6 fixture độc lập**, đều đúng kết quả mong đợi. `bash -n` và `git diff --check` qua.
>
> CI hiện **gitops, kyverno xanh**, **terraform đang chạy**. Review dựa trên fixture cục bộ, chưa thử với plan thật. Không sửa file, không chạy AWS, kind hay Terraform apply.

**Status:** the post-window review is closed with APPROVE at `a6cc55a` (#105 and #108 passed in round 1; #107 after rounds 2–3). Open limit: the S2 retry gate is proven on synthetic plans only, not on a real partial-apply plan.
