# P2 L3 window — xin duyệt, tạo, kiểm, dọn (DRF-10 → DRF-11)

Trạng thái: **gói hồ sơ để owner duyệt, chưa chạy.** Runbook này chưa cho phép apply.
Chỉ được apply khi owner đã duyệt một **window request** cụ thể (phần A) trong chat hoặc Linear.
Window đã duyệt ngày 05/10 đã hết hạn và không dùng lại được.

Nguồn:
- SPEC-P2 Task 6, Task 7;
- COST_PLAN §7–11;
- ADR-0007.

Runbook trước đó:
- [P2_BOOTSTRAP_ACCESS](P2_BOOTSTRAP_ACCESS.md): phiên MFA;
- [P2_STATE_BACKEND](P2_STATE_BACKEND.md): bucket state;
- [P2_NETWORK](P2_NETWORK.md);
- [P2_EKS](P2_EKS.md).

Evidence: `docs/evidence/p2/DRF10_L3_GATE_20261031.md`.

## Sơ đồ một window

```
T-30m  Chuẩn bị: MFA, inventory CLEAN, IP, Budget/gross ──┐ dừng nếu có gì sai
T+0    plan window → gate 24/24 → shape hash KHỚP → apply  │
T+0:20 cluster + 1 node Ready → verify/smoke (DRF-11)      │ ≤ 4 giờ chạy
T_end-2h  FREEZE: không create mới, chỉ export evidence + dọn
          (tùy chọn) gỡ admin → kubectl phải Forbidden
          destroy → state list = 0 → inventory CLEAN
T+1 ngày  Đối soát billing, chạy inventory lần nữa
```

## A. Mẫu window request (owner điền, rồi duyệt)

Chép mẫu này vào Linear DRF-11 hoặc vào chat. **Không ghi account ID, IP hay tên bucket.**

```
WINDOW REQUEST — P2 L3
RunId:            P2-L3-YYYYMMDD-01
Bắt đầu:          YYYY-MM-DD HH:MM Asia/Saigon (= HH:MM UTC)
Kết thúc cứng:    bắt đầu + 6 giờ (4 giờ chạy + 2 giờ dọn)
expires_at (tag): giờ kết thúc cứng, dạng UTC ...Z
Freeze-new-create: kết thúc cứng − 2 giờ
Người dọn (teardown owner): HoangLV, có mặt suốt window
Git revision:     <commit trên main>
Plan shape sha256 (window, 51 resource): 0f16874574067ba338874ba413c7124ba195fb4c249a09b96a2db4a4319c9879
Plan shape sha256 (mặc định, 50):        41f63a72e8f447dec01b34642a89c2e8233af1e7ee38c747bce75baab5565fbc
Ước tính:         ≈ 0.21 USD/giờ → ≈ 1.3 USD cho 6 giờ; trần window 2.6 USD
P2 đã tiêu (gross, trước credit): ___ USD; P2 còn lại sau window: ___ USD (phải ≥ 0 với trần 5 USD)
Owner duyệt: "Duyệt window P2-L3-YYYYMMDD-01" (gõ trong chat)
```

Chỉ được apply khi đủ 5 điều kiện sau (SPEC Task 6 gate):
1. Có exact plan, và shape hash khớp.
2. Danh tính đúng.
3. Còn dưới trần chi phí.
4. Window đang mở.
5. Owner đã duyệt người dọn.

## B. Điều kiện dừng

Gặp **bất kỳ** điều nào dưới đây thì dừng tạo mới và chuyển ngay sang phần E (dọn):

| # | Tình huống | Làm gì |
|---|---|---|
| S1 | `plan_assert` FAIL, hoặc shape hash khác bản đã duyệt | **Không apply.** Chưa tạo gì nên không cần dọn. Sửa code, xin duyệt lại. |
| S2 | Apply lỗi giữa chừng | Không thử lại quá 1 lần. Chạy destroy những gì đã tạo, ghi lỗi làm evidence. |
| S3 | Node không Ready sau 30 phút kể từ khi apply xong | Thu log và trạng thái, rồi destroy. |
| S4 | Inventory thấy thứ không có trong plan (NAT, EIP, load balancer, instance thừa, volume lạ) | Destroy, rồi dọn tay thứ còn sót. Ghi lại như một lỗi. |
| S5 | Tới giờ freeze (kết thúc cứng − 2 giờ) | Chỉ còn export evidence và dọn. |
| S6 | Nhận email Budget ở bất kỳ ngưỡng nào, hoặc gross P2 + phần còn lại của window > 5 USD | Dọn ngay. |
| S7 | Không làm mới được phiên MFA, hoặc owner phải rời máy | Dọn trước khi rời máy. Không để cluster chạy qua đêm. |

