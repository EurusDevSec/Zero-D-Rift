# P3 — Resource graph trên EKS: IRSA, GitOps, window, dọn

Runbook của P3 (SPEC-P3). Mỗi task thêm phần của mình:

| Phần | Task | Trạng thái |
|---|---|---|
| A. IRSA role cho provider (Terraform) | DRF-36 (T4) | Viết 05/11, phần không cần AWS đã chạy |
| B. GitOps: Argo CD sync `gitops/platform` và `gitops/requests` | DRF-35 (T3) | Xem PR của DRF-35 |
| C. Window L3: tạo, kiểm, test âm, test xóa, dọn | DRF-37 (T5) | Chưa viết; cần owner duyệt window riêng |

Runbook nền:
- [P2_L3_WINDOW](P2_L3_WINDOW.md): MFA, IP, plan, apply, admin, destroy, inventory;
- [P3_L2_KIND_LAB](P3_L2_KIND_LAB.md): làm quen với Argo CD, Crossplane và kro trên kind, không AWS.

---

## A. IRSA role cho Crossplane provider (DRF-36)

### Ý tưởng trong 4 dòng

```
Pod provider-aws-s3 ── token OIDC do EKS ký (sub = system:serviceaccount:crossplane-system:provider-aws-s3)
        │
        ▼  sts:AssumeRoleWithWebIdentity (role chỉ tin đúng sub + aud này)
IAM role zero-drift-p3-crossplane-s3 ── chỉ s3:CreateBucket/DeleteBucket/PutBucketTagging/Get*/List*
                                       trên arn:aws:s3:::zero-drift-p3-*  (không object, không IAM)
```

Terraform sở hữu role này (ADR-0003). Bucket thuộc Crossplane. Role chỉ được tạo khi bật `enable_p3_provider_role = true`. Giá trị mặc định là `false`, nên plan của P2 không đổi.

Code:
- `infra/terraform/modules/p3-provider-irsa/`;
- lời gọi module ở cuối `infra/terraform/main.tf`;
- test: `infra/terraform/tests/p3_irsa.tftest.hcl`;
- kiểm plan: `scripts/plan_assert.sh` (check 13);
- mô phỏng IAM: `scripts/p3_iam_check.sh`.

### A0. Kiểm tĩnh, không cần AWS (làm bất cứ lúc nào)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
terraform init -backend=false -lockfile=readonly    # lần đầu, hoặc khi thêm module
./scripts/check.sh
```

**Phải thấy:** `RESULT: PASS`. Dòng `terraform test` pass, gồm 4 test P3:
- mặc định không có role;
- khi bật, trust đúng 1 subject;
- role sai tiền tố bị từ chối;
- prefix bucket `*` bị từ chối.

Muốn xem từng test:

```bash
terraform test
```

**Phải thấy:** `20 passed, 0 failed`.

**Tự thử:**
1. Mở `modules/p3-provider-irsa/main.tf`, đổi dòng `Resource = ["arn:aws:s3:::${var.bucket_prefix}*"]` thành `Resource = ["*"]`, rồi chạy `terraform test`.
2. **Phải thấy:** `Permissions must apply only to arn:aws:s3:::zero-drift-p3-*` và `1 failed`.
3. Trả lại như cũ: `git checkout modules/p3-provider-irsa/main.tf`.

### A1. Plan cho window P3 (cần phiên MFA; chỉ đọc AWS)

Làm theo P2_L3_WINDOW các bước: MFA, IP, `run.tfvars`, `init` với backend. Sau đó **thêm** cờ P3:

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
export AWS_PROFILE=zdr-tf AWS_REGION=us-east-1
terraform plan -var-file=run.tfvars -var bootstrap_cluster_admin=true -var enable_p3_provider_role=true -out=tfplan
ADMIN_WINDOW=1 P3_WINDOW=1 ./scripts/plan_assert.sh tfplan
./scripts/plan_fingerprint.sh tfplan
./scripts/p3_iam_check.sh tfplan
```

