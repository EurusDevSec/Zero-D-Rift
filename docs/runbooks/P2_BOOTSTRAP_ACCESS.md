# P2 bootstrap access — MFA, phiên tạm và đường dự phòng (DRF-5)

Trạng thái: `APPROVED` 31/10 (AC-02, D1–D3 theo đề xuất). Owner tự chạy từng bước;
mọi thay đổi IAM/MFA do **owner** tự làm trên tài khoản của mình.
Nguồn: ADR-0007 (nhánh dự phòng: IAM user có MFA → AssumeRole vào role bootstrap riêng).
Chi phí: 0 USD (IAM, STS và MFA ảo đều miễn phí).

## Đích đến

```
default (key dài hạn của IAM user, chỉ dùng làm nguồn)
   └─ AssumeRole + mã MFA ─▶ role zero-drift-bootstrap ─▶ phiên tạm 1 giờ
                                                         └─ aws CLI / Terraform
Dự phòng 1: đăng nhập console bằng IAM user + MFA (độc lập với cache CLI)
Dự phòng 2: root + MFA (đã bật), chỉ khi khẩn cấp, không dùng cho Terraform
```

## Đọc nhanh

- Kiểm tra hệ thống còn nguyên không: xem **Kiểm nhanh** ở cuối.
- Làm lại từ đầu: **Chuẩn bị**, rồi bước 1 đến bước 7.
- Xóa sạch để tập lại: **Hoàn tác toàn bộ** ở cuối.

Đã chạy thật ngày 31/10: bước 1–6 bằng CLI; bước 2 trên console (bản tập với role
`zdr-practice`, tạo xong rồi xóa). Phần AC-04 chưa chạy vì cluster chưa có.

## Chuẩn bị — mỗi lần mở terminal mới

Biến shell mất khi đóng terminal; các lệnh bên dưới cần 2 biến này. Không `echo` chúng
ra màn hình và không dán vào chat, vì `ACCOUNT` là account ID thật.

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
```

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
```

```bash
USER_NAME=$(aws sts get-caller-identity --query Arn --output text | cut -d/ -f2)
```

Ghi nhớ khi dùng Windows và Git Bash:
- `file://` của aws CLI không đọc được đường dẫn `/c/...`, nên phải `cd` tới thư mục chứa file rồi dùng đường dẫn tương đối.
- Dòng `Enter MFA code for arn:...` in account ID ra stderr, nên `sed` không che được; đừng chụp hay dán dòng này.

## Hiện trạng trước khi làm (AC-01, 31/10)

IAM user, 0 MFA, chỉ có profile `default`, `AdministratorAccess` gắn trực tiếp,
root MFA = 1. Chi tiết trong `docs/evidence/p2/DRF5_BOOTSTRAP_ACCESS_20261031.md`.

## Quyết định cần owner chốt khi duyệt

| # | Câu hỏi | Đề xuất | Đánh đổi |
|---|---|---|---|
| D1 | Role bootstrap có quyền gì? | `AdministratorAccess` **trong giai đoạn này** | Bằng đúng quyền user đang có nên không tăng quyền; mục tiêu của DRF-5 là bắt buộc MFA và dùng phiên tạm. Thu hẹp quyền (least privilege) là việc phải làm trước L3, ghi thành rủi ro mở |
| D2 | Có gỡ `AdministratorAccess` khỏi user ngay không? | **Chưa**. Chỉ gỡ sau khi role chạy ổn và đã thử đường dự phòng | Gỡ sớm dễ tự khóa mình; root MFA vẫn là đường cứu |
| D3 | Thời hạn phiên | 1 giờ (`3600`) | Đúng ADR-0007; Terraform tạo/xóa EKS lâu hơn 1 giờ thì phải gia hạn giữa chừng (bước 5) |

## Bước 1 — Bật MFA cho IAM user (console)

1. Đăng nhập console (lần đầu thì dùng root nếu IAM user chưa có mật khẩu; xem bước 6)
   → **IAM** → **Users** → chọn user của bạn.
2. Tab **Security credentials** → **Assign MFA device** → đặt tên `zdr-phone` →
   **Authenticator app** → quét QR bằng app (Google Authenticator, Authy…) → nhập 2 mã liên tiếp.
