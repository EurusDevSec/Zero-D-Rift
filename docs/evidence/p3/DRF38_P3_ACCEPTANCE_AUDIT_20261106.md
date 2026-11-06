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
| Owner đạt `PRACTICED` + `EXPLAINED` cho luồng Git → Argo CD → kro → Crossplane → AWS và semantics xóa | **Chưa**: owner chạy `docs/runbooks/P3_TEACHBACK_LAB.md` và trả lời 6 câu §7 bằng lời của mình |

**Kết luận hiện tại: P3 chưa hoàn thành.** Phần kỹ thuật đã có evidence L3 và inventory trễ sạch; còn 3 cổng do người khác làm: billing (owner), review (Codex), teach-back (owner).

## 3. Lỗi và sửa trong P3 (để reviewer soi)

| # | Lỗi | Bắt bởi | Sửa |
|---|---|---|---|
| 1 | Policy role P3 dùng `s3:Get*` trên `arn:aws:s3:::zero-drift-p3-*`, mà `*` đi qua dấu `/` nên khớp cả object (`GetObject` allowed) | Mô phỏng IAM trước window | PR #26: chỉ action mức bucket; wildcard duy nhất `s3:GetBucket*`; test + `plan_assert` chặn |
| 2 | Trust của role P3 unknown ở plan đầu (OIDC chưa có) | `plan_assert` | PR #26: INFO ở plan; kiểm trust thật sau apply (`p3_iam_check --principal`) |
| 3 | Endpoint S3 (P2) chặn layer của quay.io và registry.k8s.io | Window L3 (Argo `ImagePullBackOff`) | PR #27: thêm 2 bucket chỉ `s3:GetObject`; check 7 khóa đúng 4 bucket |
| 4 | `directory.recurse: false` làm `zdr-root` luôn OutOfSync | Window L3 | PR #28: bỏ giá trị mặc định; check.sh cấm `recurse: true`. **Chưa kiểm lại trên cluster** |
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
- **Giới hạn đã biết** (không cần báo lại): bản sửa `recurse` chưa chạy lại trên cluster; thiếu imageID đang chạy; R1 least-privilege chưa có role P3 (hoãn tới DRF-27/29); ADR-0005 còn PROPOSED.
- **Ghi kết quả:** reviewer, revision, verdict, findings (mức độ), lệnh đã chạy, giới hạn. Ghi vào mục 5 dưới đây qua PR, hoặc comment Linear DRF-38.

## 5. Kết quả review độc lập

_Chưa có._ Không được điền thay.

## 6. Teach-back của owner

_Chưa có._ Owner chạy `docs/runbooks/P3_TEACHBACK_LAB.md`, trả lời trong chat; Claude ghi nguyên văn vào đây. Mức học chỉ cập nhật từ phần owner làm và nói được.
