# P2 EKS — cluster 1.35, node AL2023, OIDC, access entry (DRF-9)

Trạng thái: code xong, **chỉ plan, chưa apply**. Cluster chỉ được tạo thật ở đợt L3 (DRF-11),
khi có duyệt riêng về giờ chạy và chi phí.
Nguồn: SPEC-P2 Task 5, ADR-0003 (bootstrap trước controller), ADR-0007 (quyền vào cluster).
Cần có trước: DRF-5 (phiên MFA), DRF-6 (backend S3), DRF-8 (network). Root plan hiện có 50 resource.

## Đích đến

```
Máy owner ──(IP/32)──▶ EKS API public ─┐
                                        ├─ EKS 1.35, standard support, auth = API
Node (subnet public) ──▶ EKS API private┘   log audit + authenticator, giữ 3 ngày
   └─ node group "system": 1× m6i.large (tối đa 2), AL2023 1.35.9-20261026, IMDSv2
Add-on pin: vpc-cni v1.22.4-eksbuild.10 · kube-proxy v1.35.3-eksbuild.62 · coredns v1.13.2-eksbuild.62
OIDC provider: cho IRSA của controller ở P3 (chưa có role nào dùng)
Access entry: role zero-drift-bootstrap (STANDARD); quyền admin CHỈ khi bootstrap_cluster_admin=true
```

## Vì sao cấu hình như vậy

| Lựa chọn | Lý do | Đánh đổi |
|---|---|---|
| Standard support | 0.10 USD/giờ; extended support là 0.60 | Phải nâng phiên bản trước 27/03/2027 |
| Endpoint public chỉ cho `<MY_IP>/32` | Lệnh `kubectl` chạy được từ máy owner, người khác không gọi được API | Đổi mạng (IP khác) thì phải sửa `run.tfvars` rồi apply lại |
| `authentication_mode = API`, tắt creator admin | Quyền vào cluster nằm ở EKS API, thấy rõ và gỡ được; không dùng ConfigMap `aws-auth` | Mất API AWS thì cũng mất đường sửa quyền; dự phòng bằng IAM user + MFA (DRF-5) |
| Admin chỉ bật trong window | EKS không tự hết hạn quyền admin; mặc định `false` nên lần apply sau sẽ tự gỡ | Mỗi đợt phải bật rồi tắt; việc này đã có trong runbook DRF-5 AC-04 |
| 1 node m6i.large, tối đa 2 | Quota On-Demand là 5 vCPU, mỗi node 2 vCPU; còn chỗ cho node CPU ở P3 | Một node thì không chịu được hỏng node |
| AMI và add-on pin cứng | Chạy lại ra đúng hệ thống cũ; không có bản "latest" trôi ngầm | Muốn nâng cấp thì sửa default trong `variables.tf` và ghi evidence |
| IMDSv2, hop limit 1 | Pod không lấy được credential của node qua metadata | Pod cần quyền AWS phải dùng IRSA (P3) |
| Không KMS key riêng | EKS tự mã hóa secret bằng key của AWS; không tốn 1 USD/tháng, không phải chờ 7 ngày khi xóa | Không tự xoay key được |
| Log chỉ audit + authenticator, giữ 3 ngày | Đủ để biết ai làm gì và ai đăng nhập; tốn ít tiền | Không có log api, controllerManager, scheduler |

## Ai có quyền gì (AC-04)

