# Phiếu đếm thao tác (EXPERIMENT_PLAN §5.1, §5.4; SPEC-P7 T4)

Dùng **cùng một luật** cho baseline thủ công và đường nền tảng (IDP). Mỗi run một bản sao, lưu vào
`experiments/runs/<campaign>/<run>/interactions.md`. Claude ghi phiếu trong lúc bạn chạy; bạn chỉ chạy lệnh.

## Luật đếm (giống nhau cho hai đường)

| Loại | Đếm là | Ví dụ baseline | Ví dụ nền tảng |
|---|---|---|---|
| interaction | 1 mỗi lần người kích hoạt: gõ lệnh, submit form, approve hoặc merge, trả lời prompt, retry tay, sửa cấu hình | `aws ec2 run-instances`, `kubectl apply` | tạo PR, merge PR, retry bằng PR mới |
| command | 1 mỗi tiến trình CLI bạn gõ (một dòng có `&&` gồm hai lệnh thì đếm 2 command nhưng chỉ 1 interaction) | `create-bucket && put-bucket-tagging` = 2 | `git push` = 1 |
| automated action | thao tác do script hoặc controller làm thay | 8 thao tác của `bootstrap` (D8a) | kro, Crossplane, KEDA, Karpenter: mỗi object hoặc API call do controller tạo |
| wait | chờ thụ động; ghi thời gian, **không** đếm interaction | idle 1,800 s, chờ node Ready | chờ Argo sync, chờ Karpenter |
| error | mỗi lỗi nhìn thấy, kèm cách sửa (remedial action) | quota, timeout | Job Failed |

Không gom nhiều thao tác tự động thành "một bước" để có số đẹp. Báo cả ba số: interactions, commands và automated actions.

## Phiếu

```text
run_id:            ____________________   arm: baseline | optimized   path: RAG | batch
official:          false (P7 dry run)     profile: batch-cpu-small-v1 (batch only)
operator:          owner                  recorder: Claude
T0 (start, UTC):   ____________________   TEND/T1 (end, UTC): ____________________
result:            PASS | FAILED (stop rule: ________________)
```

| # | UTC | Bước runbook | Lệnh / hành động (không ID, không ARN) | interactions | commands | automated actions | wait (s) | lỗi / cách sửa |
|---:|---|---|---|---:|---:|---:|---:|---|
| 1 | | | | | | | | |
| 2 | | | | | | | | |
| … | | | | | | | | |
| **Tổng** | | | | | | | | |

## Kết quả cần chép vào evidence

- `cycle_time_seconds` = end − start, cộng thời gian dọn (từ preflight tới inventory sạch) để lập kế hoạch P9.
- `interactions`, `commands`, `automated_actions`, `wait_seconds`, `errors`.
- Cho batch: `billed_seconds` và `variable_compute_usd` từ `cost_calc.py` (đã tính, chưa đối soát, nên `PENDING` tới khi
  đọc Bills).
