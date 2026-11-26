# DRF-77 (P6-T3): Terraform `batch-platform` và `karpenter` (25/11/2026)

- **Nguồn:** SPEC `.agent/specs/SPEC-P6_BATCH_TRAINING_JOB.md` §5 P6-T3, D2, D3, D6, D8; A7; ADR-0008, ADR-0009.
- **Runbook để làm lại:** `docs/runbooks/P6_TERRAFORM.md`.
- **Người chạy:** Claude (speed mode), trên máy owner, Terraform 1.16.4, provider AWS 6.67.0 ở chế độ giả. Owner chưa tự chạy.
- **Quyền hạn:** chỉ code và test với provider giả. Không chạy `plan` thật, không `apply`, không tạo role, không gọi AWS.
- **Branch:** `hoang/drf-77-p6-t3-terraform`, tách từ `main` `b1ec157`.
- **Codex review:** chưa có.

**Kết quả: PASS ở mức tĩnh.** Chưa có bằng chứng nào về AWS runtime; phần đó là P6-T4.2.

## A. Module `batch-platform`

| Yêu cầu SPEC | Làm thế nào | Kiểm bằng |
|---|---|---|
| Queue và DLQ theo D8 | `zero-drift-batch`: visibility 120 s, giữ 3600 s, SSE-SQS, redrive sang `zero-drift-batch-dlq` sau 3 lần nhận. DLQ giữ 3600 s, SSE. Redrive-allow chỉ cho queue chính. Validation chặn giá trị khác D8 | tftest `queues_follow_d8_and_refuse_http`; plan_assert 19 (case âm: visibility 30, giữ 4 ngày, maxReceive 5, DLQ không SSE, redrive sang queue khác) |
| Queue không public | Policy mỗi queue chỉ có `Deny` khi `aws:SecureTransport = false`; không Allow nào | tftest; plan_assert 19 (case âm: Allow `*`, Allow principal AWS, DLQ không cấm HTTP) |
| Role KEDA | Trust `StringEquals` `keda:keda-operator`; chỉ `sqs:GetQueueAttributes` trên đúng queue | tftest `roles_trust_one_exact_service_account`; ma trận 6 case |
| Role submit | Trust `zdr-platform:batch-submit`; `SendMessage`; `PutObject` chỉ trên `…/runs/*/submit-started` và `…/runs/*/submitted`; `ListBucket` với `StringLike s3:prefix = runs/*/submitted`; không `GetObject` | tftest `tenant_and_submit_boundaries`; plan_assert 20 `P6 submit list` (case âm: bỏ điều kiện, prefix `runs/*`, thêm `GetObject`); ma trận 15 case |
| Role tenant | Trust `<tenant>:batch-train`; receive/delete/change visibility trên queue; list/get/put/delete chỉ trên `zero-drift-batch-<tenant>-*` | tftest; plan_assert 20 `P6 tenant separation` (case âm: tenant-a nhắc bucket tenant-b, tenant-b list mọi bucket batch); ma trận 19 + 19 case |
| Crossplane S3 thêm prefix `zero-drift-batch-` (A7) | Biến `extra_bucket_prefixes` của `rag-identity`, chỉ nhận đúng `zero-drift-batch-`; root chỉ truyền khi bật batch | tftest `crossplane_prefix_only_in_batch_window`; plan_assert so policy P4 có thêm prefix khi `P6_WINDOW=1` |
| Cờ `enable_batch_platform`, mặc định false | `count` trên hai module; validation bắt buộc `enable_rag_platform` (role Crossplane nằm ở `rag-identity`) | tftest `default_has_no_batch_platform`, `batch_without_rag_platform_is_rejected` |
| Output có ARN hoặc URL phải sensitive | `batch_platform` chỉ có tên; `batch_platform_config` (URL queue, ARN role) là `sensitive` | tftest đọc output |

## B. Module `karpenter`

| Yêu cầu SPEC | Làm thế nào | Kiểm bằng |
|---|---|---|
| Controller IRSA `karpenter/karpenter` | Trust `StringEquals`, aud `sts.amazonaws.com` | tftest; plan_assert 21 (case âm: thiếu audience) |
| Policy controller theo D6 | `cloudformation.yaml` v1.15.3 (đọc theo blob SHA) bỏ các lệnh ghi instance profile: 15 statement. `iam:PassRole` chỉ node role, điều kiện `iam:PassedToService = ec2.amazonaws.com`. `GetInstanceProfile` chỉ profile của mình; `ListInstanceProfiles` giới hạn `instance-profile/*` thay vì `*`. Các điều kiện tag cluster của bản gốc giữ nguyên | tftest `karpenter_has_no_iam_write`; plan_assert 20 `P6 karpenter no-iam-write`, `P6 no-iam-star`, `P6 PassRole` (case âm: thêm `CreateInstanceProfile`, thêm `iam:*`, PassRole `*`, PassRole không điều kiện, PassRole role khác); ma trận 24 case |
| Node role, profile, access entry | Trust `ec2.amazonaws.com`; `AmazonEC2ContainerRegistryPullOnly`, `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`; không SSM. Instance profile `zero-drift-karpenter-node`. Access entry `EC2_LINUX` | plan_assert 21 `P6 node role` (case âm: thêm SSM, thiếu profile, trust Lambda) |
| Queue gián đoạn + 4 rule EventBridge | `zero-drift-karpenter` giữ 300 s, SSE; chỉ `events`/`sqs` được gửi; cấm HTTP. 4 rule (Health, Spot interruption, rebalance, state-change) | plan_assert 21 `P6 interruption` (case âm: 3 rule, target sai queue) |
| Tag discovery | `karpenter.sh/discovery = <cluster>` qua biến tag của module network và cluster (không dùng `aws_ec2_tag`, tránh drift) | plan_assert 21 `P6 discovery tag` (case âm: SG thiếu tag, DB subnet có tag) |

