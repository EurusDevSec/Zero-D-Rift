---
evidence_id: P7-T1-MICROLAB
phase: P7
task: P7-T1 (DRF-82), owner micro-lab, 15 minutes
inputs: SYNTHETIC (same as tests/experiments/test_cost_calc.py MicroLabPair)
status: WAITING_FOR_OWNER (Claude does not fill in the answers)
---

# Micro-lab P7-T1: tính tay một cặp H5

Mục tiêu: bạn tự tính chi phí biến đổi của **hai arm** trong một cặp, rồi tính **saving ratio** bằng giấy bút hoặc máy
tính bỏ túi, **trước khi** xem đáp án trong test. Số của bạn phải khớp với `cost_calc.py` tới 6 chữ số thập phân. Nếu không
khớp thì phải tìm ra bên nào sai: bạn, hay code.

So sánh: đây là phép tính **tiền taxi**. Đồng hồ chạy theo giây (tối thiểu 60 giây), nhân đơn giá theo giờ, cộng tiền
gửi xe (ổ đĩa 20 GB tính theo tháng, chia theo giây).

## Dữ liệu (giả, cố định)

| | Baseline (thủ công) | Optimized (nền tảng) |
|---|---|---|
| Loại máy | m5.large On-Demand | m5.large Spot |
| Đơn giá | 0.096 USD/giờ | 0.0397 USD/giờ |
| Launch → terminate | 01:00:00 → 01:36:00 | 02:00:00 → 02:07:00 |
| Ổ đĩa | gp3 20 GB, 0.08 USD/GB-tháng | như bên trái |
| Tháng | tháng 11 = 30 ngày | như bên trái |

Công thức ([COST_MEASUREMENT](../../finops/COST_MEASUREMENT.md) §3):

```text
billed_seconds = max(60, ceil(terminate − launch))
compute = billed_seconds / 3600 × USD/giờ
volume  = GB × billed_seconds × USD/GB-tháng / (30 × 86400)
saving_ratio = (baseline − optimized) / baseline
```

## Bạn điền (không xem test trước)

| Câu | Đáp án của bạn |
|---|---|
| 1. billed_seconds baseline | |
| 2. compute baseline (6 số lẻ) | |
| 3. volume baseline | |
| 4. tổng baseline | |
| 5. billed_seconds optimized | |
| 6. tổng optimized | |
| 7. saving ratio (4 số lẻ) | |
| 8. Vì sao ratio này **không** chứng minh được H5? (một câu) | |
| 9. Nếu idle window của baseline là 0 thay vì 1,800 s, ratio tăng hay giảm? Đoán trước rồi tính lại. | |

Sau khi điền, chạy để so:

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift && python -I -m unittest discover -s tests/experiments -p 'test_cost_calc.py' -v 2>&1 | grep -i hand
```

```bash
grep -n -A14 'class MicroLabPair' tests/experiments/test_cost_calc.py
```

Kết quả (Claude ghi lại lời bạn, nguyên văn): _chưa có_.
