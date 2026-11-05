# DRF-13 — Đối chiếu evidence P2 với SPEC-P2 (04/11/2026)

Người đối chiếu: Claude (implementer của DRF-9..12). **Đây không phải review độc lập**: AC-03 của DRF-13
cần agent khác (Codex) hoặc người khác ghi candidate, findings và limits.
Candidate: `main` tại `c881fd0` (sau PR #17). Nguồn: `.agent/specs/SPEC-P2_REPRODUCIBLE_EKS_BOOTSTRAP.md` §1, §4, §5 Task 8–9, §8.

## §1 MUST deliverables

| Deliverable | Trạng thái | Bằng chứng |
|---|---|---|
| `infra/terraform/` root và module | Có | `infra/terraform/` (root, `modules/network`, `modules/cluster`); DRF7, DRF8, DRF9 |
| Khóa version provider/module | Có | `.terraform.lock.hcl`; aws 6.67.0, EKS 21.26.0, VPC 6.7.3; Terraform 1.16.4 (DRF3) |
| Quyết định remote state/security và cách bootstrap | Có | ADR-0007; `P2_STATE_BACKEND.md`, `P2_BOOTSTRAP_ACCESS.md`; DRF5, DRF6 |
| `docs/runbooks/P2_EKS_BOOTSTRAP_AND_TEARDOWN.md` | **Lệch tên** | Nội dung tách thành `P2_EKS.md` (plan) và `P2_L3_WINDOW.md` (window, smoke, teardown). Không có file đúng tên SPEC. Đề xuất: ghi nhận tách file, không tạo bản sao |
| Plan, smoke, inventory, teardown evidence đã che | Có | DRF9 (plan), DRF10 (gate), DRF11_L3_RUN (smoke, inventory, teardown); raw log để ngoài Git |
| Một vòng create/verify/destroy có quan sát, sau L3 approval | Có | DRF11_L3_RUN_20261104: apply 51, smoke 33/33, destroy 50, state 0 |

## §1 Negative boundaries

| # | Ranh giới | Kết quả | Bằng chứng |
|---|---|---|---|
| 1 | Không cài Argo CD, Crossplane, kro, KEDA, Karpenter, Kyverno, OpenCost | Đạt | Add-on chỉ vpc-cni, kube-proxy, coredns (smoke) |
| 2 | Không RDS, GPU, workload node pool, golden path | Đạt | plan_assert: no `aws_db_instance`, no `aws_rds_cluster`; 1 node group system m6i.large. Có `rds:subgrp` (DB subnet group, miễn phí) |
| 3 | Không NAT mặc định | Đạt | plan_assert + smoke "no NAT route anywhere"; inventory `nat_gateways_live=0` |
| 4 | Không cấp cluster-admin/AWS admin cho workload/controller/người dùng hằng ngày | Đạt có giới hạn | Không có creator admin; admin chỉ bật cho role bootstrap trong window và đã gỡ (Forbidden). Role Terraform vẫn là AdministratorAccess: R1 hoãn theo quyết định owner 04/11 |
| 5 | Không credential, account ID, state, plan nhạy cảm, kubeconfig trong Git/evidence | Đạt | `check.sh` secret scan 9/9; evidence chỉ chứa số đếm |
| 6 | Không dùng IAM user key dài hạn cho workload; phương thức operator đã review trước L3 | Đạt | MFA AssumeRole 1 giờ, `credential_process`; DRF5 |
| 7 | Không coi validate/plan là runtime | Đạt | Runtime claim dựa trên smoke L3 |
| 8 | Không chạy quá window/cost hoặc khi còn orphan chưa rõ | Đạt | Đóng 15:20Z, trước freeze; orphan duy nhất (SG `launch-wizard-1`, không thuộc dự án) đã xóa có duyệt |

## §4 Acceptance scenarios

| Scenario | Kết quả | Bằng chứng / giới hạn |
|---|---|---|
| Plan đúng ranh giới ownership và cost | Đạt | Gate 25/25 (window), shape hash khớp; giá Price List API ≈ 0,203 USD/giờ, trong mức P2 ≤ 5 USD |
| Bootstrap dùng được | Đạt | Smoke 33/33: EKS 1.35 API, node AL2023 Ready, OIDC, access, endpoint, IMDS, log, S3 endpoint. **Giới hạn**: tag không có check riêng trong smoke; tag được thấy qua Tagging API trong inventory |
| Chạy lại thì dự đoán được | Đạt có disposition | Không chạy một plan "cùng config" riêng. Plan gỡ admin (chỉ khác biến `bootstrap_cluster_admin`) cho `no-op=50, delete=1`; thay đổi duy nhất là thay đổi chủ ý |
| Teardown đầy đủ | Đạt (ngay sau destroy) | 50 destroyed, state 0, inventory CLEAN 15:32Z. Inventory trễ và Billing: xem DRF-12 |

## §8 P2 completion rule

| Điều kiện | Trạng thái |
|---|---|
| Plan, create, verify, destroy với evidence đã che | Đạt |
| Không còn tài nguyên trả phí chưa duyệt | Đạt ngay sau destroy; chờ inventory trễ + Billing (DRF-12 AC-04) |
| Owner đạt `PRACTICED` + `EXPLAINED` cho Terraform/state/dependency/teardown | **Chưa đạt.** Owner đã thực hành (MFA, merge, duyệt, đọc kết quả) nhưng chưa trả lời teach-back SPEC §7. Ngày 04/11 owner chọn bỏ qua teach-back của P2_L3_WINDOW phần H |

## AC-02 — Lab owner ngày 05/11/2026

Nguồn: owner dán bảng tổng kết lab vào chat sáng 05/11. Claude không hướng dẫn lab này và không thấy
lúc owner đoán, nên chỉ đối chiếu được phần artifact:
`playground/runs/TF-T01-20261030-01` có `tfplan` 10:55 VN, state 11:15 VN (serial 89). Backup state có
9 instance `terraform_data` (vpc, public/db subnets, s3_gateway_endpoint, eks, oidc_provider,
system_nodes); state cuối 0 resource. Khớp với "9 add" và "9 destroyed; state 0".

| Bước | Owner đoán | Kết quả thật | Đánh giá |
|---|---|---|---|
| Plan | 9 add; VPC trước | 9 add | Đúng; lý do được sửa từ "đầu file" thành "do tham chiếu" |
| Apply | Subnet và endpoint song song; nhóm cluster tạo cuối | EKS trước, rồi OIDC và node | Đúng |
| Plan lần 2 | NOOP | NOOP | Đúng; hiểu exit code 0/2 |
| Đổi version | Update, không replace | 0 add, 2 change, 0 destroy | Đúng; biết ký hiệu `~` |
| Đổi tên cluster | EKS, OIDC, node bị replace theo | 3 add, 6 change, 3 destroy | Đúng; ký hiệu `-/+` mới học |
| Destroy | (không đoán) | 9 destroyed; state 0 | Đã chạy |

Đối chiếu SPEC §7:

| Câu SPEC §7 | Mức thể hiện |
|---|---|
| 2. Dependency graph xếp VPC, EKS, OIDC, node thế nào | **Đã thể hiện** (đoán đúng thứ tự, lý do "do tham chiếu") |
| 3. Plan rỗng chứng minh gì | **Một nửa**: đoán đúng NOOP và exit code; chưa nói plan rỗng *không* chứng minh được gì |
| Mục tiêu 2: phân biệt create/update/replace/destroy | **Đã thể hiện** (`~` và `-/+`, replace kéo theo phụ thuộc) |
| 1. State là gì, mất hoặc lộ state nguy hiểm thế nào | Chưa có |
| 4. Vì sao ADR-0006 bỏ NAT, kiểm soát bù | Chưa có |
| 5. Phân biệt lỗi Terraform, lỗi AWS authorization, node không join | Chưa có |
| 6. Inventory nào bắt buộc trước khi tuyên bố teardown xong | Chưa có lời giải thích (đã thực hành ở window 04/11) |

Kết luận AC-02: **PRACTICED đạt** (lab local có đoán trước + window L3 thật).
**EXPLAINED đạt một phần**: dependency, idempotency, update vs replace. Còn thiếu câu 1, 4, 5, 6 và
nửa sau câu 3. Owner giữ quyền nghiệm thu cuối.

## Kết luận

- DRF-13 AC-01 (evidence đủ mapping tới SPEC): **đạt**, với 3 lưu ý: runbook lệch tên, re-plan dùng disposition thay vì plan cùng config, R1 hoãn.
- DRF-13 AC-02 (owner explain): **đạt một phần**, xem mục trên. Claude không được viết thay phần còn thiếu.
- DRF-13 AC-03 (review độc lập): **chưa có**.
- DRF-13 AC-04 (SPEC-P3): chưa được làm, vì gate P2 chưa đạt.
