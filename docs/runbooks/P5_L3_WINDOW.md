# P5 L3 window trên EKS: đơn xin duyệt và luồng chạy (DRF-71, P5-T4.2)

> **TL;DR** · Để làm gì: chạy guardrail P5 trên EKS thật. Đầu tiên lượt control cho thấy cửa **mở**,
> sau đó bật guardrail và chạy suite để thấy cửa **khoá**, cuối cùng dọn sạch ·
> Chi phí: ước tính ≤ 2,3 USD, trần P5 là 4 USD ·
> Liên quan: SPEC-P5 §5 P5-T4.2, D10, A6, A15, A16; runbook `P4_RAG_SANDBOX.md` (B, C, J),
> `P2_L3_WINDOW.md` (C, F), `P5_ISOLATION_SUITE.md` §5 ·
> Mục lục: 1 Đơn · 2 Bạn chọn · 3 Việc trước window · 4 Cổng T−30 · 5 Luồng window · 6 Điều kiện dừng · 7 Chi phí

Ví von: P4 đã xây xong hai căn hộ và chứng minh có người ở được. P5 lắp khoá cửa, bảo vệ và tường ngăn.
Muốn chứng minh khoá có tác dụng thì phải ghi lại lúc **chưa khoá** hai nhà sang được nhau (control),
rồi khoá và thử lại (enforced). Không có lượt control thì "bị chặn" có thể chỉ là do mạng hỏng.

## 1. Đơn xin duyệt

Không ghi account ID, IP, ARN hay tên bucket state vào đây, vào chat hay vào Linear.

```
WINDOW REQUEST — P5 L3
RunId:             P5-L3-YYYYMMDD-01
Bắt đầu:           YYYY-MM-DD HH:MM Asia/Saigon (= HH:MM UTC)        ← bạn chọn
Kết thúc cứng:     bắt đầu + 5 giờ; tag ExpiresAt = giờ này, dạng UTC ...Z
Freeze-new-create: kết thúc cứng − 1,5 giờ
Teardown owner:    HoangLV, có mặt suốt window; không rời máy khi cluster hoặc RDS còn chạy
Người chạy:        Claude (lệnh AWS, kubectl); owner gõ micro-lab, tự merge PR Deny và PR xoá request
Git revision:      main = <điền ở cổng>; ứng viên đã chốt, không sửa code trong window (A16)
Node:              2 × m6i.large (system_node_desired_size = 2)       ← owner chọn 24/11, xem mục 2
Plan:              <N> to add, 0 to change, 0 to destroy; shape sha256 <điền ở cổng>
Ước tính:          ≈ 0,45 USD/giờ → ≈ 2,3 USD nếu chạy hết 5 giờ
Trần P5 (D10):     4 USD gross cho mọi window P5 và mọi lần thử lại
P5 đã tiêu:        0 (P5 chưa tạo tài nguyên AWS nào; mọi lab P5 chạy trên kind)
Owner duyệt:       "Duyệt window P5-L3-YYYYMMDD-01" (gõ trong chat)
```

Chỉ apply khi đủ cả năm điều kiện:

1. Plan khớp shape hash đã ghi.
2. Danh tính đúng.
3. Còn dưới trần.
4. Window đang mở.
5. Bạn đã duyệt đúng RunId.

## 2. Hai điều bạn chọn khi duyệt

**a. Giờ bắt đầu.** Cần 5 giờ liền và bạn ngồi máy suốt. Chọn lúc bạn không phải rời máy.

**b. Số node: 2** (owner chọn ngày 24/11). Lý do: A6 (sức chứa của node) chưa đo bao giờ.

| | 1 node (như P4) | 2 node (đề xuất) |
|---|---|---|
| Pod ước tính lúc đông nhất | khoảng 27 trên giới hạn 29 của `m6i.large` (giới hạn này chưa kiểm, S7) | khoảng 27 trên 58 |
| Rủi ro | Pod `Pending` do `Too many pods` giữa chừng thì dừng window, tốn thêm một window nữa | thấp |
| NetworkPolicy | các Pod thường nằm chung một node | Pod có thể nằm ở hai node, nên agent ở cả hai node đều được thử |
| Chi phí thêm | 0 | ≈ 0,1 USD/giờ, tức ≈ 0,5 USD cho 5 giờ |
| Quota vCPU | cần 2 | cần 4; thấy 8 ngày 22/11, kiểm lại ở cổng |