**Phải thấy:**
- `plan_assert`: `RESULT: PASS`, có 3 dòng `P3 role …` PASS. Số resource là 53: 50 của P2, cộng 1 admin association, 1 role P3 và 1 inline policy.
- `plan_fingerprint`: ghi lại shape hash cho window request.
- `p3_iam_check`: Access Analyzer không có ERROR hay SECURITY_WARNING. Các hành động trên bucket `zero-drift-p3-*` ra `allowed`; mọi thứ khác ra `implicitDeny` (bucket ngoài prefix, object, PutBucketPolicy, ListAllMyBuckets, IAM, AssumeRole).

**Nếu sai:**
- Quên `P3_WINDOW=1`: check 13 báo `inline role polic(ies) planned without P3_WINDOW=1`. Đó là cố ý, để không ai vô tình tạo role P3.
- Quên `-var enable_p3_provider_role=true`: `p3_iam_check` báo `no aws_iam_role_policy in the plan`.

### A2. Sau khi apply trong window

```bash
./scripts/p3_iam_check.sh --principal
aws iam get-role --role-name zero-drift-p3-crossplane-s3 --query 'Role.RoleName' --output text
# ARN chỉ để đưa vào cluster, KHÔNG echo, KHÔNG ghi vào evidence/Git (chứa account ID):
ROLE_ARN="$(aws iam get-role --role-name zero-drift-p3-crossplane-s3 --query 'Role.Arn' --output text)"
```

`ROLE_ARN` được dùng ở phần B: gắn vào ServiceAccount `provider-aws-s3` qua DeploymentRuntimeConfig.

**Phải thấy:** `p3_iam_check --principal` trả `RESULT: PASS`, và `get-role` in đúng tên role.

### A3. Gỡ admin nhưng GIỮ role P3

Trong P2, bước gỡ admin là plan lại **không** truyền `-var bootstrap_cluster_admin=true`. Sang P3 thì **phải vẫn giữ** `-var enable_p3_provider_role=true` cho tới khi bucket P3 đã hết:

```bash
terraform plan -var-file=run.tfvars -var enable_p3_provider_role=true -out=tfplan
terraform show -no-color tfplan | grep -E '^Plan:|will be destroyed'
```

**Phải thấy:** `Plan: 0 to add, 0 to change, 1 to destroy`, và resource bị destroy là association admin.

Nếu quên cờ này, plan sẽ xóa luôn role. Khi đó provider mất quyền, không xóa được bucket thật, và MR bị kẹt ở bước xóa.

### A4. Undo

- **Chỉ gỡ role** (cluster vẫn còn, và bucket P3 đã hết): plan và apply **không** có `-var enable_p3_provider_role=true`. Plan phải chỉ có 2 delete: `aws_iam_role_policy` và `aws_iam_role` của module `p3_provider_irsa`.
- **Gỡ hết:** dùng `terraform destroy` như P2. Role đi cùng destroy.
- **Kiểm sau cùng:**

  ```bash
  aws iam get-role --role-name zero-drift-p3-crossplane-s3 2>&1 | grep -c NoSuchEntity
  ```

  Kết quả phải là `1`.

### Giới hạn của phần A

- Role P3 nằm ngoài phạm vi policy R1 (`infra/iam/zero-drift-terraform-policy.json` chỉ cho phép role `zero-drift-cluster-*` và `zero-drift-system-node-*`, và không có `iam:PutRolePolicy`). Hiện tại Terraform dùng AdministratorAccess (R1 hoãn tới DRF-27/29), nên window không bị chặn. Khi làm lại R1 thì phải thêm role `zero-drift-p3-*` và `PutRolePolicy`/`GetRolePolicy`.
- `s3:Get*` và `s3:List*` là wildcard ở **action**, không phải ở resource: provider đọc rất nhiều thuộc tính con của bucket mỗi lần refresh. Resource chỉ gồm ARN bucket có prefix, nên các action trên object không bao giờ khớp.
