# P4 — Terraform `shared-rds` và `rag-identity` (DRF-46, P4-T2.2)

Runbook để tự làm lại. Phần A–C không cần AWS, không cần credential và không tốn
tiền. Phần D chỉ dành cho window L3 (DRF-56), sau khi owner duyệt riêng.
Code: `infra/terraform/modules/shared-rds/`, `modules/rag-identity/`, `main.tf`
(cờ `enable_rag_platform`), `scripts/plan_assert.sh` (check 14–17),
`scripts/rag_iam_check.sh`, `scripts/inventory.sh`, `tests/`.

## Bức tranh

Khi bật cờ `enable_rag_platform = true` (chỉ trong window), Terraform tạo thêm 13
resource:

| Resource | Số lượng | Vai trò |
|---|---|---|
| `aws_db_instance` | 1 | PostgreSQL 17.11, `db.t4g.micro`, 20 GiB gp3, private, mã hoá, mật khẩu master do RDS giữ trong Secrets Manager |
| `aws_security_group` + `aws_vpc_security_group_ingress_rule` | 1 + 1 | Lối vào duy nhất: 5432/tcp từ security group của node |
| `aws_iam_role` | 5 | `zero-drift-rag-db-admin`, `-bootstrap`, `-tenant-a`, `-tenant-b`, `-crossplane-s3` |
| `aws_iam_role_policy` | 6 | Mỗi role một policy. Riêng db-admin có thêm `rag-db-admin-master` để đọc secret master |

Khi tắt cờ (mặc định), không có resource nào trong số này, và plan giống hệt P3.

Đường đi của một credential:

```
Pod (SA rag-bootstrap, ns zdr-platform)
  -> token do EKS OIDC ký (sub = system:serviceaccount:zdr-platform:rag-bootstrap, aud = sts.amazonaws.com)
  -> STS AssumeRoleWithWebIdentity
  -> role zero-drift-rag-bootstrap: trust chỉ khớp đúng sub đó (StringEquals)
  -> policy: đọc secret bootstrap; tạo/đọc/xoá secret dưới zero-drift/rag/tenant-a/ và tenant-b/
```

## A. Kiểm tĩnh (Git Bash, khoảng 5 phút)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
terraform init -backend=false -lockfile=readonly
bash scripts/check.sh
```

**Phải thấy:** `RESULT: PASS`. Bước `terraform test` lúc này chạy cả
`tests/rag_platform.tftest.hcl` (7 run), còn bước guard chạy 44 case.

Chỉ chạy test của P4, kèm tên từng run (trên Windows, đường dẫn dùng `\`):

```bash
terraform test -no-color '-filter=tests\rag_platform.tftest.hcl'
bash tests/plan_assert_guards.sh
```

## B. Đoán trước khi đọc kết quả

| Câu hỏi | Ghi dự đoán | Đáp án trong code |
|---|---|---|
| Role tenant-a có đọc được object trong bucket `zero-drift-rag-tenant-b-s2` không? Vì sao? | | Không. Resource là `zero-drift-rag-tenant-a-*/*`, nên không khớp. Ma trận: `tenant-a implicitDeny s3:GetObject` |
| Vì sao role tenant dùng `StringLike` còn role nền tảng dùng `StringEquals`? | | Tenant tin mọi SA `rag-*` trong namespace của nó (D6). Role nền tảng chỉ tin đúng một SA trong `zdr-platform`. Nếu nền tảng dùng pattern thì một tenant tạo được SA khớp pattern đó |
| Vì sao secret bootstrap ghi là `bootstrap-??????` mà không phải `bootstrap*`? | | Secrets Manager luôn thêm đúng 6 ký tự vào cuối ARN. `*` sẽ khớp cả `bootstrap-extra-…` (có case âm trong ma trận) |
| Role Crossplane xoá được object, thế có xoá được file state Terraform không? | | Không. Resource chỉ là `zero-drift-rag-*/*`. Ma trận có case `DeleteObject` trên bucket state |
| Plan đầu tiên của window có đọc được policy `rag-db-admin-master` không? | | Không. ARN secret master chỉ có sau khi tạo instance, nên `plan_assert` in `INFO` cho policy này, và `rag_iam_check.sh --principal` kiểm nó sau apply |

## C. Tự thấy guard bắt lỗi

1. Mở `modules/rag-identity/main.tf`, trong statement `ReadOwnObjects` đổi
   `"arn:aws:s3:::${var.bucket_prefix}${t}-*/*"` thành `"arn:aws:s3:::${var.bucket_prefix}*/*"`.
2. Chạy `terraform test -no-color '-filter=tests\rag_platform.tftest.hcl'`.
   **Phải thấy:** run `policies_are_exact_allowlists` và run `iam_matrix` đều `fail`.
3. Hoàn tác: `git checkout -- modules/rag-identity/main.tf`.

`tests/plan_assert_guards.sh` làm việc tương tự trên plan giả: đổi đúng một chỗ
(RDS public, ingress từ `0.0.0.0/0`, thêm `iam:PassRole`, tenant-a nhắc tới
tenant-b, role nền tảng tin namespace tenant…), rồi kiểm dòng tương ứng là `FAIL`.

## D. Trong window L3 (DRF-56, cần phê duyệt riêng)

Đây chỉ là thứ tự. Không chạy bước nào khi chưa có phê duyệt của window.

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
export AWS_PROFILE=zdr-tf AWS_REGION=us-east-1
# 0. AZ: instance class phải đặt được trong cả hai AZ của subnet group (us-east-1a, us-east-1b)
aws rds describe-orderable-db-instance-options --engine postgres --engine-version 17.11 \
  --db-instance-class db.t4g.micro --query 'OrderableDBInstanceOptions[0].AvailabilityZones[].Name' --output text
# 1. plan với cờ bật, rồi gate
terraform plan -var-file=run.tfvars -var enable_rag_platform=true -out=tfplan
ADMIN_WINDOW=1 P4_WINDOW=1 bash scripts/plan_assert.sh tfplan
bash scripts/rag_iam_check.sh tfplan          # Access Analyzer + mô phỏng; các dòng MASTER là SKIP
# 2. sau apply
bash scripts/rag_iam_check.sh --principal     # trust thật + toàn bộ ma trận, kể cả MASTER
# 3. sau destroy
bash scripts/inventory.sh                      # p4_* và rds_* phải bằng 0
```