## C. Guard và inventory

| Thứ | Kết quả |
|---|---|
| `terraform fmt -check -recursive`, `terraform validate` | OK |
| `terraform test` (toàn bộ) | 36 pass, 0 fail; trong đó `tests/batch_platform.tftest.hcl` 8 run |
| `tests/batch_iam_offline.sh` (ma trận 83 case, 5 role: 26 allowed, 57 implicitDeny) | `cases=83 wrong=0 roles=5`. Thử đột biến: bỏ điều kiện prefix của submit → 3 case sai, đúng như mong đợi; đã hoàn tác |
| `tests/plan_assert_guards.sh` | 101 case (P6: 52 = 18 PASS + 33 FAIL + 1 INFO); P3/P4/P5 cũ vẫn đúng. Xem dòng kết quả cuối ở mục E |
| `scripts/plan_assert.sh` | Check 3, 10, 12, 13 nhận thêm resource P6 khi `P6_WINDOW=1`; check mới 19–21. Ngoài window, check 3/12/13 vẫn cấm mọi resource P6 |
| `scripts/batch_iam_check.sh` | Mới. Access Analyzer + `simulate-custom-policy` từ plan đã lưu; `--principal` kiểm trust thật và `simulate-principal-policy`. Chưa chạy (cần AWS) |
| `scripts/inventory.sh` | Thêm 7 dòng đếm: instance có tag Karpenter (kể cả `shutting-down`), launch template của Karpenter, Spot request mở, role `zero-drift-batch-`/`zero-drift-karpenter-`, instance profile, rule EventBridge, bucket `zero-drift-batch-`. Queue đã có dòng `sqs_queues`. Chưa chạy (cần AWS) |

## D. Rủi ro và ghi chú cho bước sau

1. **Policy của role Terraform (R1) chưa thêm quyền SQS, EventBridge, instance profile.** R1 đang hoãn; nếu window dùng role đó, plan/apply sẽ bị từ chối. Phải giải quyết trước P6-T4.2.
2. **Node Karpenter dùng chung security group của node**, nên cũng tới được RDS 5432 như node hệ thống. Đây là khoảng hở đã biết từ P4; NetworkPolicy của P5 là lớp chặn trong cluster.
3. **4 rule EventBridge, không phải 5:** SPEC ghi bốn; rule capacity-reservation của bản gốc bị bỏ vì không dùng capacity reservation.
4. **`ListInstanceProfiles` bị giới hạn** thay vì `*`. Trong window phải đọc log Karpenter xem có lỗi `AccessDenied` khi khởi động không.
5. **Lệnh `cleanup` chỉ xoá message**, Job do operator xoá bằng `kubectl` (từ P6-T2.1). Đề xuất sửa câu chữ SPEC, chưa sửa.
6. **Tên ServiceAccount P6-T2.2 phải dùng đúng:** `keda/keda-operator`, `zdr-platform/batch-submit`, `<tenant>/batch-train`, `karpenter/karpenter`.

## E. Lần chạy cuối

`bash infra/terraform/scripts/check.sh` trên cây được commit: 11 dòng `PASS` (CLI, fmt,
validate, `terraform test`, guard plan_assert, `P6 IAM matrix (offline)`, lockfile,
module pin, không state/tfvars, không mẫu key/account ID, R1 JSON) và
`RESULT: PASS (static only; proves nothing about AWS)`, exit 0. Lần chạy guard
trước đó có 100/101 `ok`; case lệch (`p6-keda-policy-unknown`) là do câu `FAIL`
khác chữ với câu `PASS`, đã sửa câu trong plan_assert, và lần chạy cuối này đi
qua đủ guard. Ngoài ra `check-context.sh` PASS, `gitops/check.sh` PASS,
`git diff --check` sạch, quét ID không thấy account/ARN/IP thật (chỉ IP
TEST-NET-3 của tài liệu trong test có sẵn).