3. Kiểm tra (phải ra `1`):

```bash
aws iam list-mfa-devices --query 'length(MFADevices)'
```

Lấy mã định danh thiết bị (đã che account), dùng ở bước 3:

```bash
aws iam list-mfa-devices --query 'MFADevices[0].SerialNumber' --output text | sed -E 's/[0-9]{12}/<ACCOUNT>/'
```

Hoàn tác: console → Security credentials → chọn thiết bị → **Remove**.

## Bước 2 — Tạo role bootstrap

Trust policy chỉ cho **đúng user này** assume (`Principal`), và chỉ khi có MFA nhập trong
vòng 1 giờ (`Condition`). Chọn **một** trong hai cách.

### Cách A — CLI

Cần 2 biến ở phần Chuẩn bị. File trust thật có account ID nên tạo **ngoài repo**:

```bash
sed "s/<ACCOUNT>/$ACCOUNT/; s/<USER>/$USER_NAME/" infra/iam/zero-drift-bootstrap-trust.json.example > ~/zdr-trust.json
```

Tạo role (phiên tối đa 1 giờ, tag theo COST_PLAN §10). Phải `cd ~` vì lưu ý `file://` ở trên:

```bash
cd ~
```

```bash
aws iam create-role --role-name zero-drift-bootstrap --assume-role-policy-document file://zdr-trust.json --max-session-duration 3600 --tags Key=Project,Value=Zero-D-Rift Key=Owner,Value=HoangLV Key=Environment,Value=PoC Key=ManagedBy,Value=manual
```

Gắn quyền theo D1, xóa file trust có account ID, rồi quay lại repo:

```bash
aws iam attach-role-policy --role-name zero-drift-bootstrap --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

```bash
rm ~/zdr-trust.json
```

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
```

### Cách B — console

1. **IAM** → **Users** → user của bạn → copy **ARN** ở Summary.
2. **IAM** → **Roles** → **Create role** → **Custom trust policy** → dán nội dung
   `infra/iam/zero-drift-bootstrap-trust.json.example`, thay cả cụm
   `arn:aws:iam::<ACCOUNT>:user/<USER>` bằng ARN vừa copy.
3. **Next** → tìm và tick `AdministratorAccess` → **Next**. Ô tìm kiếm trả về nhiều policy
   có tên gần giống (trong buổi tập 31/10 đã tick nhầm `AIOpsReadOnlyAccess` thay vì
   `ReadOnlyAccess`), nên tick đúng tên chính xác rồi kiểm lại ở trang Review.
4. Role name `zero-drift-bootstrap`; Tags `Project=Zero-D-Rift`, `Owner=HoangLV`,
   `Environment=PoC`, `ManagedBy=manual` → **Create role**.
5. Mở role → kiểm **Maximum session duration** = 1 hour.

### Kiểm (cả hai cách)

Phải ra `3600` và `AdministratorAccess`:

```bash
aws iam get-role --role-name zero-drift-bootstrap --query Role.MaxSessionDuration
```

```bash
aws iam list-attached-role-policies --role-name zero-drift-bootstrap --query 'AttachedPolicies[].PolicyName'
```

Hoàn tác (bằng console thì chỉ cần: Roles → tick role → **Delete**):

```bash
aws iam detach-role-policy --role-name zero-drift-bootstrap --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

```bash
aws iam delete-role --role-name zero-drift-bootstrap
```

## Bước 3 — Thêm profile CLI

Mở `~/.aws/config` bằng editor và thêm 2 profile. Thay `<ACCOUNT>` bằng số thật
**chỉ trong file này** (file nằm ngoài repo); `<MFA_SERIAL>` là kết quả bước 1.

```ini
[profile zdr-bootstrap]
role_arn = arn:aws:iam::<ACCOUNT>:role/zero-drift-bootstrap
source_profile = default
mfa_serial = <MFA_SERIAL>
duration_seconds = 3600
role_session_name = hoang-bootstrap
region = us-east-1