**Phải thấy:**
- `plan_assert`: mọi dòng `P4 …` là `PASS`, ngoại trừ các dòng `INFO` cho trust (OIDC chưa có) và cho `rag-db-admin-master`.
- `rag_iam_check.sh --principal`: `RESULT: PASS`.
- `inventory.sh`: `RESULT: CLEAN`.

Không in output của `terraform output rag_platform_config`, vì nó chứa host,
ARN và account ID. Chỉ pipe nó thẳng vào `kubectl`, theo runbook của DRF-51/56.

**Lưu ý cho teardown (DRF-56):**
- Secret bootstrap `zero-drift/rag/platform/bootstrap` do Job `db-init` tạo, không phải Terraform. Không role P4 nào được phép xoá nó. Sau khi chạy `cleanup` các sandbox, owner xoá nó bằng role Terraform với `--force-delete-without-recovery`.
- Secret master `rds!db-…` do RDS quản lý. `inventory.sh` đếm cả các secret đang chờ xoá, nên sẽ thấy nếu RDS để nó lại trong thời gian chờ xoá.
- Mỗi lúc chỉ trỏ được một role vào SA `provider-aws-s3`. Trong window P4, annotation phải là role `zero-drift-rag-crossplane-s3`, còn cờ `enable_p3_provider_role` để `false`.

## Undo

Code: `git checkout main`. Trong window: `terraform destroy` xoá RDS, security
group, 5 role và 6 policy. Không có final snapshot và không có backup, nên không
để lại gì tốn tiền. Kiểm lại bằng `inventory.sh`.

## Tự thử (không bắt buộc)

- Thêm `tenant-ab` vào `tenants`: validation phải từ chối, vì `tenant-a` là tiền tố của `tenant-ab` và resource `zero-drift-rag-tenant-a-*` sẽ khớp cả bucket của tenant kia.
- Đổi `instance_class` sang `db.t4g.small`: validation từ chối (D2 cần phê duyệt mới).
- Chạy `bash scripts/plan_assert.sh --approved | jq .`: in ra đúng các statement đã duyệt (account giả).

## Giới hạn

- Ma trận offline chỉ so khớp glob của IAM (`*` và `?` khớp mọi ký tự, kể cả `/`; action không phân biệt hoa thường) và bỏ qua condition. Đánh giá thật là `aws iam simulate-*` ở mục D, và test âm L3.
- Chưa chạy `plan` thật, `apply` hay mô phỏng trên AWS (ngoài quyền của DRF-46).
