# P6 — Terraform `batch-platform` và `karpenter` (DRF-77, P6-T3)

Runbook để tự làm lại. Phần A–C không cần AWS, không cần credential và không tốn
tiền. Phần D chỉ dành cho window L3 (P6-T4.2), sau khi owner duyệt riêng.
Code: `infra/terraform/modules/batch-platform/`, `modules/karpenter/`, `main.tf`
(cờ `enable_batch_platform`), `scripts/plan_assert.sh` (check 19–21),
`scripts/batch_iam_check.sh`, `scripts/inventory.sh`, `tests/`.

## Bức tranh

Bật `enable_batch_platform = true` (chỉ trong window, và bắt buộc kèm
`enable_rag_platform = true`) thì Terraform tạo thêm 31 resource:

| Resource | Số lượng | Vai trò |
|---|---|---|
| `aws_sqs_queue` | 3 | `zero-drift-batch` (visibility 120 s, giữ 1 h, SSE, sau 3 lần nhận thì sang DLQ), `zero-drift-batch-dlq`, `zero-drift-karpenter` (hàng đợi báo Spot bị thu hồi, giữ 300 s) |
| `aws_sqs_queue_policy` + `aws_sqs_queue_redrive_allow_policy` | 3 + 1 | Cả ba queue cấm HTTP; không Allow cho `*`. Chỉ EventBridge được gửi vào queue Karpenter. DLQ chỉ nhận từ queue chính |
| `aws_iam_role` | 6 | `zero-drift-batch-keda`, `-submit`, `-tenant-a`, `-tenant-b`, `zero-drift-karpenter-controller`, `zero-drift-karpenter-node` |
| `aws_iam_role_policy` | 5 | Mỗi role IRSA một policy: `batch-keda`, `batch-submit`, `batch-tenant-a`, `batch-tenant-b`, `karpenter-controller` |
| `aws_iam_role_policy_attachment` + `aws_iam_instance_profile` + `aws_eks_access_entry` | 3 + 1 + 1 | Node role: 3 policy worker của EKS (không SSM), instance profile tạo sẵn, access entry `EC2_LINUX` |
| `aws_cloudwatch_event_rule` + `_target` | 4 + 4 | Health, Spot interruption, rebalance, state-change → queue Karpenter |

Ngoài ra: tag `karpenter.sh/discovery` trên 2 public subnet và security group
của node (sửa tại chỗ, không tạo resource mới), và role Crossplane S3 của P4 có
thêm prefix `zero-drift-batch-` (A7). Tắt cờ (mặc định) thì không có gì trong
số này và plan giống hệt P5.

Ai được làm gì (tên ServiceAccount mà P6-T2.2 phải dùng đúng):

```
keda/keda-operator          -> zero-drift-batch-keda        đọc độ sâu queue (GetQueueAttributes)
zdr-platform/batch-submit   -> zero-drift-batch-submit      gửi message; ghi 2 marker submit; list chỉ prefix runs/*/submitted; không GetObject
tenant-a/batch-train        -> zero-drift-batch-tenant-a    nhận/xoá/đổi visibility; chỉ bucket zero-drift-batch-tenant-a-*
tenant-b/batch-train        -> zero-drift-batch-tenant-b    như trên, chỉ của tenant-b
karpenter/karpenter         -> zero-drift-karpenter-controller  chính sách v1.15.3 bỏ phần ghi IAM; PassRole chỉ node role, chỉ cho EC2
```

Mọi trust đều `StringEquals` cho cả `sub` và `aud`. Mọi ARN trong policy được
dựng từ tên và account, nên plan đầu tiên đã thấy đủ policy và so được với file
duyệt `tests/p6_approved_policies.json`.

