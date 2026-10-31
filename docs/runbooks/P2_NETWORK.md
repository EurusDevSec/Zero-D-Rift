# P2 network — VPC, subnet, S3 endpoint, không NAT (DRF-8)

Trạng thái: code xong, **chỉ plan, chưa apply**. Network chỉ được tạo thật ở đợt L3 (DRF-11),
khi có duyệt riêng. Nguồn: SPEC-P2 Task 4, ADR-0006.
Chi phí: plan và test không tốn tiền; 19 resource này nếu tạo cũng 0 USD/giờ (xem **Chi phí**).

## Đích đến

```
VPC 10.0.0.0/16 (us-east-1)
├─ public  10.0.0.0/24 (1a), 10.0.1.0/24 (1b)   map_public_ip=true, tag kubernetes.io/role/elb
│     └─ route table public: 0.0.0.0/0 → Internet Gateway ; S3 → gateway endpoint
├─ db      10.0.10.0/24 (1a), 10.0.11.0/24 (1b) không public IP
│     └─ 2 route table db: KHÔNG có route ra ngoài ; DB subnet group cho RDS sau này
├─ S3 gateway endpoint: policy chỉ cho bucket của account mình + đọc ECR/AL2023 của AWS
└─ default security group: 0 rule (không vào, không ra)
Không có: NAT, Elastic IP, RDS, interface endpoint, SSH
```

Node EKS (DRF-9) sẽ nằm ở subnet public và có IP public để kéo image qua IGW, thay cho NAT
(NAT tốn khoảng 33 USD/tháng). Chặn truy cập vào node là việc của security group, không phải của subnet.

## Code nằm đâu

| File | Vai trò |
|---|---|
| `infra/terraform/main.tf` | Gọi `module "network"` với CIDR tính sẵn trong `locals.tf` |
| `infra/terraform/modules/network/main.tf` | Gọi module VPC 6.7.3, module VPC endpoints 6.7.3, và dựng policy cho endpoint |
| `infra/terraform/tests/network.tftest.hcl` | Test với AWS giả: 0 NAT, 2+2 subnet, 1+2 route table, endpoint loại Gateway |
| `infra/terraform/scripts/plan_assert.sh` | Đọc plan thật, rồi kiểm 15 điều kiện ở mục bước 4 |

## Chuẩn bị — mỗi lần mở terminal mới

Giống DRF-6. Lệnh dưới có thể hỏi mã MFA:

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
```

```bash
aws sts get-caller-identity --profile zdr-bootstrap --query Arn --output text | sed -E 's/[0-9]{12}/<ACCOUNT>/'
```

```bash
export AWS_PROFILE=zdr-tf
```

```bash
export AWS_REGION=us-east-1
```

Phải `export` **trước** khi chạy `terraform init` hoặc `plan`. Nếu quên, Terraform sẽ lấy key
dài hạn của profile `default`, đúng thứ DRF-5 muốn tránh.

## Bước 1 — Init (tải module VPC, nối backend S3)

```bash
terraform init -backend-config=backend.hcl -lockfile=readonly
```

Kết quả đúng: `Terraform has been successfully initialized!`. Lần đầu sẽ tải module
`terraform-aws-modules/vpc/aws` 6.7.3 vào `.terraform/modules/`; thư mục này đã được gitignore.

## Bước 2 — Kiểm tĩnh (không gọi AWS)

```bash
./scripts/check.sh
```

Phải thấy `RESULT: PASS`. Lệnh này đã gồm `terraform test`: 9 test của guardrails và network chạy với AWS giả.

## Bước 3 — Plan thật (chỉ đọc AWS, không tạo gì)

`run.tfvars` là file riêng tư, đã gitignore. Nếu chưa có thì tạo từ file mẫu:

```bash
cp run.tfvars.example run.tfvars
```

```bash
sed -i 's/^run_id .*/run_id     = "P2-PLAN-20261031-01"/' run.tfvars
```

```bash
terraform plan -var-file=run.tfvars -out=tfplan
```

Kết quả đúng: `Plan: 19 to add, 0 to change, 0 to destroy.`

Plan có lấy khóa state trong S3 rồi nhả ra. Nó không ghi state và không tạo resource.
File `tfplan` có chứa account ID, nên phải gitignore và không được dán ra ngoài.

## Bước 4 — Plan gate

```bash
./scripts/plan_assert.sh tfplan
```

Phải ra 15 dòng `PASS` và dòng cuối `RESULT: PASS`. Những gì được kiểm:

| # | Kiểm | Vì sao |
|---|---|---|
| 1 | Chỉ có hành động `create` | Lần đầu không được sửa hay xóa thứ gì |
| 2 | Không NAT, EIP, RDS, EC2, interface endpoint | Các thứ này tính tiền theo giờ (ADR-0006) |
| 3 | Đúng 19 resource, chia theo loại | Plan không phình to ngầm |
| 4 | Route duy nhất là public 0.0.0.0/0 → IGW | Subnet DB không có đường ra Internet |
| 5 | Chỉ subnet public mới gán IP public | DB không bao giờ có IP public |
| 6 | Không có ingress từ 0.0.0.0/0, không mở cổng 22; default SG 0 rule | Không ai từ Internet vào được |
| 7 | Endpoint S3 loại Gateway, policy giới hạn | Miễn phí, và không làm cửa cho S3 của account lạ |
| 8 | Đủ 6 tag bắt buộc | Kiểm kê và dọn dẹp (COST_PLAN §10) |

Muốn tự kiểm script có bắt lỗi thật không: script nhận được cả file `.json`. Trong evidence
DRF-8 có một bài thử chèn NAT, SSH, RDS và route DB ra Internet vào plan, và script báo `FAIL` đủ cả 4.

## Bước 5 — Dọn file plan

```bash
rm tfplan
```

## Chi phí (AC-04)

| Resource trong plan | Giá |
|---|---|
| VPC, 4 subnet, 3 route table, 4 route table association, 1 route | 0 |
| Internet Gateway | 0. Chỉ tính tiền dữ liệu đi ra Internet, và 100 GB/tháng đầu được miễn phí |
| S3 gateway endpoint | 0 (interface endpoint mới tính tiền theo giờ) |
| DB subnet group, default SG, default NACL, default route table | 0 |
| **Tổng theo giờ** | **0 USD/giờ** |

Khoản tiền mạng thật sẽ đến ở DRF-9: mỗi node có 1 IP public, giá 0.005 USD/giờ.
Hai node chạy 8 giờ hết khoảng 0.08 USD. Con số này đã có sẵn trong ước tính P2 ở COST_PLAN §7.4.
Giá lấy từ trang giá AWS VPC; kiểm lại ngay trước L3.

## Hoàn tác

- Chưa apply nên trên AWS không có gì để xóa.
- Muốn bỏ code thì revert commit DRF-8, rồi `terraform init` lại.
- Sau L3, network bị xóa bằng `terraform destroy` cùng với cluster (DRF-11). Bucket state DRF-6 không bị ảnh hưởng.

## Chưa kiểm được (chờ L3)

- Node có thật sự kéo được image từ ECR qua endpoint không (bucket `prod-us-east-1-starport-layer-bucket`).
- Tên bucket repo AL2023 (`al2023-repos-us-east-1-de612dc2`) lấy theo tài liệu AWS, chưa thử thật.
  Nếu sai thì node chỉ không cài thêm được gói qua `dnf`; image EKS vẫn khởi động bình thường.
- Truy cập S3 của account khác (dataset công khai) từ subnet public sẽ bị policy chặn.
  Nếu P4 cần thì thêm một statement và review lại.
