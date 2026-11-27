# DRF-81 (P6-T4.3): bản audit nghiệm thu P6 (27/11/2026)

> **TL;DR** · Window `P6-L3-20261126-01`: batch suite **14/14 PASS** trên EKS. Tenant-a chạy Spot `m5.large`, tenant-b chạy On-Demand `c6i.large`, cả hai trên node do Karpenter tạo ·
> Trên EKS: **8/9** kịch bản §4 đạt, **1 một phần** (cleanup request còn `jobs=1` lúc đọc). Teardown `96 destroyed`, inventory và inventory trễ đều `CLEAN` ·
> Bills: P6 ≈ **0,77 USD** (trần 4). Codex review sau window qua 3 vòng, **APPROVE** ở `a6cc55a` ·
> **P6 chưa hoàn thành theo §8:** còn chờ teach-back §7 (8 câu) và cổng học `PRACTICED` + `EXPLAINED` của owner ·
> Mục lục: 1 Quy tắc §8 · 2 Run và phiên bản · 3 Kịch bản §4 · 4 Giới hạn · 5 Review độc lập ·
> 6 Inventory trễ và billing · 7 Học và teach-back · 8 Việc sau window

- SPEC: `.agent/specs/SPEC-P6_BATCH_TRAINING_JOB.md` §4, §5 P6-T4.3, §7, §8.
- Evidence gốc:
  - L3: `docs/evidence/p6/P6-T4.2_L3_WINDOW_20261126.md`.
  - L2: `P6-T2.2_KIND_LAB_20261125.md`, `P6-T4.1_BATCH_SUITE_20261126.md`.
  - L0/L1: `P6-T2.1_WORKER_20261125.md`, `P6-T3_TERRAFORM_20261125.md`.
  - Pin: `P6-T1_PINS_20261125.md`.
- Người viết: Claude (Opus 5.5). Bản này **không** phải review độc lập. Review của Codex nằm ở mục 5.
- Đã che: account ID, ARN, IP, endpoint, URL queue, tên bucket có account, tên node, instance ID.
- Mọi kết quả batch mang nhãn `CPU_SUBSTITUTE_FOR_GPU` (ADR-0009). Bản này không đưa ra kết luận nào về GPU hay về mức tiết kiệm.

## 1. Quy tắc hoàn thành P6 (SPEC §8)

| Điều kiện §8 | Trạng thái | Bằng chứng |
|---|---|---|
| Mọi kịch bản §4 có bằng chứng L3 trên EKS, với node do Karpenter tạo | **đạt với giới hạn**: 8/9 đạt, 1 một phần (mục 3) | window §4, §5, §8 |
| Hai tenant đều xong một run | đạt: tenant-a Spot attempt 1, tenant-b On-Demand | window §4 (B04 ×2) |
| Thu hồi thấy được trên Kubernetes **và** AWS | đạt: B05 ×2, node mất khỏi Kubernetes, instance `terminated` (đếm theo tag) | window §4, §6 |
| Teardown và inventory trễ sạch | **đạt**: `96 destroyed`; inventory `CLEAN` lúc 16:20Z; inventory trễ `CLEAN` lúc 27/11 04:27Z | window §8; mục 6 |
| Billing đã đọc | **đạt** 27/11: P6 ≈ 0,77 USD | mục 6 |
| Second-agent review ghi lại finding và giới hạn | **đạt**: trước window có 4 vòng, APPROVE ở `58c9982`. Sau window có 3 vòng (3 finding, đều đã sửa), APPROVE ở `a6cc55a` | mục 5 |
| Owner đạt `PRACTICED` + `EXPLAINED` cho SQS, KEDA, Karpenter, checkpointing | **chưa đạt** | mục 7 |
| Kết quả batch mang nhãn `CPU_SUBSTITUTE_FOR_GPU`, không có kết luận GPU | đạt | window §12 |

