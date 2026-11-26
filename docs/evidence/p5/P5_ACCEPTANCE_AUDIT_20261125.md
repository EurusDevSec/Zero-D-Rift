# DRF-72 (P5-T4.3): bản audit nghiệm thu P5 (25/11/2026, chốt 26/11)

> **TL;DR** · Window `P5-L3-20261125-01`, suite **82/82** ở `ded7014`; 8/10 kịch bản §4 đạt trên EKS, 2 một phần (chấp nhận là giới hạn) ·
> Đã xong: suite, Kyverno sập, micro-lab, teardown `CLEAN`, 3 PR sửa sau window (#85, #86, #87), Codex review (REQUEST CHANGES → 5 finding sửa → **APPROVE**) ·
> **P5 hoàn thành theo §8 (26/11):** inventory trễ `CLEAN`, Bills gross tháng 11 1,62 USD cả tài khoản (P5 ≈ 0,89, trần 4) · Teach-back §7: **đạt** (25/11) · Kịch bản admission: đã tách (25/11) ·
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
| Mọi kịch bản §4 có bằng chứng L3 trên EKS | đạt với giới hạn: 8/10 đạt; 2 một phần được chấp nhận là giới hạn (mục 3.1) | window §11 |
| Hai sandbox RAG PASS với mọi guardrail ở `Enforce` | đạt | window §4 C4: tạo lại dưới `Deny`, Ready, `probe sandbox` ×2 PASS |
| Suite PASS từ checkout sạch ở revision đã ghi | đạt một phần | lượt 2 PASS trên `main` `ded7014`. `acceptance.json` không ghi revision hay trạng thái `git status`; revision lấy từ dòng thời gian của window |
| Teardown và inventory trễ sạch | **đạt**: teardown 25/11; inventory trễ 26/11 `CLEAN`, chỉ mục tag chỉ còn bucket state | window §8; mục 6 |
| Billing đã đọc | **đạt** 26/11: gross tháng 11 1,62 USD cả tài khoản, credits 1,62, net 0; P5 ≈ 0,89 USD, dưới trần 4 USD | mục 6 |
| Review độc lập ghi finding và giới hạn | Codex REQUEST CHANGES 25/11; kiểm lại 4/5 đóng; kiểm lần ba **APPROVE**, cả 5 finding đóng | mục 5 |
| Owner đạt `PRACTICED` + `EXPLAINED` cho RBAC, Pod Security, NetworkPolicy, quota, Kyverno | **đạt** 25/11: `PRACTICED` (lab kind 24/11, micro-lab EKS 25/11) + `EXPLAINED` (teach-back 7/7 và câu quota) | mục 7 |
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
| Admission fail closed khi Kyverno không gọi được (tách 25/11) | F2 trên kind | D2 3b: Service hỏng + 150 giây → `ok` và `bad` đều `InternalError` ở tenant; `sys` ở `kube-system` được nhận; cluster vẫn dọn được (mục 8) | đạt; cách giải thích độ trễ 150 giây chưa kiểm chứng (F6) |
| Scale về 0 là đường vòng chỉ admin có (tách 25/11) | F1 trên kind | D2 3a: 0 webhook, Pod `bad` được nhận; tenant không có quyền trên namespace `kyverno` (D1, `T04`) | đạt; ghi thành giới hạn T15 (mục 4 giới hạn 2) |
| Teardown đầy đủ | thứ tự teardown kind (F3) | `65 destroyed`, inventory `CLEAN` | đạt **có điều kiện dừng G2**: 8 webhook Kyverno sống sót sau khi xoá app, Claude xoá theo nhãn trước destroy. Runbook E2 đã có bước này (PR #87) |

### 3.1. Hai quyết định ngày 25/11

Owner giao Claude chọn cách tối ưu để hoàn thành dự án (chat 25/11: "bạn cứ chọn cách tối ưu nhất là được để hoàn thành dự án"). Claude chọn:

1. **Tách kịch bản "Admission failure is understood"** thành hai kịch bản trong SPEC §4, theo đề xuất có từ lab kind 24/11 (SPEC §10 F1–F2), tức là **trước** window EKS.
   - Lý do: câu cũ gộp hai sự cố cho hai kết quả ngược nhau. Cả hai đã quan sát trên kind và EKS.
   - Đây là sửa câu chữ của tiêu chí nghiệm thu sau khi có kết quả. Để minh bạch, hai kết quả 3a/3b giữ nguyên, finding 4 của Codex vẫn ghi ở mục 5, và lần sửa SPEC này **chưa được Codex xem**.
2. **Hai kịch bản "một phần" được chấp nhận là giới hạn**, không mở window mới:
   - `zdr-require-resources` trên EKS: LimitRange điền resources trước Kyverno, nên Pod thiếu resources không bao giờ tới luật này. Luật đã được chứng minh trên kind (`noreq2`, LimitRange gỡ tạm) và bằng `kyverno test` trong CI.
   - Quota số Pod và số object: cùng cơ chế ResourceQuota với ca GPU đã chạy trên EKS. Mang sang suite P6, vì `BatchTrainingJob` tạo Job và `count/jobs` khi đó có ý nghĩa thật.

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

**Đạt (26/11).**

**Inventory trễ.** Owner làm mới MFA; Claude chạy `infra/terraform/scripts/inventory.sh` (profile `zdr-tf`,
chỉ đọc) lúc 2026-11-26T04:00:14Z, khoảng 21 giờ sau destroy. Mọi bộ đếm EKS, EC2, EBS, VPC, NAT, EIP,
VPC endpoint, ENI, SG, LB, RDS (gồm snapshot và automated backup), SQS, secret (gồm secret chờ xoá),
`p4_*`, KMS, log group, OIDC, `p3_iam_roles` đều 0; `s3_buckets=1` (bucket state). Chỉ mục tag
`Project=Zero-D-Rift` chỉ còn `1 s3:bucket`: 1 SG, 1 SG rule, 1 VPC endpoint lúc window đã hết, giống P4.
`RESULT: CLEAN (only the retain allowlist remains)`, exit 0.

**Bills tháng 11** (owner đọc trên console Billing ngày 26/11, cả tài khoản, `us-east-1`):

| Trang | Số đọc được |
|---|---|
| Bills, Highest AWS Region spend | 1,62 USD (US East, N. Virginia) |
| Charges by service | 13 dịch vụ, tổng trước thuế 0,00 USD (sau credits) |
| Savings, Credits | 1,62 USD: EC2 0,80, EKS 0,59, RDS 0,16, VPC 0,05, Secrets Manager 0,01, Data Transfer 0,01, S3 0,00 |

- Gross tháng 11 = 1,62 USD cả tài khoản, credits bù đủ, net 0. Gồm P3 window 05/11, hai window P4
  và window P5.
- Mốc trước window (25/11): gross 0,73 USD. Phần của P5 ≈ 1,62 − 0,73 = **0,89 USD**. Dù tính trọn
  1,62 vào P5 vẫn dưới trần P5 4 USD. Ước tính của window là 1,36 USD (mục 13 của window), cao hơn số đọc.
- Hoá đơn tháng còn ở trạng thái ước tính; số chốt khi phát hành không còn là cổng của P5 (giống P4 mục 6.1).
- Giới hạn: số đọc từ console do owner dán, không có export CUR; chia theo window là phép trừ hai lần đọc,
  không theo tag.

## 7. Teach-back §7

**Đạt (25/11).** Owner trả lời 7 câu SPEC §7 và một câu bổ sung về quota bằng lời của mình. Mỗi câu hỏi có một dòng gợi ý.
Claude chép nguyên văn và đối chiếu từng ý với bằng chứng: `docs/evidence/p5/P5-T4.3_TEACHBACK_20261125.md`.
- Kết quả: 8/8 đạt. Hai chỗ thiếu nhỏ: câu 2 chỉ xem `tenant-b` (cần cả egress của `tenant-a`); câu 3 bỏ sót dải VPC trong `except`.
- Chưa nói bằng lời: khi nào `zdr-require-resources` thật sự có tác dụng.
- Trạng thái học (`.agent/learning/CURRENT_STATUS.md`): RBAC, Pod Security, NetworkPolicy, quota, Kyverno `PRACTICED` + `EXPLAINED`.
- Giới hạn: không có dự đoán trước lab nào của P5 (owner chọn).

## 8. Việc sau window (đã xong)

| PR | Phát hiện | Thay đổi |
|---|---|---|
| [PR #85](https://github.com/EurusDevSec/Zero-D-Rift/pull/85) | F3 | `check_guards.sh` sửa trên fixture riêng; kiểm baseline trước các case. Trên `main` `010c49b`: 77/77 PASS |
| [PR #86](https://github.com/EurusDevSec/Zero-D-Rift/pull/86) | F8 | `smoke.sh` đọc số node từ `run.tfvars` (mặc định từ `variables.tf`); số sai thì dừng. Chỉ thử offline |
| [PR #87](https://github.com/EurusDevSec/Zero-D-Rift/pull/87) | F4, F6, F7, F9 | runbook: quy tắc MFA, chờ 150 giây ở 3b, xoá webhook Kyverno theo nhãn, tên container node agent |
