# P2 R1 — thu hẹp quyền role bootstrap (chuẩn bị DRF-11)

Trạng thái: **đã soạn và mới kiểm bằng mô phỏng; chưa gắn vào role thật.**
Các bước 3–5 thay đổi IAM, nên owner phải duyệt riêng trong chat trước khi chạy.

Nguồn: DRF-5 D1 (admin chỉ là tạm, phải thu hẹp trước L3), ADR-0007.
Policy: `infra/iam/zero-drift-terraform-policy.json`.
Script kiểm (chỉ đọc): `infra/terraform/scripts/iam_check.sh`.

## Vì sao

Role `zero-drift-bootstrap` đang có `AdministratorAccess`. Khi phiên MFA bị lộ hoặc gõ nhầm lệnh, nó có thể:
- tạo IAM user hay access key mới;
- tự cấp thêm quyền cho chính nó;
- mở NAT, EIP hay máy GPU;
- xóa bucket state.

R1 thay quyền admin bằng một policy chỉ đủ cho Terraform P2 và các lệnh kiểm tra trong runbook.

## Policy cho phép và chặn gì

| Nhóm | Cho phép | Giới hạn |
|---|---|---|
| Đọc để kiểm | `Describe*`/`List*`/`Get*` của EC2, EKS, IAM, RDS, ELB, ASG; đọc Budget, giá, quota, tag; mô phỏng IAM | Chỉ đọc |
| Mạng + EKS | `ec2:*`, `eks:*` | Chỉ ở `us-east-1` |
| Log | Tạo, xóa, đặt retention, gắn tag | Chỉ log group `/aws/eks/zero-drift/*` |
| RDS | Tạo, sửa, xóa **DB subnet group** | Không tạo được DB instance |
| IAM role | Tạo, xóa, sửa, gắn tag | Chỉ role `zero-drift-cluster-*` và `zero-drift-system-node-*` |
| Gắn policy | Attach, detach | Chỉ 4 policy EKS: ClusterPolicy, WorkerNodePolicy, CNI, ECR ReadOnly |
| PassRole | Đưa role cho dịch vụ dùng | Chỉ cho `eks.amazonaws.com` và `ec2.amazonaws.com` |
| OIDC, service-linked role | Tạo và xóa OIDC của EKS; SLR cho eks, eks-nodegroup, autoscaling | Đúng các đối tượng đó |
| Bucket state | Đọc, ghi, xóa object (state và lock); đọc cấu hình bucket | Chỉ bucket `zero-d-rift-tfstate-*` |
| **Chặn cứng (Deny)** | NAT, EIP, dedicated host, reserved instance, capacity reservation | Kể cả khi sau này có ai gắn thêm policy rộng hơn |
| **Chặn cứng** | Chạy máy EC2 khác `m6i.large` và `t3.medium` | Trùng với danh sách giá đã duyệt |
| **Chặn cứng** | Mọi thao tác ghi lên role bootstrap, lên chính policy này và lên mọi IAM user | Role không tự nâng quyền được |
| **Chặn cứng** | Xóa bucket state hoặc sửa policy, versioning, mã hóa, lifecycle của nó | Bảo vệ state |

**Đây là bậc 1, chưa phải tối thiểu tuyệt đối.** `ec2:*` và `eks:*` vẫn rộng trong `us-east-1`.
Lý do: chưa apply lần nào nên chưa biết chính xác Terraform gọi những API nào. Thu hẹp thêm thì
dễ bị dừng giữa chừng vì thiếu quyền. Bậc 2 làm sau L3: xem CloudTrail Event history (miễn phí,
giữ 90 ngày) để biết các API thật đã gọi, rồi rút gọn lại.

Đường cứu khi policy sai: **IAM user break-glass + MFA** (DRF-5). User đó vẫn có admin qua console.
Root chỉ là đường cuối cùng.