**Kết luận:** P6 **đạt về kỹ thuật** nhưng **chưa hoàn thành**. Còn thiếu teach-back §7 và cổng học của owner. Hai việc này chỉ owner làm được: Claude không trả lời thay, cũng không tự nâng trạng thái học.

## 2. Run, revision và phiên bản

| Mục | Giá trị |
|---|---|
| Window | `P6-L3-20261126-01`, 12:30Z–16:20Z ngày 26/11. Stack sống từ khoảng 13:46Z đến 16:19Z |
| Revision lúc plan | `main` `7bfbb2c`. Plan lại ở `407b751` (sau #105, không đổi `.tf`), cùng shape hash |
| Terraform plan | `96 to add`; shape sha256 `265b5721c1249de239c439e234770af9ae1f4218ccbd5fee617ab37cfb56aeb7` |
| Revision cuối window | `main` `c82640a` (sau #99–#104, các PR request soạn sẵn). `gitops/` khớp `7bfbb2c` |
| Revision hiện tại | `main` `e59648e` (thêm #106 P1g, #107 evidence/runbook/retry gate, #108 thứ tự access entry). #108 đổi `.tf`. Codex vòng 1 đọc là shape hash không đổi, nhưng chưa có plan thật nào chứng minh, nên window sau phải plan lại và đọc lại hash |
| Kubernetes | EKS 1.35, 2 × `m6i.large` system |
| KEDA | chart và app 2.21.1; chart sha256 `76b45621…8fb883e`; image `keda` `sha256:d09d92c0…1e6488`, `keda-metrics-apiserver` `sha256:747e376b…6e1c84`, `keda-admission-webhooks` `sha256:5f4b0b0f…4fcd3` |
| Karpenter | chart và app 1.15.3; chart OCI `sha256:7fadb557…fe56ed`; controller `sha256:37ae6d13…7b4814` |
| kro / Kyverno / Argo CD | 0.9.4 / chart 3.10.0 (3 policy `Deny`) / v3.5.7 |
| Image batch | `ghcr.io/…/batch-training@sha256:d2bb517d884710dd269285773b6fd5de74b631a4faafdb2fd2a3c0020cbb470e` |
| Image L2 (chỉ kind) | ElasticMQ 1.7.1 `sha256:e4580ab9…24e05c`, S3Mock 5.2.3 `sha256:ab01a694…8fca92` |

Digest đầy đủ: `P6-T1_PINS_20261125.md` và VERSION_MATRIX "P6 pins".

**Capacity và instance type của từng run** (đọc từ nhãn của Node chạy Pod, B04):

| Run | Tenant | Pool | Capacity | Instance type | Kết quả |
|---|---|---|---|---|---|
| attempt 1 | tenant-a | `batch-spot` | `spot` | `m5.large` | `SUCCEEDED`, 11 checkpoint, 1 artifact |
| attempt 2 (B06, B07) | tenant-a | `batch-spot` | Spot. B07 tạo node thay thế | không ghi riêng | resume từ step 39, rồi từ step 102; 1 artifact (K3) |
| attempt 3 `fail-always` (B08) | tenant-a | `batch-spot` | không ghi riêng | không ghi riêng | `RECEIVED-1,2,3`, vào DLQ, không có `SUCCEEDED` |
| attempt 1 | tenant-b | `batch-ondemand` (Spot limit 0) | `on-demand` | `c6i.large` | `SUCCEEDED`, 11 checkpoint |

Suite chỉ đọc capacity và instance type ở B04. Với attempt 2 và 3, bản này không khẳng định capacity (biên âm 7: không có nhãn đã đọc thì không có claim capacity).

## 3. Kịch bản §4 → bằng chứng

| Kịch bản §4 | L2 (kind, 25–26/11) | L3 (EKS, 26/11) | Trạng thái |
|---|---|---|---|
| Capacity bị giới hạn trước khi launch | `check.sh` rule 19–23; NodePool tĩnh | cổng: quota Standard 8/8 vCPU; B3–B5: 2 NodePool mỗi pool 2 CPU, D1 allowlist, `expireAfter`; K1: taint batch và 4 tag dự án trên instance | đạt |
| Sự kiện tạo Job | KEDA + ElasticMQ trên kind | B01 (sau run đầu, queue rỗng qua 4 lần poll, 0 Job, 0 NodeClaim, 0 instance); B02 `jobs=1`; B03 vẫn 1 Job sau 3 lần poll | đạt. Lỗi 8: có 1 Job thừa **sau** khi run xong, Job đó không nhận message, không tạo node |
| Một request cho kết quả quan sát được | RGD trên kind | K5: `ACTIVE` chỉ sau khi gửi message; B04 ×2; K2 `device=cpu`, có attempt, có node | đạt |
| Node được thu hồi | — (kind không có Karpenter) | B05 ×2: node mất khỏi Kubernetes, instance `terminated` trên AWS | đạt, có giới hạn: khoảng Job xong → `terminated` **chưa đo trực tiếp** (window lỗi 10). Volume mất chỉ thấy qua inventory sau teardown |
| Run bị ngắt thì resume | resume trên kind (S3Mock) | B06 (xoá Pod) resume từ step 39; B07 (xoá NodeClaim) resume từ step 102; K3: đúng 1 artifact | đạt. B07 là simulated disruption (D11) |
| Lỗi thấy được và có giới hạn | DLQ trên kind | B08: `RECEIVED-1,2,3`, message trong DLQ (khớp tenant, request, attempt); K4 15:34Z `nodeclaims: 0` | đạt |
| Capacity và vị trí đặt Pod bị giới hạn | — | B09: message thừa (`b09-extra`), vẫn 1 Job, 1 NodeClaim; B10: Pod không toleration `Pending`; B11: ba lần từ chối nêu đúng `pods`, `count/jobs.batch`, `requests.cpu` | đạt. B11 cũng đóng giới hạn số object mà P5 audit §3.1 chuyển sang |
| Danh tính bị giới hạn | — | B12: cả hai probe `caller_role_match=true`; tenant-a đọc được; tenant-b get/put đều `AccessDenied`. B13: mô phỏng 92/92; KEDA `SendMessage` và Karpenter `CreateRole` đều `AccessDenied`. B14: `imds=denied` | đạt |
| Xoá request và teardown đầy đủ | thứ tự teardown kind | K6: `bucket=gone`, ScaledJob 0, queue rỗng, nhưng **còn `jobs=1` mỗi tenant** lúc đọc. DLQ còn 1 message B08 đến khi destroy. F2: 0 NodeClaim, 0 instance Karpenter. `96 destroyed`, inventory `CLEAN` ×2 | **một phần** ở bước xoá request: kịch bản đòi Jobs bằng 0, đọc ra 1 (không có Pod batch). Bước teardown thì đạt |

### 3.1. Đề xuất cho kịch bản "một phần"

Claude **đề xuất**, chưa quyết: chấp nhận đây là giới hạn và không mở window mới.

- Lúc đọc, không có Pod batch nào, và F2 đếm 0 NodeClaim, 0 instance. Vì vậy Job còn lại không giữ node.
- Chưa xác định đó là Job nào. Có thể là Job lịch sử (`successfulJobsHistoryLimit: 1`), hoặc submit Job của kro chưa bị garbage collection kịp. Evidence không ghi tên hay trạng thái của Job đó.
- Destroy xoá cả cluster, và inventory trễ sạch, nên không còn tài nguyên AWS hay chi phí nào.
- Khoảng trống còn lại là bằng chứng `jobs=0` ngay sau cleanup, trước destroy. Có thể bổ sung ở window P6 sau (nếu có), hoặc ở lab kind: đọc lại sau khi kro xoá ScaledJob.
- Cần owner quyết: chấp nhận là giới hạn, hay giữ "một phần" và kiểm lại ở window sau.

## 4. Giới hạn

1. **CPU thay cho GPU** (ADR-0009). Không có kết luận GPU, không ngoại suy từ CPU sang GPU.
2. **Disruption là giả lập** (D11). B07 xoá NodeClaim, không phải Spot interruption thật, vì không dùng AWS FIS (biên âm 5).
3. **Cô lập mềm trên queue chung** (D3). Worker của cả hai tenant đều nhận được message. Message của tenant khác bị trả lại, không bị xoá. Tenant sai vẫn không ghi được vào bucket của tenant kia (B12).
4. **Giờ smoke chỉ từ một lần chạy**, không phải số đo hiệu năng. Khoảng Job xong → `terminated` chỉ có ước lượng theo poll, khoảng 3 phút.
5. **Lỗi 8 chưa giải thích chắc chắn.** KEDA tạo thêm 1 Job sau khi run xong. Có thể vì số message của SQS là gần đúng.
6. **Retry gate S2** (`retry_plan_check.sh`) mới được chứng minh trên plan giả (23 ca), chưa chạy trên plan thật.
7. **Một window, một lượt PASS.** Hai lượt suite đầu hỏng vì lỗi vận hành của Claude (window lỗi 4a, 4b). Trong window có một lần sửa script kiểm IAM (#105), không đổi policy hay `.tf`.
8. **Owner chưa tự chạy lab kind.** Micro-lab EKS không có dự đoán và thiếu M3, M5 (mục 7).
9. **Service-linked role Spot được giữ lại có chủ đích** (A11), không phải sót sau teardown.

## 5. Review độc lập (Codex)

| Lượt | Phạm vi | Kết quả | Hồ sơ |
|---|---|---|---|
| Trước window (25–26/11) | PR #93 (Terraform IAM, Karpenter), #94 (RGD, NodePool, `check.sh` 19–23), #96 (suite, window helper) | rounds 1–3 REQUEST CHANGES, mọi finding đã sửa; round 4 **APPROVE** ở `58c9982` | `P6_CODEX_REVIEW_REQUEST_20261125.md` |
| Sau window (27/11) | #105 (đọc trên `407b751`), #108, #107 | vòng 1: #105, #108 đạt; #107 REQUEST CHANGES, 2 finding (HIGH H8, MEDIUM mốc B05/B09). Vòng 2: B05/B09 đóng; thêm 1 MEDIUM (retry gate cho qua khi thêm phần tử mảng hay tag). Vòng 3: **APPROVE** ở `a6cc55a` | `P6_CODEX_REVIEW_REQUEST_20261127.md` (nguyên văn cả 3 vòng) |

- **Ngoài phạm vi Codex:**
  - Worker T2.1 (65 unit test, smoke trên S3Mock).
  - Các PR request #99–#104 và #106: mỗi PR chỉ đổi một dòng, hoặc giống từng byte với `8692146`.
  - Bản audit này **chưa được Codex xem**.
- Mọi kết luận của Codex dựa trên code, fixture và log đã lưu. Codex không chạy AWS, kind hay apply.

## 6. Inventory trễ và billing

**Đạt (27/11).**

**Inventory trễ.** Owner làm mới MFA. Claude chạy `infra/terraform/scripts/inventory.sh` (profile `zdr-tf`, chỉ đọc) lúc 2026-11-27T04:27Z, khoảng 12 giờ sau destroy.
- Mọi bộ đếm bằng 0, trừ `s3_buckets=1` (bucket state, nằm trong allowlist).
- Tagging API còn 5 bản ghi `ec2:fleet`. Đây là fleet loại instant mà Karpenter tạo khi dựng node: chỉ là bản ghi, không có instance, không tính tiền.
- Kết quả: `RESULT: CLEAN`.

**Bills tháng 11** (owner đọc trên console ngày 27/11, cả tài khoản):

| Dịch vụ | Credits 27/11 | Trước window (26/11) | Phần của P6 |
|---|---|---|---|
| EC2 | 1,26 | 0,80 | 0,46 |
| EKS | 0,82 | 0,59 | 0,23 |
| RDS | 0,21 | 0,16 | 0,05 |
| VPC | 0,07 | 0,05 | 0,02 |
| Data Transfer | 0,02 | 0,01 | 0,01 |
| Secrets Manager, S3 | 0,01 | 0,01 | 0,00 |
| **Tổng** | **2,39** | **1,62** | **≈ 0,77** |

- Charges by service sau credits là 0,00 USD: credits bù đủ, net 0.
- P6 ≈ 0,77 USD, dưới trần D14 4 USD. Ước tính trước window là 2,5–2,6 USD vì tính trọn 5 giờ; stack thật chỉ sống khoảng 2,5 giờ.
- **Kiểm chéo:**
  - EKS 0,23 USD ứng với khoảng 2,3 giờ control plane.
  - EC2 0,46 USD gần bằng 2 × `m6i.large` trong khoảng 2,4 giờ.
- **Giới hạn:**
  - Số liệu là số owner đọc trên console, không có CUR.
  - Phần của P6 tính bằng phép trừ hai lần đọc, không theo tag.
  - Node batch chỉ sống vài phút mỗi lần nên không tách được khỏi EC2.
  - Hoá đơn tháng còn ở trạng thái ước tính.

## 7. Học và teach-back §7

**Chưa đạt.** `.agent/learning/CURRENT_STATUS.md` vẫn ghi P6 batch là `NOT_STARTED` (25/11). Theo SPEC §5 T4.3, trạng thái học chỉ được nâng khi owner tự làm lại được.

| Chủ đề §8 | Owner đã tự làm | Còn thiếu |
|---|---|---|
| SQS semantics | chưa có | lab kind hoặc teach-back câu 1, 2 |
| KEDA | chưa có | lab kind hoặc teach-back câu 1, 3, 5 |
| Karpenter | micro-lab EKS M1, M2, M4: quan sát NodeClaim sinh ra, nhãn capacity và instance type, Pod đặt đúng node (window §7). Không có dự đoán trước | M3 (taint), M5 (consolidation); teach-back câu 3, 4, 5, 8 |
| Checkpointing | chưa có | teach-back câu 4 |

- **Đề xuất của Claude:** trạng thái học chỉ owner nâng, Claude không tự sửa.
  - Karpenter: lên `PRACTICED` nếu owner xác nhận micro-lab là do mình tự gõ, không có dự đoán.
  - Cả bốn chủ đề: lên `EXPLAINED` chỉ khi teach-back đạt.
- **Teach-back §7** gồm 8 câu, owner trả lời bằng lời của mình. Claude ghi nguyên văn vào `docs/evidence/p6/P6-T4.3_TEACHBACK_<date>.md` và đối chiếu từng ý với bằng chứng, giống P5. Câu 4 và câu 5 cũng thay cho phần còn thiếu của M3 và M5 (window lỗi 7).

## 8. Việc sau window (đã xong)

| PR | Phát hiện | Thay đổi |
|---|---|---|
| [PR #105](https://github.com/EurusDevSec/Zero-D-Rift/pull/105) | window lỗi 1 | `batch_iam_check.sh` đọc policy bằng `jq -r`; dòng ma trận `ListInstanceProfiles` mô phỏng trên `*`. Merge trong window |
| [PR #106](https://github.com/EurusDevSec/Zero-D-Rift/pull/106) | P1g | bật lại hai request RAG, giống từng byte với `8692146` |
| [PR #107](https://github.com/EurusDevSec/Zero-D-Rift/pull/107) | lỗi 2, 3, 4a, 4b, 5, 6, 10 | evidence T4.2; runbook §4, B1, C2, K3, F4, H8; `retry_plan_check.sh` cùng 23 test trong `check.sh` 3e; nhãn B05/B09 của suite |
| [PR #108](https://github.com/EurusDevSec/Zero-D-Rift/pull/108) | lỗi 3 | access entry Karpenter lấy tên cluster từ output `module.cluster`, nên phải chờ cluster |

**Còn lại cho P6:** teach-back §7, cổng học, owner quyết mục 3.1, rồi chuyển DRF-81 sang Done.
