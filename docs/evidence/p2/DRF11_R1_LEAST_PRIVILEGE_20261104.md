# DRF-11 chuẩn bị — R1: thu hẹp quyền role bootstrap (04/11/2026)

| Trường | Giá trị |
|---|---|
| Issue | DRF-11, phần chuẩn bị R1 (DRF-5 D1: admin chỉ là tạm, phải thu hẹp trước L3) |
| Người làm | Claude (implementer, speed mode); owner giữ quyền duyệt thay đổi IAM |
| Revision | nhánh `hoang/drf-11-r1-least-privilege`, tách từ `main` @ `2a245e5` |
| Thời gian | 2026-11-04 10:17–10:26 UTC (17:17–17:26 Asia/Saigon) |
| Danh tính | `arn:aws:sts::<ACCOUNT>:assumed-role/zero-drift-bootstrap/hoang-bootstrap` (vẫn đang có AdministratorAccess) |
| Thay đổi trên AWS | **Không có.** Chỉ chạy lệnh đọc và mô phỏng: Access Analyzer `ValidatePolicy`, IAM `SimulateCustomPolicy`, `terraform plan`, đọc S3 |
| Che dữ liệu | Script thay account ID bằng `<ACCOUNT>`; không in IP và tên bucket |

## Kết quả

| Kiểm | Kết quả |
|---|---|
| `check.sh` | 9/9 PASS, có dòng mới `R1 policy JSON valid, 4624/6144 chars` |
| Access Analyzer `validate-policy` (IDENTITY_POLICY) | 0 finding: không ERROR, không SECURITY_WARNING, không WARNING, không SUGGESTION |
| `iam_check.sh`, mô phỏng file policy | **30/30 dòng ma trận PASS** (31 PASS tính cả Access Analyzer) |
| `terraform plan` mặc định | 50 to add; `plan_assert` **26/26 PASS** (gồm check 12: IAM nằm trong phạm vi R1) |
| `terraform plan` window (`bootstrap_cluster_admin=true`) | 51 to add; `ADMIN_WINDOW=1 plan_assert` **25/25 PASS** |
| Tên role trong plan | `zero-drift-cluster-`, `zero-drift-system-node-` (trước đây là `system-eks-node-group-`) |
| Lock trên bucket state sau các plan | 0 |

Ma trận mô phỏng (30 tình huống):

| Kỳ vọng | Tình huống |
|---|---|
| `allowed` | Tạo VPC và EKS cluster ở us-east-1; RunInstances m6i.large; tạo 2 loại role có prefix; gắn AmazonEKSClusterPolicy; PassRole cho eks; tạo OIDC của EKS; SLR eks-nodegroup; log group `/aws/eks/zero-drift/*`; DB subnet group `zero-drift`; ghi object vào bucket state; đọc tham số AMI EKS từ SSM; xem Budget |
| `implicitDeny` | Tạo VPC ở us-west-2; role `zero-drift-admin`; gắn AdministratorAccess cho role cluster; PassRole cho lambda; SLR rds; log group ngoài dự án; tạo DB instance; đọc bucket khác; rời Organization |
| `explicitDeny` | RunInstances g4dn.xlarge; NAT Gateway; Elastic IP; gắn admin cho role bootstrap; sửa chính policy R1; tạo IAM user; xóa bucket state |

## Hai lỗi phát hiện và đã sửa

1. **`simulate-custom-policy` không nhận `file://` cho tham số danh sách.**
   AWS CLI 2.37.4 báo `ValidationError ... length less than or equal to 2000`.
   Đã sửa: truyền JSON đã nén (`jq -c`).

2. **`plan_fingerprint.sh` v1 cho hash phụ thuộc máy chạy.**
   Cùng code ở `main`, plan hôm nay ra shape `ab7c1761…`, khác `41f63a72…` ghi ngày 31/10.
   Đã chứng minh bằng 3 phép thử:
   - So danh sách địa chỉ của plan **trước và sau khi đổi tên role**: giống hệt nhau. Vậy đổi tên role không phải nguyên nhân.
   - `jq` trên Windows xuất CRLF: cả 50 dòng đều có `\r`.
   - `sort` theo `en_US.UTF-8` và theo `C` cho thứ tự khác nhau ở `aws_iam_role_policy_attachment.this["AmazonEKS_CNI_Policy"]`.

   Đã sửa thành v2: `tr -d '\r' | LC_ALL=C sort`. Hash do script tính khớp với cách tính độc lập `d9fe3d79…`.

