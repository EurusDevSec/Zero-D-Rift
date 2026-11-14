# DRF-38 (P3-T6) — Kiểm nghiệm thu P3 (06/11/2026)

SPEC: `.agent/specs/SPEC-P3_FIRST_RESOURCE_GRAPH.md` §4 (kịch bản), §5 Task 6, §7 (teach-back), §8 (quy tắc hoàn thành).
Người viết: Claude. Đây là **tự kiểm**, không phải review độc lập, cũng không phải bằng chứng owner đã học.
Revision ứng viên: `main` = `c98b4a1be2ea98e88128e09ca1b8348eb1bd3a17` (merge PR #28).

## 1. Kịch bản SPEC §4 và evidence

| Kịch bản | L2 (kind, không AWS) | L3 (EKS, P3-L3-20261105-01) | Trạng thái |
|---|---|---|---|
| Controller được pin và giới hạn | DRF14_L2_KIND: Crossplane 2.4.3, provider 2.8.1, kro 0.9.4 healthy trên 1.35. DRF35: 7 app sync thật từ GitHub | DRF37: 7 app con Synced/Healthy; 2 provider đúng digest, `INSTALLED/HEALTHY`, không provider nào khác; RGD Active | **Đạt**, có giới hạn: chưa chụp imageID đang chạy của Crossplane core và kro |
| Một request dựng cả graph | DRF14: graph ZdrRequest; bucket thất bại vì không có credential | DRF37: bucket thật đủ 6 tag; Deployment chỉ tạo sau khi bucket Ready; instance `ACTIVE/Ready` | **Đạt** |
| Readiness không bị giả | DRF14: không có `readyWhen` thì instance Ready giả; đã thêm `readyWhen` | DRF37: `AccessDenied` thật từ role IRSA ngoài prefix; instance âm không Ready; Argo vẫn Synced | **Đạt** |
| Xóa đoán trước được | DRF35: prune trên kind (bucket chưa từng tạo) | DRF37: xóa qua Git, 17 giây sau bucket AWS mất; không kẹt finalizer | **Đạt** (đường orphan của D6 không thử, đúng như D6 cho phép) |
| Teardown đầy đủ | DRF35: teardown app trên kind (bỏ bước root) | DRF37: root trước, 7 app, Argo, gỡ admin, destroy 52, inventory CLEAN | **Đạt** |

## 2. Quy tắc hoàn thành §8

| Điều kiện | Trạng thái |
|---|---|
| Các kịch bản §4 có evidence L3 trên EKS | **Đạt** (bảng trên) |
| Teardown sạch | **Đạt**: inventory 05/11 16:45Z CLEAN |
| Inventory trễ sạch | **Đạt** 06/11 04:01Z (khoảng 11 giờ sau destroy), phiên MFA mới của owner: `RESULT: CLEAN`, 25 kiểm OK (gồm `eks_clusters=0`, `vpc_endpoints_live=0`, `oidc_providers=0`, `p3_iam_roles=0`, `s3_buckets=1`); role `zero-drift-p3-crossplane-s3` không tồn tại; bucket `zero-drift-p3-*`/`zdr-outside*` = 0; `terraform state list` = 0 |
| Đối chiếu billing | **Chưa**: owner xem Billing → Bills (us-east-1, theo dịch vụ). Ước tính ≈ 0,22 USD; trần 3 USD |
| Review độc lập ghi findings và limits | **Chưa**: yêu cầu cho Codex ở mục 4 |
| Owner đạt `PRACTICED` + `EXPLAINED` cho luồng Git → Argo CD → kro → Crossplane → AWS và semantics xóa | **Chưa đạt**: `PRACTICED` có (lab kind 14/11, owner tự chạy phần 0–7). `EXPLAINED` mới một phần: trả lời 2/6 câu, có lỗi vai trò kro/Crossplane; câu 3–6 chưa trả lời (mục 6) |

**Kết luận hiện tại: P3 chưa hoàn thành.** Phần kỹ thuật đã có evidence L3 và inventory trễ sạch; còn 3 cổng do người khác làm: billing (owner), review (Codex), teach-back (owner).

**Quyết định của owner 14/11/2026:** dừng teach-back sau câu 2 và chuyển sang P4 ("thôi bỏ qua tốn thời gian quá nhanh qua phase 4 đi"). P3 **không** được đánh dấu hoàn thành; 3 cổng vẫn mở và được mang theo: billing, review Codex, teach-back câu 3–6 cùng phần sửa câu 1–2.

## 3. Lỗi và sửa trong P3 (để reviewer soi)

| # | Lỗi | Bắt bởi | Sửa |
|---|---|---|---|
| 1 | Policy role P3 dùng `s3:Get*` trên `arn:aws:s3:::zero-drift-p3-*`, mà `*` đi qua dấu `/` nên khớp cả object (`GetObject` allowed) | Mô phỏng IAM trước window | PR #26: chỉ action mức bucket; wildcard duy nhất `s3:GetBucket*`; test + `plan_assert` chặn |
| 2 | Trust của role P3 unknown ở plan đầu (OIDC chưa có) | `plan_assert` | PR #26: INFO ở plan; kiểm trust thật sau apply (`p3_iam_check --principal`) |
| 3 | Endpoint S3 (P2) chặn layer của quay.io và registry.k8s.io | Window L3 (Argo `ImagePullBackOff`) | PR #27: thêm 2 bucket chỉ `s3:GetObject`; check 7 khóa đúng 4 bucket |
| 4 | `directory.recurse: false` làm `zdr-root` luôn OutOfSync | Window L3 | PR #28: bỏ giá trị mặc định; check.sh cấm `recurse: true`. Đã kiểm lại trên kind 14/11 (L2): `zdr-root` `Synced/Healthy` ở `ee34db4`. Chưa kiểm lại trên EKS |
| 5 | kro `readyWhen` tham chiếu `schema` làm RGD Inactive | Sync thật trên kind | PR #23 |
| 6 | kro aggregation thiếu RBAC cho kind sinh ra (cache sync timeout) | Lab kind | PR #21/#23: ClusterRole aggregate |

## 4. Yêu cầu review độc lập (cho Codex)

- **Ứng viên:** base `dd3b77b6f36815778e4697887d6595cda38eeb9d` (SPEC-P3 đã được Codex review 05/11), head `c98b4a1be2ea98e88128e09ca1b8348eb1bd3a17`. 46 file, PR #19–#28.
- **Đọc trước:** SPEC-P3 §4, §5, §8; ADR-0003, ADR-0005; evidence `docs/evidence/p3/DRF14_L2_KIND_20261105.md`, `DRF35_P3_GITOPS_20261105.md`, `DRF36_P3_IRSA_20261105.md`, `DRF37_L3_WINDOW_20261105.md`, file này.
- **Câu hỏi cần trả lời:**
  1. Policy role IRSA (`infra/terraform/modules/p3-provider-irsa/main.tf`) có còn đường tới object, bucket ngoài prefix, hay leo quyền IAM không? Trust có chỉ một SA, một audience không?
  2. Policy endpoint S3 sau PR #27 (`modules/network/main.tf`) có mở cửa ra cho dữ liệu đi ra ngoài không (chỉ `s3:GetObject` trên 4 bucket)? `plan_assert` check 7 có đủ chặt không?
  3. GitOps (`gitops/`): pin đủ chưa (digest, chart version)? Sync policy có đúng: requests prune, platform không prune? Teardown root trước có đủ không?
  4. Evidence DRF37 có chứng minh đủ 5 kịch bản §4 không, hay có chỗ kết luận vượt quá dữ liệu?
  5. Có lộ account ID, ARN, IP, tên bucket state trong Git không?
- **Giới hạn đã biết** (không cần báo lại): bản sửa `recurse` mới kiểm lại trên kind (14/11), chưa trên EKS; thiếu imageID đang chạy; R1 least-privilege chưa có role P3 (hoãn tới DRF-27/29); ADR-0005 còn PROPOSED.
- **Ghi kết quả:** reviewer, revision, verdict, findings (mức độ), lệnh đã chạy, giới hạn. Ghi vào mục 5 dưới đây qua PR, hoặc comment Linear DRF-38.

## 5. Kết quả review độc lập

_Chưa có._ Không được điền thay.

## 6. Teach-back của owner

Owner chạy `docs/runbooks/P3_TEACHBACK_LAB.md` trên kind ngày 14/11/2026 (khoảng 12:10–13:36 giờ máy), tự gõ lệnh và dán output vào chat; Claude hướng dẫn và đọc output. Mức học chỉ cập nhật từ phần owner làm và nói được.

### 6.1 Lab: owner đã chạy gì, thấy gì

| Phần | Kết quả owner thấy |
|---|---|
| 0 | Lần đầu lệnh `kind create` bị cắt khi dán (`\` xuống dòng), cluster lên `v1.37.0` mặc định; owner xóa và tạo lại đúng `v1.35.8` (digest). Argo CD v3.5.7 sha256 `OK`, 6 deployment `condition met` |
| 1 | 8 app `Synced/Healthy` ở `ee34db4` (bao gồm `zdr-root`, xác nhận bản sửa PR #28 trên kind). Sau khi tắt automated của root và trỏ `zdr-requests` về `cff3ac9`: root `OutOfSync` (drift được báo, không tự sửa). Instance có `argocd.argoproj.io/tracking-id`; Bucket MR có `kro.run/instance-name: spike`, `kro.run/node-id: bucket`; MR `Synced=False` vì IRSA thiếu `AWS_WEB_IDENTITY_TOKEN_FILE` |
| 2 | Argo `Synced/Healthy`; instance `IN_PROGRESS`, `ResourcesReady=False` chờ `readyWhen` của node `bucket`; MR `SYNCED False`, event `CannotConnectToProvider` x15; log provider chỉ có dòng khởi động; không có Deployment |
| 3 | 3a: `kubectl delete` instance → sau 15 giây instance và MR quay lại (AGE 42s, selfHeal + kro). 3b: `targetRevision: main` → 0 object; provider, Crossplane vẫn chạy (AGE 44m) |
| 4 | SA nhận annotation `role-arn` giả từ DRC; pod mới không có `AWS_ROLE_ARN` (jq `false`, kind không có webhook IRSA). Đổi `Resource` thành `*`: `terraform test` `19 passed, 1 failed`; hoàn tác: `20 passed`, Git sạch |
| 5 | **Khác dự kiến.** Xóa app `zdr-providers` khi MR còn: `provider-aws-s3` và CRD `buckets` mất, MR mất theo (không kẹt). Kẹt ở chỗ khác: instance `spike` giữ `kro.run/finalizer` (`deletion blocked: list ... buckets ... could not find the requested resource`); ClusterProviderConfig `default` giữ `in-use.crossplane.io` với `users=1`; `provider-family-aws` `foregroundDeletion`; app treo. Giả thuyết (chưa chứng minh): MR không có finalizer vì provider chưa từng connect được AWS |
| 6–7 | Đọc `p3_provider_irsa`, `kind: Bucket` trong RGD, mốc 16:28/16:43 của DRF37. `kind delete cluster`; `No kind clusters found` |

### 6.2 Câu trả lời của owner (nguyên văn, 14/11/2026)

> câu 1 : mình merge file instance vào git. Argocd thấy commit mới, apply instace SToẻageappspike lên cluster (bằng chứng: annotation kro) crossplane đọc rgd sinh ra bucket mr(bằng chứng nhãn kro.run/bucket) provider aws s3 dùng credential từ irsa để gọi aws tạo bucket thật
>
> câu 2: Argo xanh chỉ có nghĩa là cluster đã giống với git, khôngnói gì về aws, Mình đã xem theo thứ tự apps-> íntace (state là sync)  -> mr cột synced là healthy) -> describe mr đọc ... logg provider
>
> thôi bỏ qua tốn thời gian quá nhanh qua phase 4 đi

Câu 3–6: chưa trả lời.

### 6.3 Nhận xét (Claude, so với output owner đã dán)

- **Câu 1:** thứ tự Git → Argo → instance → MR → provider → AWS qua IRSA là đúng. Sai vai trò: **kro** (không phải Crossplane) đọc RGD và sinh Bucket MR; Crossplane provider reconcile MR rồi gọi AWS. Bằng chứng Argo apply instance là annotation **Argo** `argocd.argoproj.io/tracking-id`, không phải annotation kro. Nhãn trên MR là `kro.run/instance-name: spike` và `kro.run/node-id: bucket`.
- **Câu 2:** câu đầu đúng (Argo chỉ so cluster với Git). Thứ tự xem đúng. Giá trị ghi lại sai so với output: instance `IN_PROGRESS`/`Ready=False` (không phải "sync"); MR `SYNCED False` (không phải healthy). Thiếu: kro chờ `readyWhen` của node `bucket` nên chưa tạo Deployment; lỗi đọc ở status/events của MR, log provider gần như im lặng.
- **Câu 3–6:** không có câu trả lời nên không đánh giá. Lab đã cho đủ dữ liệu (phần 3–6 ở 6.1).

### 6.4 Mức đạt

- Argo CD, kro, Crossplane: **`PRACTICED`** (lab có output 14/11).
- **`EXPLAINED` chưa đạt.** Cần: sửa vai trò kro/Crossplane ở câu 1, đọc đúng trạng thái ở câu 2, trả lời câu 3–6 bằng lời của owner.