| Danh tính | Quyền AWS | Quyền trong Kubernetes | Ai tạo, ai xóa |
|---|---|---|---|
| Role `zero-drift-bootstrap` (người, qua MFA) | Admin (DRF-5 D1; least privilege làm trước L3) | Entry STANDARD; `AmazonEKSClusterAdminPolicy` chỉ khi `bootstrap_cluster_admin=true` | Role: CLI DRF-5. Entry và association: Terraform |
| Role cluster (EKS dùng) | `AmazonEKSClusterPolicy` | — | Terraform (module EKS) |
| Role node | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` | EKS tự map cho node | Terraform (module EKS) |
| IAM user `<USER>` + MFA (break-glass) | Admin qua console | Không có entry; sửa quyền bằng EKS API khi cần | Thủ công (DRF-5) |
| Observer | — | Chưa tạo | Để sau |
| OIDC provider | Chưa có role nào tin nó | — | Terraform; role controller ở P3 |

**Vì sao bootstrap phải có trước controller (ADR-0003):** Argo CD, kro và Crossplane đều là
Pod chạy *trong* cluster. Muốn có chúng thì trước đó phải có API server, mạng (vpc-cni),
DNS (coredns), node đã Ready, và OIDC để cấp quyền AWS cho chúng. Terraform dựng nền này;
controller không thể tự dựng cái cluster mà chính nó đang chạy bên trong.

## Chuẩn bị — mỗi lần mở terminal mới

Giống DRF-8: `cd` vào `infra/terraform`, chạy `zdr-bootstrap` để nhập MFA, rồi
`export AWS_PROFILE=zdr-tf` và `export AWS_REGION=us-east-1`.

Lưu ý:
- Phiên còn dưới khoảng 15 phút thì AWS CLI sẽ đòi mã MFA và lệnh của Terraform sẽ đứng im.
  Hãy làm mới phiên **trước** khi plan.
- Trên Git Bash, đường dẫn SSM bắt đầu bằng `/aws/...` bị tự đổi thành đường dẫn Windows.
  Trước các lệnh `aws ssm` ở bước 1, chạy `export MSYS_NO_PATHCONV=1`.

## Bước 1 — Đọc phiên bản để pin (chỉ đọc, khi muốn nâng cấp)

Lệnh này lấy bản add-on mặc định cho 1.35. Đổi `coredns` thành `vpc-cni` hoặc `kube-proxy` để xem add-on khác:

```bash
aws eks describe-addon-versions --kubernetes-version 1.35 --addon-name coredns --query 'addons[0].addonVersions[?compatibilities[?defaultVersion==`true`]].addonVersion | [0]' --output text
```

Bản AMI AL2023 được khuyến nghị:

```bash
aws ssm get-parameter --name /aws/service/eks/optimized-ami/1.35/amazon-linux-2023/x86_64/standard/recommended/release_version --query Parameter.Value --output text
```

Đối chiếu kết quả với default của `addon_versions` và `system_node_ami_release_version`
trong `variables.tf`. Đã đọc ngày 31/10: `1.35.9-20261026`, và 3 add-on như ở phần Đích đến.

## Bước 2 — Ghi IP máy vào `run.tfvars` (file riêng tư)

```bash
MYIP=$(curl -s https://checkip.amazonaws.com)
```

```bash
echo "endpoint_public_access_cidrs = [\"$MYIP/32\"]" >> run.tfvars
```

Mở `run.tfvars` và kiểm chỉ có **một** dòng `endpoint_public_access_cidrs`. Không dán IP vào Git hay Linear.
Sau đó chạy `terraform fmt run.tfvars` để căn lại hàng. Nếu không, bước `fmt -check` trong `check.sh` sẽ báo FAIL.

## Bước 3 — Kiểm tĩnh, plan, plan gate

```bash
terraform init -backend-config=backend.hcl -lockfile=readonly
```

```bash
./scripts/check.sh
```

Lệnh trên chạy 16 test với AWS giả. Phải ra `RESULT: PASS`.

```bash
terraform plan -var-file=run.tfvars -out=tfplan
```

Kết quả đúng: `Plan: 50 to add, 0 to change, 0 to destroy.`

```bash
./scripts/plan_assert.sh tfplan
```

Phải ra 25 dòng `PASS`. Phần EKS kiểm các điều sau:
- version 1.35, support STANDARD, auth API, tắt creator admin;
- endpoint private bật, endpoint public chỉ mở cho dải /24 hoặc hẹp hơn;
- log audit + authenticator giữ 3 ngày, không có KMS key riêng;
- node AL2023 có pin bản AMI, dùng m6i.large, tối đa 2 node;
- IMDSv2 bắt buộc, hop limit 1;
- 3 add-on đều pin bản;
- entry cho role bootstrap;
- có OIDC;
- không có admin association.

```bash
rm tfplan
```

## Plan cho window (khi đã được duyệt chạy L3)

```bash
terraform plan -var-file=run.tfvars -var bootstrap_cluster_admin=true -out=tfplan
```

```bash
ADMIN_WINDOW=1 ./scripts/plan_assert.sh tfplan
```

Kết quả đúng: 51 resource, trong đó thêm `aws_eks_access_policy_association`.
Nếu chạy gate thường (không có `ADMIN_WINDOW=1`) trên plan này thì nó **phải** FAIL.
Hết window: plan lại với giá trị mặc định (`false`), rồi apply để gỡ quyền admin.
Sau đó kiểm theo DRF-5 AC-04: liệt kê lại association phải rỗng, và một thao tác admin phải bị `Forbidden`.

## Chi phí (theo plan chính xác, cho một window 8 giờ)

| Khoản | 1 node | 2 node |
|---|---|---|
| EKS control plane, 0.10 USD/giờ | 0.80 | 0.80 |
| m6i.large, 0.096 USD/giờ | 0.77 | 1.54 |
| EBS gốc 20 GB gp3 (mặc định của AMI) | 0.02 | 0.04 |
| IPv4 public của node, 0.005 USD/giờ | 0.04 | 0.08 |
| CloudWatch Logs (ghi 0.50 USD/GB, ước khoảng 0.1–0.2 GB) | ≤ 0.10 | ≤ 0.10 |
| Network DRF-8 | 0 | 0 |
| **Tổng** | **≈ 1.73 USD** | **≈ 2.56 USD** |

Cả hai mức đều dưới trần P2 là 5 USD. Giá lấy từ COST_PLAN §5.2; dung lượng log là ước tính.
Kiểm lại giá ngay trước L3.

## Hoàn tác

- Chưa apply nên không có gì trên AWS để xóa.
- Sau L3, xóa bằng `terraform plan -destroy -out=d.tfplan` rồi `terraform apply d.tfplan`, theo thứ tự node → cluster → network.
- Sau khi destroy, `terraform state list | wc -l` phải ra 0.
- Role bootstrap (DRF-5) và bucket state (DRF-6) nằm ngoài root này nên không bị xóa theo.

## Chưa kiểm được (chờ L3)

- Node có Ready không; coredns có chạy không; kubectl từ máy owner có vào được không.
- Gỡ admin thì kubectl có thật sự bị `Forbidden` không.
- EBS gốc có đúng 20 GB không. Plan không đặt `block_device_mappings`, nên dung lượng do AMI quyết định.
- Lượng log thật và chi phí thật.