**Hash chuẩn mới (v2), dùng cho window request DRF-11:**

| Plan | shape sha256 |
|---|---|
| Mặc định (50) | `d9fe3d7989f0a934343eaa96197b1ad6407eaa3051402990a1e1a0fed5ac44a0` |
| Window (51) | `95f61444096ecd86dba558e179925d2341292784c25c4a26163f90f003ea72b8` |

## Chưa làm (cần owner duyệt riêng)

Các bước 3–5 trong `docs/runbooks/P2_LEAST_PRIVILEGE.md` thay đổi IAM:
- `create-policy zero-drift-terraform`;
- `attach-role-policy`;
- `detach-role-policy AdministratorAccess`.

Sau khi gắn, kiểm bằng:
- `iam_check.sh --principal`: phải ra 30 PASS;
- `--dry-run` của EC2;
- `inventory.sh`;
- plan, `plan_assert` và shape hash.

## Giới hạn

- Mô phỏng chưa phải bằng chứng thật. Danh sách quyền đủ hay thiếu chỉ được chứng minh khi apply và destroy ở L3.
  Thiếu quyền lúc đó thì xử lý theo S2: destroy, rồi sửa policy bằng break-glass.
- Policy mới là bậc 1: `ec2:*` và `eks:*` vẫn rộng trong `us-east-1`. Bậc 2 làm sau L3, dựa trên CloudTrail Event history.
- Trình mô phỏng không khớp `eks:CreateCluster` với ARN cluster cụ thể, nên ma trận kiểm hành động này trên `*`. Policy thật cũng cấp nó trên `*`.
- `run.tfvars` (file riêng của owner) có một dòng hỏng `["/32"]`, do `MYIP` rỗng. Claude đã xóa đúng dòng đó. Runbook P2_EKS bước 2 giờ kiểm `MYIP` trước khi ghi.
- Owner teach-back cho R1 (4 câu ở cuối runbook): chưa trả lời.

## Quyết định owner 04/11/2026: hoãn R1, giữ AdministratorAccess

Owner viết trong chat:

> "tôi nghĩ nên để adminitrator access thì quá trình làm task từ đây về sau tránh gặp rắc rối tốn thời gian khi làm xong các phase rồi tính sau"

Ghi nhận:
- **Không gắn policy R1.** Role `zero-drift-bootstrap` giữ `AdministratorAccess`.
  Quyết định này thay mốc "thu hẹp quyền trước L3" của DRF-5 D1. Owner chấp nhận rủi ro còn lại.
- **Rủi ro còn lại:** một phiên MFA bị lộ hoặc một lệnh gõ nhầm có thể làm mọi việc trong account, gồm tạo NAT/GPU, tạo IAM user hay key, xóa bucket state.
- **Lớp bảo vệ vẫn còn:**
  - MFA bắt buộc, phiên 1 giờ;
  - `plan_assert` chặn NAT, EIP, loại máy chưa duyệt giá, sai IAM;
  - Budget đo gross (B1-a), cảnh báo 50/75/90;
  - `inventory.sh` trước và sau mỗi window;
  - S1–S7 và freeze trong P2_L3_WINDOW.
- **Lớp bảo vệ mất đi:** các Deny cứng ở tầng IAM (NAT, EIP, loại máy, tự nâng quyền, bảo vệ bucket state). Chỉ còn kiểm ở tầng plan.
- **Làm lại R1:** trước DRF-27 (đóng băng campaign, 19/11) hoặc ở DRF-29.
  Lợi ích của việc hoãn: lúc đó đã có CloudTrail Event history của các lần chạy thật, nên rút được policy sát hơn bậc 1.
- **Phần còn dùng ngay:**
  - `plan_fingerprint.sh` v2 và hash chuẩn mới (bắt buộc cho window request DRF-11);
  - check 12 của `plan_assert`;
  - tên role `zero-drift-system-node-*`;
  - file policy và `iam_check.sh`, để sẵn cho lần làm lại.
