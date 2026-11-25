# DRF-72 (P5-T4.3): bản audit nghiệm thu P5 (bản nháp 25/11/2026)

> **TL;DR** · Window `P5-L3-20261125-01`, suite **82/82** ở `ded7014`; 6/9 kịch bản §4 đạt trên EKS, 2 một phần, 1 lệch SPEC hiện tại ·
> Đã xong: suite, Kyverno sập, micro-lab, teardown `CLEAN`, 3 PR sửa sau window (#85, #86, #87), Codex review (REQUEST CHANGES → 5 finding sửa → **APPROVE**) ·
> **Chưa xong (P5 chưa hoàn thành theo §8):** inventory trễ và Bills gross (26/11), teach-back §7, owner quyết kịch bản admission ·
> Mục lục: 1 Quy tắc §8 · 2 Run và phiên bản · 3 Kịch bản §4 · 4 Cô lập mềm và giới hạn · 5 Review độc lập ·
> 6 Inventory trễ và billing · 7 Teach-back · 8 Việc sau window

- SPEC: `.agent/specs/SPEC-P5_TENANT_GUARDRAILS.md` §4, §5 P5-T4.3, §7, §8.
- Evidence gốc: `docs/evidence/p5/P5-T4.2_L3_WINDOW_20261125.md` (L3), `P5-T2.1_L2_KIND_BASELINE_20261124.md`,
  `P5-T2.2_L2_KIND_KYVERNO_20261124.md` (L2), `P5-T1_PINS_20261122.md` (pin).
- Người viết: Claude (Opus 5.5). Bản này **không** phải review độc lập; mục 5 là chỗ ghi review của Codex.
- Đã che: account ID, ARN, IP, endpoint, tên node, tên secret.

## 1. Quy tắc hoàn thành P5 (SPEC §8)

| Điều kiện §8 | Trạng thái | Bằng chứng |
|---|---|---|
| Mọi kịch bản §4 có bằng chứng L3 trên EKS | **chưa trọn**: 2 kịch bản một phần, 1 kịch bản lệch SPEC hiện tại (mục 3) | window §11 |
| Hai sandbox RAG PASS với mọi guardrail ở `Enforce` | đạt | window §4 C4: tạo lại dưới `Deny`, Ready, `probe sandbox` ×2 PASS |
| Suite PASS từ checkout sạch ở revision đã ghi | đạt một phần | lượt 2 PASS trên `main` `ded7014`. `acceptance.json` không ghi revision hay trạng thái `git status`; revision lấy từ dòng thời gian của window |
| Teardown và inventory trễ sạch | teardown đạt; **inventory trễ chờ 26/11** | window §8; mục 6 |
| Billing đã đọc | **chờ owner 26/11** | mục 6 |
| Review độc lập ghi finding và giới hạn | Codex REQUEST CHANGES 25/11; kiểm lại 4/5 đóng; kiểm lần ba **APPROVE**, cả 5 finding đóng | mục 5 |
| Owner đạt `PRACTICED` + `EXPLAINED` cho RBAC, Pod Security, NetworkPolicy, quota, Kyverno | **chưa**: `PRACTICED` trên kind (24/11) và micro-lab EKS (25/11); `EXPLAINED` chưa có | mục 7 |
| Văn bản nghiệm thu nói rõ cô lập mềm và giới hạn | đạt | mục 4 |

## 2. Run, revision và phiên bản

| Mục | Giá trị |
|---|---|
| Window | `P5-L3-20261125-01`, 03:51Z–06:52Z ngày 25/11, 2 × `m6i.large` |
| Revision suite PASS | `main` `ded7014` (sau #76 Deny, #79, #80, #81, #82, #83) |
| Revision hiện tại | `main` `010c49b` (thêm #84 evidence, #85, #86, #87; không đổi guardrail hay RGD) |
| Kubernetes | EKS 1.35, kubectl client 1.35 |
| VPC CNI | `v1.22.4-eksbuild.10`, `enableNetworkPolicy: true`, mode `standard`; node agent `aws-network-policy-agent:v1.4.0-eksbuild.1` |
| Kyverno | `v1.20.0`, chart `3.10.0`; digest 6 image ở `P5-T1_PINS_20261122.md`; policy `ValidatingPolicy` `policies.kyverno.io/v1`, 3 policy ở `Deny` |
| Argo CD | v3.5.7 |
| Crossplane / kro | chart `2.4.3` / `0.9.4` |
| Image app | `ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox@sha256:850c77c200a798b5706ce56c7878164d4887fcf3661bbec91b2d8564df735263` |
| Terraform plan | 65 to add; shape sha256 `56963920…7d17f9` khớp P4 |

## 3. Kịch bản §4 → bằng chứng

| Kịch bản §4 | L2 (kind, 24/11) | L3 (EKS, 25/11) | Trạng thái |
|---|---|---|---|
| Request path chỉ nhận golden path | AppProject trên kind | `T03-foreign-namespace`, `T03-foreign-kind` `deny:argocd`; micro-lab AppProject; tầng CI `check.sh` + 77 guard case | đạt |
| Tenant không đọc được tenant kia | RBAC trên kind | 17 case `T04` (15 deny, 2 allow trong namespace mình); micro-lab `no`/`yes` | đạt |
| Workload nguy hiểm bị chặn | Pod Security, 3 policy Kyverno | `T05` ×4 `deny:pod-security`; `T14` ×2, `T10-label-spoof` nêu tên policy | **một phần** trên EKS: `zdr-require-resources` chỉ có bằng chứng L2 (LimitRange điền mặc định trước) |
| Tài nguyên bị giới hạn | quota, LimitRange | `T11-gpu` (quota GPU), `T11-big` (maximum LimitRange), `T11-defaults` (mặc định LimitRange) | **một phần** trên EKS: chưa có ca quota số Pod hay số object (`count/`) |
| Mạng mặc định chặn | — (kind không có VPC CNI) | control 4 đường `allow` → enforced a→b, b→a, metadata `deny`; own-app `allow`; DNS, DB, AWS API của sandbox PASS | đạt |
| Cô lập phía AWS vẫn giữ | — | probe P4 cross ×2, `T07-other-sa` `AccessDenied` | đạt |
| Guardrail không làm gãy golden path | — | C4 tạo lại hai sandbox dưới `Deny` | đạt, **sau** PR #80 sửa RGD trong window |
| Hiểu khi admission hỏng | F1–F6 trên kind | D2: scale về 0 → webhook bị gỡ, fail open; Service hỏng + 150 giây → fail closed ở tenant, `kube-system` không ảnh hưởng; cluster vẫn dọn được | **lệch SPEC hiện tại**: §4 nói "scaled to zero … matches the configured failurePolicy", nhưng scale về 0 cho 0 webhook và Pod sai được nhận; chỉ sự cố "không gọi được" mới fail closed. Giữ cả hai kết quả; đề xuất tách kịch bản ở SPEC §10 **owner chưa quyết** |
| Teardown đầy đủ | thứ tự teardown kind (F3) | `65 destroyed`, inventory `CLEAN` | đạt **có điều kiện dừng G2**: 8 webhook Kyverno sống sót sau khi xoá app, Claude xoá theo nhãn trước destroy. Runbook E2 đã có bước này (PR #87) |

## 4. Cô lập mềm và giới hạn

**Câu nghiệm thu:** P5 cho **cô lập mềm** giữa hai tenant trên một cluster EKS dùng chung. Đây là cô lập
theo chính sách (RBAC, Pod Security, quota, AppProject, Kyverno, NetworkPolicy, IAM theo IRSA), không phải
cô lập cứng: hai tenant vẫn chung node, kernel, control plane, CoreDNS, database instance và tài khoản AWS.

Giới hạn đã biết:

1. **Chung node và kernel.** Một lỗ hổng thoát container hay một Pod ngốn CPU (không có CPU limit, D3) ảnh hưởng tenant kia. Quota chặn tổng, không chặn tranh chấp tức thời.
2. **Admission có đường vòng cho admin.** Scale Kyverno về 0 thì webhook bị gỡ và admission mở (D2 3a). Tenant không có quyền này (D1), nhưng đây là bypass T15 cho platform admin.
3. **Fail closed có độ trễ.** Trên EKS, Service Kyverno hỏng chỉ làm fail closed sau một khoảng không có request (F6); cách giải thích là giả thuyết.
4. **Standard mode của NetworkPolicy.** Pod mới được mở cho tới khi policy được lập trình (start-up gap); suite chờ trước khi thử deny.
5. **Egress 443 ra ngoài VPC vẫn mở** cho AWS API; chặn gọi sai API là việc của IAM, không phải mạng.
6. **T01 (branch protection) vẫn mở** theo D12; request path dựa vào review PR và CI, chưa có ruleset bắt buộc.
7. **Một window, một lượt PASS trọn vẹn**, và ba lần sửa code trong window (A16): #79, #80 (sản phẩm), #83.
8. Chưa kiểm riêng trên EKS: `zdr-require-resources`, giới hạn số object.
9. Kyverno không phải control cho thay đổi phía AWS (negative boundary SPEC §1).

## 5. Review độc lập (Codex)

Lần review code P5 trước của Codex là APPROVE ở `ae20196` (SPEC §5 P5-T4.1). Lần này phạm vi là
`ae20196..010c49b` (PR #74–#87). Prompt hỏi theo thứ tự: PASS oan, hành vi guardrail (nhất là selector
Service ở PR #80), rồi câu nào trong evidence nói quá output đã ghi.

### 5.1. Kết quả (25/11)

Owner chạy Codex rồi dán kết quả vào chat ngày 25/11/2026. Claude ghi nguyên văn, chỉ đổi link file tuyệt đối
trên máy owner thành đường dẫn trong repo.

> ## Review độc lập P5-T4.3 — REQUEST CHANGES
>
> **Reviewer:** Codex · **Revision:** `010c49b71cdaf18808ae7005dba842c2475bced4` · **Phạm vi:** `ae20196..010c49b`
>
> | ID | Mức | File:dòng | Vấn đề và tình huống cụ thể | Sửa tối thiểu |
> |---|---|---|---|---|
> | 1 | MEDIUM | `infra/terraform/scripts/smoke.sh:30` | Giá trị sai trong `run.tfvars` có thể bị coi là chưa khai báo. Kiểm cục bộ với `system_node_desired_size = -1` cho kết quả mong đợi `desired=1 max=2`, nên cụm đang khớp mặc định vẫn có thể qua smoke. | Chỉ dùng mặc định khi biến vắng mặt. Nếu biến có mặt nhưng giá trị sai hoặc không đọc được, exit 1. |
> | 2 | LOW | `docs/runbooks/P5_L3_WINDOW.md:140` | Lệnh kiểm webhook có thể in `0` khi `kubectl get` lỗi. Stub trả `Forbidden` vẫn cho `grep` in `0`, đúng con số runbook yêu cầu trước khi tiếp tục teardown. | Kiểm `kubectl get` thành công rồi mới đếm. Dừng bước E2 nếu không đọc được. |
> | 3 | MEDIUM | `docs/evidence/p5/P5-T4.2_L3_WINDOW_20261125.md:213` | Hai dòng đánh dấu cả kịch bản **đạt** dù còn thiếu ca EKS. `zdr-require-resources` chỉ có bằng chứng kind. `T11-gpu` kiểm quota GPU, `T11-big` kiểm LimitRange, và cả hai đều không kiểm quota số object. | Ghi hai kịch bản là **một phần** và nêu rõ ca nào đã có bằng chứng EKS. |
> | 4 | MEDIUM | `docs/evidence/p5/P5-T4.2_L3_WINDOW_20261125.md:218` | §4 hiện yêu cầu hành vi khi scale admission về 0 khớp `failurePolicy: Fail`. Log 3a ghi 0 webhook và Pod sai được nhận. Lượt 3b chứng minh fail closed khi webhook còn được đăng ký nhưng không gọi được. | Đánh dấu kịch bản là **lệch SPEC hiện tại**, giữ cả hai kết quả và chờ owner quyết định đề xuất tách kịch bản ở §10. |
> | 5 | LOW | `docs/runbooks/P5_L2_KIND_KYVERNO.md:41` · `docs/runbooks/P5_L3_WINDOW.md:105` | Checkout `010c49b` áp ngay policy `Deny`. Làm theo bước 0–1 của lab kind thì Pod `tagimg` bị chặn ngay ở bước Audit. Runbook L3 cũng giả định bước dựng bắt đầu ở `Audit`. | Chỉ rõ revision Audit cho bước dựng L3 và cho bước Audit của lab kind khi chạy lại. |
>
> **Đã kiểm:** PR #83 bỏ CR nhưng vẫn giữ mã lỗi khi Python thất bại. Kiểm tra GitOps cục bộ qua. CI đúng SHA ghi baseline fixture qua, **77/77 guard** qua, Kyverno **14/14** qua và self-test lật kỳ vọng exit `1`. [Static gates](https://github.com/EurusDevSec/Zero-D-Rift/actions/runs/45567238537)
>
> **PR #80:** Selector thêm nhãn tenant cho Service hiện có. Kubernetes chỉ chọn backend trong namespace của Service. JSON gốc xác nhận đường nội bộ mở và cả hai chiều liên tenant bị chặn ở lượt enforced. `gitops/platform/rgd/rag-sandbox.yaml:245` · [Kubernetes EndpointSlice controller](https://github.com/kubernetes/kubernetes/blob/v1.35.0/pkg/controller/endpointslice/endpointslice_controller.go#L370-L372) · [AWS VPC CNI controller](https://github.com/aws/amazon-network-policy-controller-k8s#networkpolicy-podselector-must-match-the-target-services-selector)
>
> **Giới hạn:** Kiểm code, CI và log lưu sẵn. Đếm lại control **7/7**, enforced lượt đầu **73/82**, lượt hai **82/82** với 82 case riêng biệt và 0 skip. Log destroy ghi **65 destroyed**. Micro-lab được đối chiếu với output lưu trong evidence. Inventory trễ và Bills gross chưa xác minh, **1,36 USD** vẫn là ước tính. Không chạy EKS/AWS và không sửa file.

### 5.2. Xử lý từng finding

| ID | Xử lý | Kiểm |
|---|---|---|
| 1 | `smoke.sh`: biến có mặt trong `run.tfvars` mà không phải số nguyên trần thì thành `invalid`, nên guard exit 1. Chỉ khi biến vắng mặt mới lấy mặc định từ `variables.tf` | Offline, 11 trường hợp: không có file, 2/2, CRLF, comment cuối dòng, dòng bị comment, chỉ có biến khác → đúng số; `-1`, `"2"`, `two`, desired 2 max 1, desired 3 → `FAIL`, rc 1 |
| 2 | Runbook L3 E2 và kind §4: chỉ đếm webhook khi `kubectl get` thành công; nếu lỗi thì in `LỖI …` và dừng | Stub: đọc được → `webhook kyverno: 1`; `Forbidden` → `LỖI`, không in số |
| 3 | Window §11 và audit mục 3: hai kịch bản thành **một phần**, ghi rõ ca nào có trên EKS | Đọc lại |
| 4 | Window §11 và audit mục 3: kịch bản admission thành **lệch SPEC hiện tại**, giữ cả 3a và 3b, chờ owner quyết SPEC §10 | Đọc lại |
| 5 | Runbook kind §0 lấy policy từ `5b56624` (bản Audit cuối trên `main`, chỉ khác `validationActions`) bằng `git archive`. Runbook L3 B: chạy lại thì merge một PR revert PR #76 trước khi dựng | `git archive 5b56624` ra ba dòng `validationActions: [Audit]` |

PR #80 không bị đòi sửa, nên bản RGD đã chạy trên EKS là bản nghiệm thu và không cần window xác nhận.
### 5.3. Codex kiểm lại (25/11)

Owner chạy Codex trên bản sửa chưa commit, rồi dán kết quả vào chat ngày 25/11/2026. Claude ghi nguyên văn;
chỉ đổi link file tuyệt đối thành đường dẫn trong repo.

> **REQUEST CHANGES — còn 1/5 finding chưa đóng.** Re-check bản sửa chưa commit trên `010c49b71cdaf18808ae7005dba842c2475bced4`.
>
> | # | Trạng thái | Kết quả |
> |---|---|---|
> | 1 | **Chưa đóng · MEDIUM** | Cả 11 ca đã nêu cho kết quả đúng. Khi giả lập `grep` không đọc được `run.tfvars` và trả `2`, `\|\| true` nuốt lỗi và bộ kiểm vẫn chấp nhận mặc định `1/2`. Cụm khớp mặc định vẫn có thể PASS oan. Sửa tối thiểu: chỉ dùng mặc định khi `grep` trả `1` vì không có dòng khớp. Lỗi đọc phải dừng smoke. `infra/terraform/scripts/smoke.sh:30` |
> | 2 | **Đã đóng** | Hai lệnh đã được thử với stub. `Forbidden` in `LỖI`. Kết quả đọc thành công phân biệt đúng còn webhook và danh sách rỗng. |
> | 3 | **Đã đóng** | Evidence và audit ghi **một phần** cho cả hai kịch bản và chỉ rõ các ca EKS còn thiếu. |
> | 4 | **Đã đóng** | Evidence và audit ghi **lệch SPEC hiện tại**, giữ cả 3a và 3b, chờ owner quyết định. |
> | 5 | **Đã đóng** | `git archive 5b56624` cho đúng ba policy `[Audit]`. Runbook L3 yêu cầu đưa policy về Audit trước khi dựng lại. |
>
> Audit §5.1 khớp nguyên văn review trước sau khi chuẩn hóa các link file cục bộ. Không thấy PASS oan nào khác trong phạm vi re-check.
>
> **Giới hạn:** Chỉ đọc và kiểm offline. Không chạy EKS/AWS, sửa file hay commit.

**Xử lý finding 1:** `size()` bỏ `|| true`. Mã thoát của `grep` quyết định:
- `0`: có dòng, nên lấy dòng cuối.
- `1`: không có dòng, nên lấy mặc định.
- `2` trở lên: in `unreadable`, nên guard exit 1.

Điều kiện `-f` đổi thành `-e`, để một `run.tfvars` không phải file thường không bị coi là vắng mặt.

Kiểm offline có 13 trường hợp: 11 trường hợp cũ, kết quả không đổi, cộng 2 trường hợp mới. `run.tfvars` là thư mục, và stub `grep` trả `2`. Cả hai mới ra `FAIL … desired=unreadable max=unreadable`, rc 1.

### 5.4. Codex xác nhận finding 1 (25/11)

Owner chạy Codex trên bản sửa chưa commit, rồi dán kết quả vào chat ngày 25/11/2026. Claude ghi nguyên văn;
chỉ đổi link file tuyệt đối thành đường dẫn trong repo.

> **APPROVE — finding 1 đã đóng.** Cả 5 finding của review P5-T4.3 đã được xử lý trên bản sửa chưa commit dựa trên `010c49b`.
>
> Mình chạy lại **13 ca offline**. Khi `run.tfvars` là thư mục hoặc `grep` trả `2` dù đã in dữ liệu một phần, smoke báo `unreadable` và thoát `1`. Các ca giá trị sai vẫn bị từ chối. Không phát hiện PASS oan mới trong phạm vi kiểm. `infra/terraform/scripts/smoke.sh:28`
>
> Audit §5.3 khớp nguyên văn lần re-check trước sau khi chuẩn hóa link file. Audit §5.3
>
> **Giới hạn:** Kết luận chỉ áp dụng cho bản sửa review. Kiểm offline, không chạy EKS/AWS, sửa file hay commit.

APPROVE này áp dụng cho bản sửa chưa commit. Commit gộp các file đó (PR DRF-72) mà không đổi nội dung đã kiểm; mục 5.4 được thêm sau APPROVE.

## 6. Inventory trễ và billing

**Chờ 26/11.**
- Owner chạy `infra/terraform/scripts/inventory.sh` (MFA, profile `zdr-tf`) và dán output. Tại window, chỉ mục tag còn liệt kê 1 SG, 1 SG rule, 1 VPC endpoint trong khi API đếm 0. P4 lệch y hệt và đã hết sau một ngày.
- Owner đọc Bills gross tháng 11, đối chiếu mốc 0,73 USD trước window. Ước tính của window ≈ 1,36 USD, trần P5 4 USD.

## 7. Teach-back §7

**Chưa bắt đầu.** Owner trả lời 7 câu hỏi SPEC §7 bằng lời của mình; Claude chỉ ghi lại, không viết hộ.
Trạng thái học hiện tại (`.agent/learning/CURRENT_STATUS.md`): `PRACTICED` trên kind 24/11, chưa `EXPLAINED`.
Micro-lab EKS 25/11 do owner gõ nhưng không có dự đoán trước, nên chỉ cho thấy owner tự gõ và đọc được output.

## 8. Việc sau window (đã xong)

| PR | Phát hiện | Thay đổi |
|---|---|---|
| [PR #85](https://github.com/EurusDevSec/Zero-D-Rift/pull/85) | F3 | `check_guards.sh` sửa trên fixture riêng; kiểm baseline trước các case. Trên `main` `010c49b`: 77/77 PASS |
| [PR #86](https://github.com/EurusDevSec/Zero-D-Rift/pull/86) | F8 | `smoke.sh` đọc số node từ `run.tfvars` (mặc định từ `variables.tf`); số sai thì dừng. Chỉ thử offline |
| [PR #87](https://github.com/EurusDevSec/Zero-D-Rift/pull/87) | F4, F6, F7, F9 | runbook: quy tắc MFA, chờ 150 giây ở 3b, xoá webhook Kyverno theo nhãn, tên container node agent |
