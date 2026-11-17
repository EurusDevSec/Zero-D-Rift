---
id: ADR-0009
title: P6 BatchTrainingJob trên CPU khi quota GPU bị từ chối
status: ACCEPTED
date: 2026-11-17
accepted_date: 2026-11-17
decision_source: AWS Support từ chối hai quota G/VT (COST_PLAN §7.3.1); owner chọn phương án A
authority: DOCUMENTATION_ONLY_NO_AWS
---

# Context and authority

Ver3 đặt `BatchTrainingJob` là workload cần **GPU node** động (§4.2, H2 ở §4.3,
§6.5, scale-down time ở §8.2, P6 ở §12). GPU được dùng để chứng minh cơ chế
provisioning và reclamation, không để huấn luyện mô hình lớn (ver3 §5.2).

Account dự án có quota G/VT bằng **0** cả On-Demand lẫn Spot ở `us-east-1`
(COST_PLAN §7.3). Owner xin tăng lên 4 vCPU (một `g4dn.xlarge`) ngày 31/10, bị
từ chối, appeal có use case chi tiết và bị từ chối lần hai ngày 01/11 (On-Demand)
và 03/11 (Spot). Chi tiết ở COST_PLAN §7.3.1. AWS chỉ hẹn xét lại sau kỳ billing
tiếp theo, tức sớm nhất tháng 12/2026, sau giai đoạn đo P9.

Ver3 §15.2 yêu cầu mọi thay đổi phạm vi, metric hay kiến trúc phải có ADR ghi lý
do. Campaign chính thức chưa bắt đầu, nên thay đổi này không phải là sửa metric
sau khi đã xem kết quả.