## A. Kiểm tĩnh (Git Bash, khoảng 25 phút trên Windows vì jq chậm)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
```

```bash
terraform init -backend=false -lockfile=readonly
```

```bash
bash scripts/check.sh
```

**Phải thấy:** `RESULT: PASS`, có dòng `PASS  P6 IAM matrix (offline)`.

Chỉ chạy phần của P6 (trên Windows, đường dẫn filter dùng `\`):

```bash
terraform test -no-color '-filter=tests\batch_platform.tftest.hcl'
```

```bash
bash tests/batch_iam_offline.sh
```

```bash
bash tests/plan_assert_guards.sh | grep p6-
```

**Phải thấy:** 8 run `pass`; `cases=83 wrong=0 roles=5`; 52 dòng `ok    p6-…`.

## B. Đoán trước khi đọc kết quả

Ghi dự đoán của bạn vào cột giữa trước, rồi mới mở cột phải.

| Câu hỏi | Dự đoán | Đáp án trong code |
|---|---|---|
| Role submit có đọc được nội dung marker `submitted` không? | | Không. Nó không có `s3:GetObject`; nó chỉ `ListBucket` với `s3:prefix` khớp `runs/*/submitted`, đủ để biết marker có hay chưa. Ma trận có case `GetObject` → `implicitDeny` |
| Karpenter tự tạo instance profile được không? | | Không (D6). Profile tạo sẵn bằng Terraform; controller chỉ có `GetInstanceProfile` trên đúng profile đó và `ListInstanceProfiles`. Không có `iam:Create*`, `iam:Add*`, `iam:Tag*` |
| Karpenter có `PassRole` role bootstrap được không? | | Không. Resource là đúng node role và có điều kiện `iam:PassedToService = ec2.amazonaws.com` |
| Một message lỗi mãi thì sao? | | Lần nhận thứ 4 không xảy ra: sau 3 lần SQS chuyển nó sang `zero-drift-batch-dlq` |
| Vì sao bật batch mà không bật rag thì Terraform từ chối? | | Role Crossplane tạo bucket checkpoint nằm trong module `rag-identity` của P4 |

## C. Tự thấy guard bắt lỗi

1. Mở `modules/batch-platform/main.tf`, trong statement `ListSubmittedMarkerOnly`
   xoá dòng `Condition = { StringLike = { "s3:prefix" = ["runs/*/submitted"] } }`.
2. Chạy `terraform test -no-color '-filter=tests\batch_platform.tftest.hcl'`.
   **Phải thấy:** run `policies_equal_the_approved_file` và
   `tenant_and_submit_boundaries` đều `fail`.
3. Hoàn tác:

```bash
git checkout -- modules/batch-platform/main.tf
```

`tests/plan_assert_guards.sh` làm tương tự trên plan giả: mỗi case đổi đúng một
chỗ (visibility 30, queue cho `*`, thêm `iam:CreateInstanceProfile`, PassRole
`*`, tenant-a nhắc bucket tenant-b, submit list không điều kiện, thêm SSM vào
node role, trust dùng `StringLike`, thiếu tag discovery…) rồi kiểm dòng tương
ứng là `FAIL`.

## D. Trong window L3 (P6-T4.2, cần phê duyệt riêng)

Đây chỉ là thứ tự; xem đầy đủ ở `docs/runbooks/P6_L3_WINDOW.md`. Không chạy bước
nào khi chưa có phê duyệt của window.

```bash
export AWS_PROFILE=zdr-tf AWS_REGION=us-east-1
```

```bash
terraform plan -var-file=run.tfvars -out=tfplan
```

```bash
ADMIN_WINDOW=1 P4_WINDOW=1 P5_WINDOW=1 P6_WINDOW=1 bash scripts/plan_assert.sh tfplan
```

```bash
bash scripts/batch_iam_check.sh tfplan
```

Sau apply (trust thật + toàn bộ ma trận trên role thật):

```bash
bash scripts/batch_iam_check.sh --principal
```

Sau destroy (các dòng `p6_*` và `spot_requests_open` phải bằng 0):

```bash
bash scripts/inventory.sh
```

## Hoàn tác toàn bộ (trước khi merge)

Nhánh này chỉ đổi code và test. Bỏ hết thay đổi chưa commit của P6-T3:

```bash
git restore infra/terraform && git clean -n infra/terraform
```

`git clean -n` chỉ liệt kê file mới; xoá chúng là việc của bạn (bỏ `-n` thành `-f`).