Con số khoảng 27 Pod là Claude đếm từ danh sách controller, chưa phải số đo thật. Dù chọn bao nhiêu node,
bước B vẫn đo số Pod và memory allocatable, rồi ghi vào evidence.

## 3. Việc trước window (Claude, không AWS, không tốn tiền)

| # | Việc | Xong khi |
|---|---|---|
| P1 | Soạn sẵn PR "Kyverno Audit → Deny" (3 file trong `gitops/platform/policies/`, mỗi file chỉ đổi `validationActions`). **Không merge trước window** | [PR #76](https://github.com/EurusDevSec/Zero-D-Rift/pull/76) mở ở dạng **draft**; chờ bạn merge ở bước C3 |
| P2 | Thử trên kind các lệnh tạm dừng và bật lại sync (`zdr-root`, `zdr-tenants`, `zdr-kyverno*`): app con không bị root bật lại khi đang tạm dừng; NetworkPolicy quay về khi bật lại | **Xong 24/11** (Claude, kind `zdr-p5-l3prep`), mục 5a |
| P3 | Soạn lệnh micro-lab một dòng cho từng lớp (RBAC, Pod Security, quota, Kyverno, AppProject, NetworkPolicy) và thử trên kind. Pod Security chặn trước Kyverno, nên Pod của ca Kyverno phải hợp lệ với `restricted` | **Xong 24/11** (Claude, kind), mục 5b; file trong `tests/isolation/microlab/` |
| P4 | Bạn điền **bảng dự đoán** ở cuối `P5_ISOLATION_SUITE.md` trước window | Có dự đoán của bạn |

## 4. Cổng T−30 (chỉ đọc, có MFA)

Làm như `P4_RAG_SANDBOX.md` mục C (gồm `P2_L3_WINDOW.md` C), rồi kiểm thêm các mục riêng của P5:

| Kiểm | Phải thấy |
|---|---|
| Danh tính | `assumed-role/zero-drift-bootstrap/<SESSION>`; MFA còn ≥ 40 phút lúc apply |
| `inventory.sh` | `RESULT: CLEAN` |
| Quota vCPU On-Demand | ≥ 4 nếu 2 node, ≥ 2 nếu 1 node |
| Giá (S5, đọc ngày 28/09) | đọc lại giá `m6i.large`, EKS, IPv4, `db.t4g.micro`; lệch > 20% thì tính lại ước tính trước khi duyệt |
| `run.tfvars` | `run_id`, `expires_at` theo đơn; IP đúng; `system_node_desired_size` theo lựa chọn của bạn; **không** đè `vpc_cidr` |
| Pre-flight CIDR | `bash gitops/check.sh` PASS. Luật egress so `ipBlock` với `vpc_cidr` trong `variables.tf`, nên `run.tfvars` không được đổi giá trị này |
| `terraform plan` + `plan_assert.sh` (`ADMIN_WINDOW=1 P4_WINDOW=1`) | PASS; output `vpc_cni_configuration` có `enableNetworkPolicy = "true"`, mode `standard`; ghi số resource và shape sha256 vào đơn |
| `rag_iam_check.sh tfplan` | PASS |

## 5. Luồng window

```
B Dựng (1 g)        apply → smoke P2 → Argo CD → platform → db-init → 2 sandbox Ready
                    → đo Pod/memory node (A6) → Kyverno ở Audit
C Control (1 g)     tạm dừng sync → xoá NetworkPolicy → suite control (4 đường phải MỞ)
                    → bật lại sync → NetworkPolicy + PolicyEndpoint về → report Audit sạch
                    → bạn merge PR Deny → xoá, tạo lại 2 sandbox → Ready
D Suite (1 g)       suite enforced (mọi case PASS, không SKIPPED) → Kyverno sập (3a, 3b)
                    → micro-lab bạn gõ
E Dọn (0,5 g)       request + cleanup → policy → Kyverno → webhook = 0 → P4 J → destroy → inventory
```

**B. Dựng.** Làm `P4_RAG_SANDBOX.md` từ mục D tới hai sandbox Ready (P4 F). Thêm:

- Đo A6 (Claude đọc, ghi vào evidence): số Pod đang chạy so với allocatable `pods`, và tổng memory request so với allocatable memory của từng node.
- `zdr-kyverno` và `zdr-kyverno-policies` `Synced Healthy`. Ba policy ở `Audit`. Webhook `Fail` và chỉ bắt namespace tenant (như lab kind bước 0).

**C. Control rồi guardrail.** Root có `selfHeal`, nên phải tạm dừng root **trước**, rồi mới tạm dừng app con.

1. Tạm dừng sync cho `zdr-root` rồi `zdr-tenants` (lệnh ở mục 5a). Xoá NetworkPolicy của `tenant-a` và `tenant-b`.
2. Chạy suite pha control theo `P5_ISOLATION_SUITE.md` §5, `RUN_ID=P5-L3-YYYYMMDD-01-control`. Phải thấy 4 đường `allow`; giữ file `control.json`.
3. Bật lại sync: `kubectl apply -f gitops/bootstrap/root-app.yaml` (mục 5a). Root tự trả spec của app con về như trong Git, nên NetworkPolicy về lại. Báo cáo Audit phải sạch. **Bạn merge PR Deny** (P1). Đợi Argo áp xong, ba policy ở `Deny`.
4. Xoá rồi tạo lại hai sandbox bằng PR request (như P4 I). Cả hai Ready; `probe sandbox` PASS.

**D. Suite và sự cố.**

1. Chạy suite pha enforced theo `P5_ISOLATION_SUITE.md` §5, với `CONTROL=control.json` và `RUN_ID=P5-L3-YYYYMMDD-01`. Phải thấy exit 0, không case nào `SKIPPED`, cleanup `verified-empty`. Mỗi ca âm quan sát tối đa 10 phút, tổng cộng 900 giây.
2. Kyverno sập, làm như lab kind bước 3, sau khi đã tạm dừng `zdr-root`, `zdr-kyverno` và `zdr-kyverno-policies`:
   - 3a: scale admission controller về 0.
   - 3b: làm Service không gọi được.
   - Thử một Pod hợp lệ ở `tenant-a` và một Pod ở `kube-system`. Ghi kết quả, rồi khôi phục và bật lại sync.
3. Micro-lab: bạn tự gõ lệnh ở mục 5b, mỗi lớp một request bị cấm.

**E. Dọn** (từ giờ freeze, hoặc sớm hơn nếu đã xong).

1. Làm `P4_RAG_SANDBOX.md` J bước 1–2: xoá request (cascade), chạy cleanup, xoá secret bootstrap.
2. Gỡ guardrail trước controller P4. Xoá app `zdr-kyverno-policies`, rồi `zdr-kyverno` (cascade). Sau đó chạy `kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -o name | grep -ci kyverno`, phải ra `0`.
3. Làm tiếp P4 J bước 3–4: gỡ các app còn lại theo thứ tự ngược wave, gỡ Argo CD, `terraform destroy`, rồi chạy `inventory.sh`, phải ra `RESULT: CLEAN`.
4. Inventory trễ vào ngày hôm sau (A16).

### 5a. Tạm dừng và bật lại sync (Claude đã thử trên kind ngày 24/11)

Ví von: Argo CD là người quản gia, cứ thấy đồ trong nhà khác bản vẽ (Git) là trả về như cũ. `zdr-root` là quản gia
trưởng: nó trả cả **lệnh của quản gia con** về như bản vẽ. Vì vậy phải cho quản gia trưởng nghỉ trước.

Tạm dừng (ví dụ cho bước C1; ở bước D2 thay `zdr-tenants` bằng `zdr-kyverno zdr-kyverno-policies`):

```bash
for a in zdr-root zdr-tenants; do kubectl -n argocd patch app $a --type json -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]'; done
```

Bật lại (một lệnh cho mọi trường hợp; root tự trả `automated` cho từng app con):

```bash
kubectl apply -f gitops/bootstrap/root-app.yaml
```

Kết quả trên kind (Argo CD v3.5.7, root app thật từ `main`):

| Thử | Quan sát |
|---|---|
| Chỉ tạm dừng `zdr-tenants`, **không** dừng root | Sau 10 giây root bật lại `automated` cho `zdr-tenants`. Đây là cái bẫy |
| Dừng root rồi `zdr-tenants`, xoá 10 NetworkPolicy | Trong 3 phút 45 giây vẫn 0 NetworkPolicy; không app nào tự bật lại sync |
| Bật lại bằng root | Sau 1 giây `zdr-tenants` có lại `automated`; sau 16 giây đủ 10 NetworkPolicy; `Synced Healthy` |
| Dừng root, `zdr-kyverno`, `zdr-kyverno-policies`; patch 3 policy sang `Deny`; scale admission về 0 | Trong 3 phút 30 giây replicas vẫn 0, policy vẫn `Deny`, không còn webhook Kyverno (Kyverno tự gỡ webhook khi tắt êm) |
| Bật lại bằng root | Sau 16 giây có lại 1 replica, policy về như Git (`Audit` trên `main` lúc thử; sau khi PR #76 merge sẽ là `Deny`) |

### 5b. Micro-lab: bạn tự gõ, mỗi lớp một request bị cấm

Gõ ở bước D3, khi policy đã `Deny`. Điền cột dự đoán **trước** window. Cột "Phải thấy" là kết quả Claude đã thử trên kind ngày 24/11;
riêng ca NetworkPolicy trên kind dùng một listener giả ở `tenant-b`, còn trên EKS là Service thật của sandbox.

| Lớp | Lệnh | Dự đoán của bạn | Phải thấy |
|---|---|---|---|
| RBAC | `kubectl auth can-i delete pods -n tenant-a --as=alice --as-group=zdr:tenant-a:developers` | | `no` (cùng group, `get pods` thì `yes`) |
| Pod Security | `kubectl -n tenant-a run microlab-priv --image=busybox:1.37 --privileged --dry-run=server` | | `violates PodSecurity "restricted:v1.35": privileged …` |
| Quota | `kubectl apply --dry-run=server -f tests/isolation/microlab/gpu.yaml` | | `exceeded quota: tenant-quota, requested: requests.nvidia.com/gpu=1 …` |
| Kyverno | `kubectl apply --dry-run=server -f tests/isolation/microlab/kyverno-tag.yaml` | | `Policy zdr-image-digest failed: image must come from … pinned by @sha256`. Ở `Audit` thì `created (server dry run)` |
| AppProject | `kubectl apply -f tests/isolation/microlab/appproject-bad-ns.yaml`, rồi `kubectl -n argocd get app zdr-microlab-badns -o jsonpath='{.status.conditions[*].message}'`, rồi `kubectl -n argocd delete app zdr-microlab-badns` | | `InvalidSpecError: … namespace 'zdr-platform' do not match any of the allowed destinations in project 'zdr-requests'` |
| NetworkPolicy | `kubectl apply -f tests/isolation/microlab/netpol-a-to-b.yaml`, rồi `kubectl -n tenant-a wait --for=condition=complete job/microlab-a-to-b --timeout=120s`, rồi `kubectl -n tenant-a logs job/microlab-a-to-b`, rồi `kubectl -n tenant-a delete job microlab-a-to-b` | | `RESULT TIMEOUT`. Trên kind, cùng Job đặt ở `tenant-b` (đối chứng) ra `RESULT OPEN` |

## 6. Điều kiện dừng

Áp dụng S1–S7 của P2, P1–P5 của P3 và R1–R9 của P4. P5 thêm các điều kiện sau:

| # | Tình huống | Làm gì |
|---|---|---|
| G1 | Guardrail chặn một controller platform (Argo, kro, Crossplane, provider, Job `db-init`/bootstrap) | Ghi lại thông báo. Không nới guardrail trong window. Dọn |
| G2 | Còn webhook configuration của Kyverno sau khi đã gỡ Kyverno | Xoá tay webhook đó, ghi thành lỗi, rồi mới destroy |
| G3 | Pod `Pending` vì `Too many pods` hoặc thiếu memory (A6) | Ghi số đo. Không đổi số node trong window. Dọn, rồi xin window mới |
| G4 | Pha control: một trong 4 đường không `allow` | Mạng hỏng, chưa phải guardrail. Không chạy pha enforced. Ghi lại, dọn |
| G5 | Không có PolicyEndpoint sau khi NetworkPolicy đã về | Suite tự dừng. Ghi trạng thái node agent, dọn |
| G6 | Sau khi bật lại sync mà app không về `Synced` | Không sửa tay. Ghi lại, dọn |

## 7. Chi phí

| Khoản | USD/giờ | Nguồn |
|---|---|---|
| Stack P4, 1 node (EKS, node, RDS, IPv4, EBS) | 0,35 | D10 / A15, ước tính |
| Node thứ hai `m6i.large` + IPv4 | ≈ 0,10 | S5 (đọc ngày 28/09), đọc lại ở cổng |
| **Tổng (2 node)** | **≈ 0,45** | 5 giờ → ≈ 2,3 USD, dưới trần 4 USD |

Đối chiếu: Bills gross tháng 11 của cả tài khoản là 0,73 USD, gồm window P3 và hai window P4.
Credits ước tính window P4 ngày 21/11 tốn khoảng 0,26 USD, thấp hơn ước tính D10. Bills gross của P5
chỉ đọc được sau window (P5-T4.3).