## Chuẩn bị

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
```

```bash
zdr-bootstrap
```

```bash
export AWS_PROFILE=zdr-tf AWS_REGION=us-east-1
```

## Bước 1 — Kiểm tĩnh

```bash
./scripts/check.sh
```

Phải có dòng `PASS  R1 policy JSON valid, .../6144 chars`.

## Bước 2 — Mô phỏng policy (chỉ đọc, miễn phí)

```bash
./scripts/iam_check.sh
```

Phải ra 31 dòng `PASS`:
- 1 dòng Access Analyzer: không có ERROR hay SECURITY_WARNING;
- 30 dòng mô phỏng: việc Terraform cần làm phải ra `allowed`, việc bị cấm phải ra `implicitDeny` hoặc `explicitDeny`.

`implicitDeny` là không có quyền vì không có dòng nào cho phép.
`explicitDeny` là bị một dòng Deny chặn cứng, và không policy nào khác mở lại được.

## Bước 3 — Tạo policy (CẦN DUYỆT)

```bash
cd ../iam
```

```bash
aws iam create-policy --policy-name zero-drift-terraform --policy-document file://zero-drift-terraform-policy.json --description "Zero D-Rift P2 Terraform scope (R1 tier 1)" --tags Key=Project,Value=Zero-D-Rift Key=Owner,Value=HoangLV Key=Environment,Value=PoC Key=ManagedBy,Value=manual
```

```bash
cd ../terraform
```

## Bước 4 — Gắn policy mới vào role (CẦN DUYỆT)

```bash
ACCT=$(aws sts get-caller-identity --query Account --output text)
```

```bash
aws iam attach-role-policy --role-name zero-drift-bootstrap --policy-arn "arn:aws:iam::$ACCT:policy/zero-drift-terraform"
```

## Bước 5 — Gỡ AdministratorAccess (CẦN DUYỆT, khó quay lại)

```bash
aws iam detach-role-policy --role-name zero-drift-bootstrap --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Từ giây này, role không còn tự gắn lại admin được. Đó là thiết kế (`DenySelfEscalation`).
Muốn quay lại thì làm theo phần Hoàn tác.

## Bước 6 — Kiểm sau khi gắn

1. Role chỉ còn một policy:

   ```bash
   aws iam list-attached-role-policies --role-name zero-drift-bootstrap --query 'AttachedPolicies[].PolicyName' --output text
   ```

   Phải ra đúng `zero-drift-terraform`.

2. Mô phỏng trên role thật:

   ```bash
   ./scripts/iam_check.sh --principal
   ```

   Phải ra 30 dòng `PASS`.

3. Thử thật bằng `--dry-run`. AWS chỉ kiểm quyền, không tạo gì:

   ```bash
   aws ec2 create-vpc --cidr-block 10.99.0.0/16 --dry-run
   ```

   Phải báo `DryRunOperation`, nghĩa là được phép.

   ```bash
   aws ec2 allocate-address --dry-run
   ```

   Phải báo `UnauthorizedOperation`, nghĩa là bị chặn.

4. Lệnh đọc vẫn chạy. Phải ra `RESULT: CLEAN`:

   ```bash
   ./scripts/inventory.sh
   ```

5. Plan vẫn chạy:

   ```bash
   terraform plan -var-file=run.tfvars -out=tfplan
   ```

   Phải ra 50 resource.

   ```bash
   ./scripts/plan_assert.sh tfplan
   ```

   Phải ra 26 `PASS`.

   ```bash
   ./scripts/plan_fingerprint.sh tfplan
   ```

   `shape sha256` phải ra `41f63a72…`. Đổi tên role không đổi địa chỉ resource, nên shape giữ nguyên.

   ```bash
   rm tfplan
   ```

## Khi thiếu quyền lúc apply (S2 của P2_L3_WINDOW)

1. Ghi đúng dòng lỗi, ví dụ `not authorized to perform: iam:XYZ on resource ...`.
2. Destroy những gì đã tạo. Policy có đủ quyền xóa đối tượng nó đã tạo.
3. Sau window, đăng nhập IAM user break-glass rồi sửa file policy. Tạo version mới:

   ```bash
   aws iam create-policy-version --policy-arn "arn:aws:iam::$ACCT:policy/zero-drift-terraform" --policy-document file://zero-drift-terraform-policy.json --set-as-default
   ```

   AWS giữ tối đa 5 version. Version cũ xóa bằng `delete-policy-version`.
4. Thêm một dòng vào ma trận của `iam_check.sh` cho action vừa thiếu. Ghi evidence.

## Hoàn tác

Phải làm bằng **IAM user break-glass**, vì role đã bị cấm tự sửa mình.

1. Console, đăng nhập IAM user + MFA → IAM → Roles → `zero-drift-bootstrap` → Add permissions →
   `AdministratorAccess`.
2. Nếu muốn bỏ hẳn R1: detach `zero-drift-terraform` khỏi role, rồi Delete policy.

## Owner tự giải thích (Claude không viết hộ)

1. `implicitDeny` khác `explicitDeny` thế nào? Vì sao các lệnh cấm NAT, EIP và tự nâng quyền phải là `explicitDeny`?
2. Vì sao phải gắn policy mới **trước**, rồi mới gỡ admin?
3. Nếu policy thiếu quyền ngay giữa lúc apply, bạn sửa bằng danh tính nào, và vì sao không dùng role bootstrap?
4. Policy này vẫn còn chỗ nào rộng, và kế hoạch thu hẹp tiếp là gì?