Owner chấp nhận phương án A ngày 17/11/2026, không cần hỏi thêm giảng viên
(nguyên văn: "khong cần hỏi đâu cứ bám đúng kể hoạch và hạn chế chỉ ra là
được"). ADR không cấp quyền apply, gửi quota request hay chạy window AWS nào.

# Options considered

| # | Phương án | Đánh giá |
|---|---|---|
| A | **Batch chạy trên node CPU do Karpenter tạo (Spot và On-Demand)**, giữ nguyên số trial, ngưỡng và quy trình đo | **Chọn.** Chứng minh được cùng cơ chế (KEDA → Job pending → Karpenter tạo node → checkpoint S3 → thu hồi node), nằm trong quota Standard hiện có |
| B | Chờ quota GPU sau kỳ billing tháng 12 | Không khả thi với lịch: P9 phải xong trước đó, và AWS không hứa sẽ duyệt |
| C | Chủ động tiêu 90% quota hiện có để "mở khoá" | Loại: tốn tiền không phục vụ đo lường, trái COST_PLAN, vẫn phải chờ tháng 12 |
| D | Dùng account khác có lịch sử thanh toán | Chỉ khi trường hoặc giảng viên cấp account. Đổi identity, state và IAM (ADR-0007), nên cần ADR riêng. Không đề xuất ở đây |
| E | Bỏ hẳn P6 | Đây là phương án cắt đã chốt khi trễ (thứ tự cắt: P6 → P8 → P5). Mất H2, H5 và scale-down. Giữ làm dự phòng nếu rebaseline không còn thời gian cho A |

# Decision

## 1. Thay GPU bằng CPU, giữ cơ chế

1. Pod batch request CPU/memory cố định, không request `nvidia.com/gpu`.
2. Karpenter NodePool batch chỉ cho một danh sách nhỏ instance type Standard,
   2 vCPU (ứng viên: `m6i.large`, `m5.large`, `c6i.large`; chốt ở P6-T1), kèm
   `limits.cpu` để không vượt quota.
3. KEDA ScaledJob, S3 checkpoint/resume, Spot preference với On-Demand fallback,
   idle window 1.800 s và teardown giữ nguyên như thiết kế GPU.
4. Workload huấn luyện là model nhỏ chạy trên CPU (vài phút đến dưới 45 phút),
   phát marker `TRAINING_STARTED` như contract hiện tại.

## 2. Hypothesis và metric

Không đổi ngưỡng, số trial hay cách tính. Chỉ đổi đối tượng đo từ GPU sang CPU:

| Mục | Hiện tại | Đề xuất |
|---|---|---|
| H2 | p95 ≤ 900 s tới khi GPU workload bắt đầu, 20 trial | Giữ p95 ≤ 900 s, 20 trial; điểm kết thúc là training process trên node CPU do Karpenter tạo |
| H3 batch | ≥ 18/20 | Giữ nguyên |
| H5 | ≥ 40% tiết kiệm, ≥ 5 cặp | Giữ nguyên; hai nhánh so sánh dùng cùng instance type CPU (Spot + scale-to-zero vs On-Demand always-on) |
| GPU scale-down time | 20 trial "khi GPU path chạy được" | Đổi tên thành **node scale-down time** trên node CPU, cùng 20 trial |
| EXPERIMENT_PLAN §7 | "GPU request", "GPU family allowlist" | "CPU/memory request", "instance type allowlist" |

Mọi dataset, bảng và slide ghi rõ nhãn `CPU_SUBSTITUTE_FOR_GPU` cho các trial batch.

## 3. Ràng buộc quota CPU

- **Standard Spot: 5 vCPU.** Đủ cho một node batch 2 vCPU (dư cho một node thứ hai
  nếu Karpenter thay node).
- **Standard On-Demand: 5 vCPU.** Hai node system `m6i.large` đã dùng 4 vCPU. Nhánh
  On-Demand của H5 (thêm 2 vCPU) **không chạy cùng lúc được** với cấu hình đó.
  P6-T1 phải chọn một trong: giảm system xuống 1 node trong window batch, dùng
  instance 1 vCPU cho nhánh baseline (phải giống nhánh optimized, nên ít khả thi),
  hoặc owner xin tăng Standard On-Demand (cũng có thể bị từ chối). Chưa chốt ở đây.
- Giá CPU lấy từ COST_PLAN §5.2 (`m6i.large` 0,096 USD/h On-Demand); giá Spot đọc lại
  trước mỗi window. Ngân sách GPU 15 USD trong COST_PLAN không còn dùng cho GPU;
  việc chuyển phần đó sang dòng CPU batch là quyết định riêng của owner.

## 4. Điều được và không được claim

- **Được:** nền tảng tự tạo và thu hồi capacity theo yêu cầu batch, xử lý Spot
  interruption bằng checkpoint/resume, và mức tiết kiệm Spot + scale-to-zero so
  với On-Demand always-on, **trên CPU**.
- **Không được:** thời gian sẵn sàng hay chi phí của GPU node; NVIDIA device
  plugin, GPU AMI hay GPU capacity của Spot. Không ngoại suy kết quả CPU sang GPU.
- Báo cáo nêu lý do: quota G/VT bị AWS từ chối hai lần, có ngày và trạng thái,
  không phải do thiết kế.
- Thiết kế GPU (NodePool GPU, device plugin) không được build hay đưa vào code
  chưa kiểm thử. Nó chỉ nằm ở mục hướng phát triển.

# Consequences

- Cần sửa ở P6-T1, cùng lúc chỉnh SPEC-P6 cho khớp thực tế: ver3 (§4.2, §4.3 H2, §6.5, §8.2, §9.2, §10,
  §11, §12 P6, §14), EXPERIMENT_PLAN (§3, §7), COST_PLAN (§5.3 dòng GPU, §9), SYSTEM_DESIGN, SPEC-P6 nháp
  (`DRAFT_FABLE_20261116`, nấc "Both denied" ở §10.1) và DRF-19.
- Rủi ro còn lại: Spot CPU thiếu capacity trong window (dùng fallback On-Demand
  có nhãn, không đổi nhãn trial để claim H5); ràng buộc On-Demand 5 vCPU ở mục 3.
- Không giảm trial, acceptance, learning gate hay teardown (ver3 §12.1).

# Status and next action

`ACCEPTED` 17/11/2026, phương án A. Phương án E (bỏ P6) chỉ dùng lại nếu
rebaseline không còn thời gian. Các file ở mục Consequences được sửa ở P6-T1;
tới lúc đó, ADR này là nguồn quyết định cho mọi chỗ ver3 còn ghi GPU. Báo cáo và
slide phải nêu giới hạn ở mục 4.