Vì sao không trông vào Budget để phanh: Budget lấy số liệu billing chậm tới khoảng 1 ngày,
nên một window 6 giờ có thể hết mà email vẫn chưa tới. Đồng hồ, inventory và destroy mới là
phanh thật. Budget chỉ là lưới an toàn cuối.

## C. Chuẩn bị (T−30 phút) — chỉ đọc

Mở Git Bash, rồi:

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift/infra/terraform
```

```bash
zdr-bootstrap
```

```bash
export AWS_PROFILE=zdr-tf AWS_REGION=us-east-1
```

**Không** export `MSYS_NO_PATHCONV=1` cho cả terminal, vì nó làm `check.sh` hỏng ở `git -C`.
`inventory.sh` tự đặt biến này bên trong script.

1. Kiểm kê. Phải ra `RESULT: CLEAN`, nghĩa là chỉ còn 1 bucket state:

   ```bash
   ./scripts/inventory.sh
   ```

2. IP máy có còn đúng như trong `run.tfvars` không:

   ```bash
   grep -c "\"$(curl -s https://checkip.amazonaws.com)/32\"" run.tfvars
   ```

   Ra `1` là đúng. Ra `0` thì sửa dòng `endpoint_public_access_cidrs` (xem P2_EKS bước 2).

3. Sửa `run_id` và `expires_at` trong `run.tfvars` theo window request, rồi chạy `terraform fmt run.tfvars`.
   Đổi tag không làm đổi shape hash, vì hash chỉ tính trên action và địa chỉ resource.

4. Gross spend và credit: owner mở **Billing → Bills** (tổng trước credit) và **Billing → Credits** (còn bao nhiêu).
   Điền 2 số vào window request. Không dùng `aws ce` vì mỗi lần gọi tốn 0.01 USD.

## D. Plan, cổng kiểm, apply

Phiên MFA dài 1 giờ, nhưng AWS CLI sẽ đòi MFA lại khi còn khoảng 15 phút.
EKS cần khoảng 20 phút để tạo, nên **gõ `zdr-bootstrap` ngay trước bước plan và apply**.
Chỉ bắt đầu apply khi phiên còn ít nhất 40 phút:

```bash
jq -r '.Credentials.Expiration' ~/.aws/cli/cache/*.json
```

```bash
terraform init -backend-config=backend.hcl -lockfile=readonly
```

```bash
./scripts/check.sh
```

```bash
terraform plan -var-file=run.tfvars -var bootstrap_cluster_admin=true -out=tfplan
```

Đúng là `Plan: 51 to add, 0 to change, 0 to destroy.`

```bash
ADMIN_WINDOW=1 ./scripts/plan_assert.sh tfplan
```

Đúng là 24 dòng `PASS` và `RESULT: PASS`.

```bash
./scripts/plan_fingerprint.sh tfplan
```

`shape sha256` **phải khớp** giá trị trong window request. Khác là gặp S1: dừng.
`file sha256` lần nào plan cũng khác, vì file plan có ghi thời gian; điều đó bình thường.

Chỉ khi cả 3 điều trên đều đúng và owner đã gõ duyệt:

```bash
terraform apply tfplan
```

```bash
rm tfplan
```

## E. Kiểm (chi tiết smoke thuộc DRF-11)

```bash
aws eks update-kubeconfig --name zero-drift --region us-east-1
```

```bash
kubectl get nodes
```

Phải có 1 node `Ready`.

```bash
kubectl -n kube-system get pods
```

Phải thấy coredns, kube-proxy và aws-node đều `Running`.

```bash
./scripts/inventory.sh
```

Lần này kết quả **phải** là `NOT CLEAN`, vì cluster đang chạy. Lưu output để làm evidence, rồi
so các dòng `LEFT` với plan. Mong đợi có:
- `eks_clusters=1`;
- `ec2_instances_live=1`;
- `launch_templates=1`;
- `ebs_volumes=1`;
- `vpcs_non_default=1`;
- `vpc_endpoints_live=1`;
- `eks_log_groups=1`;
- `oidc_providers=1`;
- vài `enis` và `sg_non_default`.

Nếu thấy NAT, EIP, load balancer, RDS hoặc nhiều hơn 1 instance thì gặp S4.

## F. Freeze, gỡ admin, destroy — dành ít nhất 2 giờ

**Freeze-new-create** bắt đầu lúc (kết thúc cứng − 2 giờ). Từ lúc đó:
- không apply gì mới;
- không chạy thêm thử nghiệm nào;
- chỉ export evidence, rồi dọn.

1. Gỡ quyền admin (tùy chọn, là phép thử DRF-5 AC-04). Làm mới MFA, rồi:

   ```bash
   terraform plan -var-file=run.tfvars -out=tfplan
   ```

   Đúng là `0 to add, 0 to change, 1 to destroy`; resource bị xóa là association admin.

   ```bash
   terraform apply tfplan
   ```

   ```bash
   kubectl get nodes
   ```

   Lệnh này phải bị từ chối (`Forbidden` hoặc `Unauthorized`). Terraform destroy vẫn chạy được,
   vì nó gọi AWS API chứ không gọi Kubernetes API.

2. Destroy. Làm mới MFA, rồi:

   ```bash
   terraform plan -destroy -var-file=run.tfvars -out=d.tfplan
   ```

   Đúng là `50 to destroy` (hoặc 51 nếu bỏ qua bước 1).

   ```bash
   terraform apply d.tfplan
   ```

   ```bash
   rm d.tfplan
   ```

3. Kiểm sau dọn:

   ```bash
   terraform state list | wc -l
   ```

   Phải ra `0`.

   ```bash
   ./scripts/inventory.sh
   ```

   Phải ra `RESULT: CLEAN`.

Nếu destroy lỗi (thường gặp nhất là ENI hoặc security group còn bị giữ):
1. Đợi 5 phút, chạy lại `plan -destroy` và `apply`.
2. Vẫn còn sót thì xóa tay trong console, theo thứ tự: node group → cluster → ENI → SG → subnet → IGW → VPC.
3. Ghi lại như một lỗi. **Không** xóa dòng nào khỏi evidence.

Ngày hôm sau:
- chạy lại `./scripts/inventory.sh`;
- xem Bills;
- ghi gross của window vào evidence DRF-11.

## G. Thứ được giữ lại sau window

| Giữ | Vì sao | Hạn hoặc lần xem lại |
|---|---|---|
| Bucket state (DRF-6) | Chứa state và lock của mọi lần chạy; tốn gần 0 USD/tháng | Owner review 03/11/2026, sau đó 7 ngày một lần |
| Role `zero-drift-bootstrap`, IAM user + MFA (DRF-5) | Đường vào AWS; IAM không tính phí | Thu hẹp quyền trước L3 (rủi ro R1) |
| Budget `zero-d-rift-project` | Lưới an toàn; Budget không có action thì miễn phí | Hết kỳ ngày 01/01/2027 (xem quyết định B2) |

Tất cả những thứ khác phải bị xóa sau window:
- EKS, node, VPC, endpoint, log group, OIDC;
- mọi IP public, EBS và ENI.

## H. Owner tự giải thích lại (Claude không viết hộ)

Trả lời bằng lời của bạn, trước khi gõ duyệt window:

1. Plan window tạo những nhóm resource nào? Những cái nào tốn tiền theo giờ, và mỗi giờ bao nhiêu?
2. Vì sao shape hash phải khớp, còn file hash thì không cần khớp?
3. Apply lỗi ở giữa thì làm gì? Vì sao không được thử lại liên tục?
4. Freeze-new-create là gì, bắt đầu lúc nào? Vì sao cần dành 2 giờ cho việc dọn?
5. Sau destroy, cái gì còn lại trên AWS, và vì sao được phép giữ?
6. Vì sao Budget không phải là phanh khẩn cấp? Phanh thật là gì?
7. Gỡ admin xong thì kiểm bằng cách nào để biết là đã gỡ thật?

## Hoàn tác

- Runbook này và các script đều chỉ đọc, nên không có gì cần hoàn tác.
- `inventory.sh` chỉ gọi lệnh `describe`/`list`.
- `plan_fingerprint.sh` chỉ đọc file plan.
- Muốn bỏ hai script: `git rm infra/terraform/scripts/inventory.sh infra/terraform/scripts/plan_fingerprint.sh`.