[profile zdr-tf]
credential_process = aws configure export-credentials --profile zdr-bootstrap --format process
region = us-east-1
```

- `zdr-bootstrap`: bạn dùng tay, CLI hỏi mã MFA rồi lưu phiên vào cache.
- `zdr-tf`: Terraform dùng. Terraform không hỏi được mã MFA, nên nó lấy phiên từ cache
  mà `zdr-bootstrap` đã tạo. Không chép key nào ra file hay biến môi trường.

## Bước 4 — Kiểm tra (AC-03)

Lấy phiên (CLI hỏi mã MFA). Kết quả phải là `assumed-role/zero-drift-bootstrap/hoang-bootstrap`:

```bash
aws sts get-caller-identity --profile zdr-bootstrap --query Arn --output text | sed -E 's/[0-9]{12}/<ACCOUNT>/'
```

Phiên hết hạn lúc nào (chỉ in thời điểm, không in key):

```bash
jq -r '.Credentials.Expiration' ~/.aws/cli/cache/*.json
```

Thử ngược: assume **không có** MFA phải bị từ chối (`AccessDenied`):

```bash
aws sts assume-role --role-arn arn:aws:iam::$ACCOUNT:role/zero-drift-bootstrap --role-session-name no-mfa-test --query Credentials.Expiration
```

Profile cho Terraform dùng được phiên tạm. Kết quả phải giống lệnh đầu:

```bash
aws sts get-caller-identity --profile zdr-tf --query Arn --output text | sed -E 's/[0-9]{12}/<ACCOUNT>/'
```

## Bước 5 — Hết hạn và gia hạn (AC-03)

Giả lập hết hạn bằng cách xóa cache, rồi gọi `zdr-tf` (phải **lỗi**, vì không ai nhập MFA):

```bash
rm -f ~/.aws/cli/cache/*.json
```

```bash
aws sts get-caller-identity --profile zdr-tf
```

Đã quan sát ngày 31/10: khi chưa có phiên trong cache, lệnh **đứng chờ** mã MFA mà
không hiện lời hỏi (bị `timeout 20` cắt, exit 124). Nhấn Ctrl+C nếu gặp. Vì vậy luôn
lấy hoặc gia hạn phiên bằng `zdr-bootstrap` **trước** khi chạy Terraform; nếu không,
Terraform sẽ treo chứ không báo lỗi.

Gia hạn: chạy lại lệnh `get-caller-identity --profile zdr-bootstrap` của bước 4, nhập mã
MFA mới, rồi `zdr-tf` chạy lại được. Đây là cách gia hạn khi Terraform chạy lâu hơn 1 giờ.

## Bước 6 — Đường dự phòng độc lập (AC-03)

1. Mở cửa sổ ẩn danh → đăng nhập console bằng IAM user + mã MFA → vào **EC2** (us-east-1)
   xem được danh sách. Việc này chứng minh vẫn vào được để dọn dẹp khi cache CLI hỏng hoặc hết hạn.
   Nếu user chưa có mật khẩu console: IAM → Users → user → **Enable console access**.
2. Root + MFA đã bật: chỉ ghi nhận là đường khẩn cấp cuối cùng, **không** đăng nhập thử
   nếu không cần.

## Bước 7 — Terraform dùng phiên tạm

Từ DRF-6 trở đi, trước mỗi lần chạy Terraform:

```bash
export AWS_PROFILE=zdr-tf
```

Không đặt `profile` hay key trong code (DRF-7 `providers.tf` đã không có).

## Ghi evidence

Sau mỗi bước, dán output (đã che account) cho reviewer. Không dán key, secret,
session token hay nội dung `~/.aws/cli/cache`.

## Kiểm nhanh — hệ thống còn nguyên không

Chạy bất cứ lúc nào, ví dụ trước một đợt apply. Mỗi lệnh có kết quả mong đợi đi kèm.
Lệnh dưới phải ra `1` (MFA vẫn gắn với user):

```bash
aws iam list-mfa-devices --query 'length(MFADevices)'
```

Phải ra `zero-drift-bootstrap 3600` (role còn, phiên 1 giờ):

```bash
aws iam get-role --role-name zero-drift-bootstrap --query 'Role.[RoleName,MaxSessionDuration]' --output text
```

Phải có `default`, `zdr-bootstrap` và `zdr-tf`:

```bash
aws configure list-profiles
```

Phải ra `assumed-role/zero-drift-bootstrap/hoang-bootstrap` (có thể hỏi mã MFA):

```bash
aws sts get-caller-identity --profile zdr-bootstrap --query Arn --output text | sed -E 's/[0-9]{12}/<ACCOUNT>/'
```

Phải in một giờ hết hạn trong tương lai:

```bash
jq -r '.Credentials.Expiration' ~/.aws/cli/cache/*.json
```

Nếu một dòng sai, làm lại đúng bước tương ứng (1, 2 hoặc 3) phía trên.

## Hoàn tác toàn bộ — đưa account về như trước DRF-5

Chỉ dùng khi muốn tập lại từ đầu hoặc bỏ cách này. Làm **ngược thứ tự** đã tạo, và giữ
một cửa đăng nhập còn chạy được ở mỗi bước. Cần 2 biến ở phần Chuẩn bị.

1. Xóa phiên đang lưu:

```bash
rm -f ~/.aws/cli/cache/*.json
```

2. Mở `~/.aws/config` (`code ~/.aws/config`), xóa 2 khối `[profile zdr-bootstrap]` và
   `[profile zdr-tf]`, rồi lưu. Bản sao lưu trước DRF-5 là `~/.aws/config.bak-20261031`.
3. Gỡ quyền rồi xóa role:

```bash
aws iam detach-role-policy --role-name zero-drift-bootstrap --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

```bash
aws iam delete-role --role-name zero-drift-bootstrap
```

4. Mật khẩu console và MFA của user: **nên giữ**, vì đó là cửa cứu hộ và lớp bảo vệ key.
   Nếu thật sự muốn gỡ, làm trên console: user → Security credentials → **Manage console
   access** → Disable; MFA device → **Remove**. Không gỡ root MFA.
5. Kiểm. Role phải không còn (`NoSuchEntity`):

```bash
aws iam get-role --role-name zero-drift-bootstrap
```

   Chỉ còn `default`:

```bash
aws configure list-profiles
```

## Kế hoạch quyền vào EKS và gỡ quyền admin (AC-04)

Kế hoạch này chưa chạy. Cluster chưa tồn tại: DRF-9 viết code, DRF-11 chạy trong
approved window. Nguồn: ADR-0007, mục "Access matrix".

### Ai vào cluster bằng gì

| Vai trò (ADR-0007) | Danh tính trong account này | Quyền Kubernetes | Khi nào có |
|---|---|---|---|
| Bootstrap operator | Role `zero-drift-bootstrap` (đã tạo 31/10), vào qua `zdr-bootstrap` / `zdr-tf` | Access entry STANDARD + `AmazonEKSClusterAdminPolicy`, scope **chỉ cluster PoC** | **Chỉ trong approved window**, gỡ khi kết thúc |
| Daily observer | Chưa tạo. Đề xuất role `zero-drift-observer` (Describe/List), làm trước L3 nếu cần xem inventory | `AmazonEKSViewPolicy`, cộng RBAC get/list/watch Nodes nếu smoke test cần | Phiên tạm, không bao giờ là cluster-admin |
| Break-glass / recovery | IAM user `<USER>`: console + MFA (đã thử 31/10). Root + MFA chỉ là lớp cuối | Không có entry thường trực. Sửa quyền bằng **EKS API** (AWS IAM), không cần kubectl | Chỉ khi có sự cố, kèm incident record |
| Node và service role | Do module EKS tạo | EKS tự quản lý | Không dùng cho người |

Vì sao break-glass không cần entry riêng: access entry được quản lý qua AWS API
(`eks:CreateAccessEntry`, `eks:AssociateAccessPolicy`, `eks:DisassociateAccessPolicy`).
Khi Kubernetes RBAC khóa operator, user `<USER>` (quyền IAM admin, D2) vẫn sửa được
entry từ console hoặc CLI. Cách này không cứu được trường hợp mất đăng nhập AWS,
IAM bị deny hoặc mất kết nối endpoint; lúc đó dùng root.

### Cấu hình cluster bắt buộc (DRF-9)

- `authentication_mode = "API"`: không dùng `aws-auth` ConfigMap.
- `enable_cluster_creator_admin_permissions = false`: không để người tạo cluster tự có
  admin vĩnh viễn ngoài code.
- Access entry dùng **role ARN ổn định** `arn:aws:iam::<ACCOUNT>:role/zero-drift-bootstrap`,
  không dùng ARN của phiên STS (`assumed-role/...`). Account lấy từ data source, không viết cứng.
- Việc gắn admin do một biến điều khiển (ví dụ `bootstrap_admin_enabled`). Hết window thì
  đặt về `false`, để lần `apply` sau không vô tình cấp lại.
- Xóa rồi tạo lại role thì phải tạo lại access entry, kể cả khi ARN giống cũ.

### Mỗi window: cấp, dùng, gỡ, kiểm

1. **Trước khi cấp**, ghi một elevation record (không có account ID):

```text
run_id: P2-RUN-YYYYMMDD-NN
role_alias: zero-drift-bootstrap
policy: AmazonEKSClusterAdminPolicy, scope cluster zero-drift
granted_at_utc: ...
cleanup_deadline_utc: <cuối approved window>
cleanup_owner: HoangLV
recovery_path: <USER> console + MFA (verified 2026-10-31); root + MFA last resort
```

2. **Cấp:** `bootstrap_admin_enabled = true`, plan rồi apply bằng `AWS_PROFILE=zdr-tf`.
3. **Gỡ khi xong** (hoặc khi tới deadline): đặt về `false`, rồi apply. Nếu Terraform không
   chạy được, gỡ tay bằng EKS API:

```bash
aws eks disassociate-access-policy --cluster-name zero-drift --principal-arn arn:aws:iam::$ACCOUNT:role/zero-drift-bootstrap --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
```

4. **Kiểm.** Access entry có độ trễ, nên thử lại mỗi 30 giây, tối đa 5 phút. Kết quả phải là danh sách rỗng:

```bash
aws eks list-associated-access-policies --cluster-name zero-drift --principal-arn arn:aws:iam::$ACCOUNT:role/zero-drift-bootstrap --query 'associatedAccessPolicies[].policyArn'
```

Thử ngược bằng **một thao tác admin thật**, chạy bằng chính role đó. Theo ADR, không
dùng `--as` và không chỉ dùng `can-i --list`. Kết quả phải là `Forbidden`:

```bash
kubectl create namespace zdr-negative-check
```

5. Ghi vào evidence: giờ gỡ, kết quả list rỗng và dòng `Forbidden`.

Trường hợp đơn giản nhất của PoC: nếu window kết thúc bằng `destroy` cả cluster, access
entry mất cùng cluster. Khi đó chỉ cần kiểm `aws eks list-clusters` không còn
`zero-drift` và ghi vào inventory.

### Giới hạn được thừa nhận

- Role bootstrap **có thể tự cấp lại** admin, vì nó có quyền `eks:AssociateAccessPolicy`.
  Không tuyên bố role này không tự leo thang được. Biện pháp giảm thiểu: chỉ assume trong
  window, có scope đúng cluster, và kiểm sự kiện `AssociateAccessPolicy` trong CloudTrail
  sau mỗi window.
- Người backup thứ hai: **SHOULD**, không phải MUST với PoC một người. Hiện chưa có;
  owner là cả cleanup owner lẫn recovery custodian.
- `AdministratorAccess` trên role và user (D1, D2) là tạm thời. Policy tối thiểu phải được
  map từ plan thật trước L3.

## Rủi ro còn mở sau DRF-5

- Role và user vẫn có `AdministratorAccess` (D1, D2): thu hẹp quyền trước L3.
- Key dài hạn của `default` vẫn tồn tại làm nguồn: xoay key định kỳ, không tạo thêm key.
- Không có người backup thứ hai (SHOULD, không MUST cho PoC một người).
- Role `zero-drift-observer` chưa tạo (tùy chọn, trước L3).
- Kế hoạch quyền EKS ở trên mới là tài liệu; chỉ được kiểm chứng ở DRF-9 (code) và DRF-11 (window).
