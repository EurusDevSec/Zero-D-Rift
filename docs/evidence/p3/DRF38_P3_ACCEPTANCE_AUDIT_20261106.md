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
| Đối chiếu billing | **Đạt** 14/11 (owner đọc Billing → Bills, tháng 11/2026): tổng phí trước thuế `USD 0.00` trên 13 dịch vụ (gồm EKS, EC2, VPC, S3); thẻ "Highest AWS Region spend" `USD 0.29`, US East (N. Virginia). Ước tính P3 ≈ 0,22 USD; trần 3 USD. Giới hạn: 0,29 USD là cả tháng (gồm window P2 04/11), không tách được theo window; trang không cho thấy chi tiết từng dịch vụ trước khi trừ credit |
| Review độc lập ghi findings và limits | **Đạt** 14/11: Codex, verdict REQUEST CHANGES với 1 finding MEDIUM (guard nhận quyền object). Đã sửa trong PR #31, kèm test âm (mục 3, #7; mục 5). Codex chưa xác nhận lại bản sửa |
| Owner đạt `PRACTICED` + `EXPLAINED` cho luồng Git → Argo CD → kro → Crossplane → AWS và semantics xóa | **Đạt, có giới hạn** 14/11: `PRACTICED` (lab kind, owner tự chạy phần 0–7). `EXPLAINED`: owner sửa câu 1–2 và trả lời câu 3–6, đúng với output lab. Giới hạn nguồn gốc của câu 3–6 ở mục 6.5 |

**Kết luận 14/11/2026: các cổng §8 đã có evidence.** P3 đóng khi owner merge PR #31 và chấp nhận các giới hạn sau:
- billing chỉ có tổng tháng, không tách theo window;
- Codex chưa xác nhận lại bản sửa finding #7;
- nguồn gốc câu trả lời teach-back 3–6 (mục 6.5);
- các giới hạn kỹ thuật đã biết ở mục 4.

Lịch sử: sáng 14/11 owner dừng teach-back sau câu 2 ("thôi bỏ qua tốn thời gian quá nhanh qua phase 4 đi"). Sau đó owner đổi ý ("khoan đã phải xong p3 luôn hoàn chỉnh nhưng phải nhanh lên") và nộp đủ 3 cổng.

## 3. Lỗi và sửa trong P3 (để reviewer soi)

| # | Lỗi | Bắt bởi | Sửa |
|---|---|---|---|
| 1 | Policy role P3 dùng `s3:Get*` trên `arn:aws:s3:::zero-drift-p3-*`, mà `*` đi qua dấu `/` nên khớp cả object (`GetObject` allowed) | Mô phỏng IAM trước window | PR #26: chỉ action mức bucket; wildcard duy nhất `s3:GetBucket*`; test + `plan_assert` chặn |
| 2 | Trust của role P3 unknown ở plan đầu (OIDC chưa có) | `plan_assert` | PR #26: INFO ở plan; kiểm trust thật sau apply (`p3_iam_check --principal`) |
| 3 | Endpoint S3 (P2) chặn layer của quay.io và registry.k8s.io | Window L3 (Argo `ImagePullBackOff`) | PR #27: thêm 2 bucket chỉ `s3:GetObject`; check 7 khóa đúng 4 bucket |
| 4 | `directory.recurse: false` làm `zdr-root` luôn OutOfSync | Window L3 | PR #28: bỏ giá trị mặc định; check.sh cấm `recurse: true`. Đã kiểm lại trên kind 14/11 (L2): `zdr-root` `Synced/Healthy` ở `ee34db4`. Chưa kiểm lại trên EKS |
| 5 | kro `readyWhen` tham chiếu `schema` làm RGD Inactive | Sync thật trên kind | PR #23 |
| 6 | kro aggregation thiếu RBAC cho kind sinh ra (cache sync timeout) | Lab kind | PR #21/#23: ClusterRole aggregate |
| 7 | Guard check 13 và `terraform test` nhận mọi action `s3:` không có `*`, nên `s3:DeleteObject`/`GetObject`/`PutObject` lọt qua (resource `zero-drift-p3-*` khớp cả object). Check 7 chỉ kiểm tập con, chưa bắt buộc đủ 4 bucket. Policy đang triển khai không có các quyền này | Review Codex 14/11 (MEDIUM) | PR #31: allowlist đúng 9 action mức bucket ở cả hai nơi; check 7 so khớp đúng tập 4 bucket; `tests/plan_assert_guards.sh` có 10 ca (bản cũ ra 4 WRONG) và `check.sh` chạy nó |

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

Owner chạy Codex với yêu cầu ở mục 4, rồi dán kết quả vào chat ngày 14/11/2026. Claude ghi nguyên văn bên dưới, chỉ bỏ phần đường dẫn tuyệt đối trên máy.

> **Reviewer:** Codex, review độc lập ngày 14/11/2026.
> **Revision:** base `dd3b77b6f36815778e4697887d6595cda38eeb9d` → head `c98b4a1be2ea98e88128e09ca1b8348eb1bd3a17`.
> **Verdict: REQUEST CHANGES — 1 finding MEDIUM về guard kiểm quyền.** Policy đang triển khai không thấy vượt phạm vi P3.
>
> **Finding**
>
> - **MEDIUM — Guard vẫn chấp nhận quyền object.** Tại `plan_assert.sh:154` và `p3_irsa.tftest.hcl:63`, điều kiện chấp nhận mọi action `s3:` không chứa wildcard. Trong khi đó resource `zero-drift-p3-*` cũng khớp ARN object. Probe cục bộ bằng chính biểu thức jq trả `true` khi thêm `s3:DeleteObject`, hoặc `GetObject/PutObject`. Ma trận IAM hiện có cũng chưa thử `DeleteObject`. Sửa gọn: dùng allowlist action mức bucket đã duyệt và kiểm trường hợp thêm quyền object. Đây là thiếu sót của guard; policy hiện tại không chứa các quyền object trên.
>
> **Kết quả đúng 5 câu hỏi**
>
> | Câu | Kết quả |
> |---|---|
> | 1. IRSA | Policy hiện tại không thấy quyền object, bucket ngoài prefix hoặc leo quyền IAM. Trust khóa đúng OIDC của cluster, một SA và audience `sts.amazonaws.com`. Guard có finding trên. |
> | 2. Endpoint S3 | Hai bucket bổ sung chỉ có `GetObject`, không thêm quyền ghi ra ngoài. Check 7 chặn action ghi và resource ngoài allowlist, nhưng kiểm **tập con**, chưa bắt buộc đủ đúng 4 bucket. Nó chỉ kiểm kiểu chuỗi của ResourceAccount; điểm này đã có ở base. |
> | 3. GitOps | Chart version và digest được pin; requests có prune/selfHeal/allowEmpty, platform không prune. Teardown hợp lý khi hết instance/MR/bucket trước, rồi dừng root trước app con. |
> | 4. Evidence | DRF37 có quan sát tương ứng cả 5 kịch bản §4, trong các giới hạn audit đã nêu. Không coi đây là bằng chứng Golden Path hoàn chỉnh hoặc P3 đã đóng mọi gate. |
> | 5. Dữ liệu nhạy cảm | Không phát hiện account ID/ARN thật, IP công khai thực tế hoặc tên bucket state thật trong snapshot ứng viên. Các match là mock, địa chỉ tài liệu/private hoặc placeholder. |
>
> **Lệnh đã chạy và kết quả**
>
> - `git status --short`, `git rev-parse HEAD`, `git diff`, `git show`, `git grep`, `rg`: đối chiếu revision, mã và dữ liệu nhạy cảm.
> - `terraform test -no-color`: **20 passed, 0 failed**.
> - `bash --noprofile --norc gitops/check.sh`: **PASS**.
> - Python/jq đọc nguyên biểu thức check 7/13 và thử JSON trong bộ nhớ: tái hiện finding; không sửa source.
>
> **Giới hạn:** HEAD hiện tại là `84103ed`; đã xác nhận các file mã/test/runbook được kiểm không khác ứng viên. Lần chạy sandbox ban đầu lỗi khởi động Bash/provider; chạy lại ngoài sandbox thành công. Chỉ review nguồn và evidence đã ghi, không xác minh AWS/cluster/billing trực tiếp. Git cuối phiên sạch; không sửa file, không commit, không ghi Linear/PR.

**Xử lý (Claude, PR #31):**
- Finding MEDIUM: đã sửa (mục 3, #7).
- Ý "check 7 chỉ kiểm tập con": cũng đã sửa.
- Ý "chỉ kiểm kiểu chuỗi của ResourceAccount": giữ nguyên, vì đã có từ P2, ngoài phạm vi P3. Ghi lại để làm cùng lúc làm lại R1.
- Codex chưa review lại bản sửa.

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

Câu 3–6: chưa trả lời ở lần này.

**Lần 2 (14/11/2026, sau khi owner đổi ý).** Câu 1–2 được gõ trong chat; câu 3–6 là một khối dán. Nguyên văn:

> 1. TEach back
> 2. argo cd (app zdr-request) đọc commit  cff3ac9 và apply instance storageappspike/spike bằng chứng annotation argocd.argoprọ.io/tracking-id: ... kro đọc rgd sinh ra bucket mr, có nhãn kro.run và kro.run/node-id provider aws s3 của crossplane lấy credential qua irsa rồi gọi aws tạo bucket
> 3. 2 argo xanh instance chưa ready argo synced/healthy chỉ nói clustẻ khớp với git. instance ở in progres, ready = false , chờ node bucket thoả reađwehn mr có synced= falsse ; describe cho thấy lỗi thật aws web identity token file must be set, còn log provider gần nhu ưtrống chưa có deployment vì kro chỉ tạo node phụ thuộc sau khi bucket ready
> 4.  3. xoá instance
>
> 3a, kubectl delete: sau khoảng 15 giây instance và MR quay lại (AGE mới), vì selfHeal của Argo apply lại từ Git. Trên EKS, bucket thật sẽ bị xóa rồi tạo lại rỗng.
> 3b, xóa qua Git: Argo prune instance, kro xóa MR, Crossplane xóa bucket AWS vì managementPolicies: "*" (DRF37: sau 17 giây ra Not Found).
> Crossplane và provider vẫn chạy, vì app nền tảng có prune: false.
>
> 4. Credential và giới hạn
> DRC gắn annotation eks.amazonaws.com/role-arn lên SA provider-aws-s3. Trên EKS, Pod Identity Webhook chèn AWS_ROLE_ARN và token vào pod, rồi STS đổi token lấy credential tạm. Kind không có webhook này nên jq ra false. Hai lớp chặn:
>
> Trust policy chỉ cho đúng một SA, aud sts.amazonaws.com.
> Permissions policy chỉ cho action S3 mức bucket trên zero-drift-p3-*, không có IAM. Đổi thành * thì terraform test fail, còn trên EKS bucket ngoài prefix bị AccessDenied.
>
> 5. Thứ tự gỡ
> Ở phần 5, xóa provider trước làm CRD buckets biến mất. Instance kẹt vì kro.run/finalizer (không list được bucket), ProviderConfig kẹt vì in-use.crossplane.io với users=1. Trên EKS, nếu bucket thật còn thì không controller nào gọi DeleteBucket nữa. MR kẹt Terminating, hoặc bị gỡ finalizer bằng tay, và bucket thành orphan, vẫn tốn tiền.
>
> 6. Role vs bucket
> Role là hạ tầng của controller. Nó phải có trước khi provider chạy, và sống cùng cluster, nên Terraform quản lý (module p3_provider_irsa). Bucket là tài nguyên do người dùng yêu cầu qua Git (kind: Bucket trong RGD): sinh ra và mất đi theo từng instance, nên Crossplane quản lý. Lúc gỡ admin vẫn giữ enable_p3_provider_role=true, vì bỏ biến đó thì plan sẽ xóa role trong khi provider có thể vẫn cần nó để dọn bucket. Thực tế plan chỉ 1 to destroy, là access policy của admin.

### 6.3 Nhận xét (Claude, so với output owner đã dán)

- **Câu 1:** thứ tự Git → Argo → instance → MR → provider → AWS qua IRSA là đúng. Sai vai trò: **kro** (không phải Crossplane) đọc RGD và sinh Bucket MR; Crossplane provider reconcile MR rồi gọi AWS. Bằng chứng Argo apply instance là annotation **Argo** `argocd.argoproj.io/tracking-id`, không phải annotation kro. Nhãn trên MR là `kro.run/instance-name: spike` và `kro.run/node-id: bucket`.
- **Câu 2:** câu đầu đúng (Argo chỉ so cluster với Git). Thứ tự xem đúng. Giá trị ghi lại sai so với output: instance `IN_PROGRESS`/`Ready=False` (không phải "sync"); MR `SYNCED False` (không phải healthy). Thiếu: kro chờ `readyWhen` của node `bucket` nên chưa tạo Deployment; lỗi đọc ở status/events của MR, log provider gần như im lặng.
- **Câu 3–6 (lần 1):** không có câu trả lời nên không đánh giá. Lab đã cho đủ dữ liệu (phần 3–6 ở 6.1).

Nhận xét lần 2:
- **Câu 1 (bản sửa): đúng.** Argo đọc `cff3ac9`; bằng chứng là `argocd.argoproj.io/tracking-id`. kro đọc RGD và sinh MR mang nhãn `kro.run/*`. Provider của Crossplane lấy credential qua IRSA rồi gọi AWS.
- **Câu 2 (bản sửa): đúng và đủ.** Nêu được: instance `IN_PROGRESS`/`Ready=False`; kro chờ `readyWhen` của node bucket; MR `Synced=False`; lỗi thật nằm ở describe; log provider gần như trống; chưa có Deployment vì còn phụ thuộc bucket.
- **Câu 3: đúng.** Phân biệt được selfHeal (3a) với prune qua Git (3b), nêu `managementPolicies: "*"` và bằng chứng EKS (bucket mất sau 17 giây).
- **Câu 4: đúng.** Đủ chuỗi DRC → SA → webhook → STS và hai lớp chặn trust/permissions. Thiếu một điểm: sau review Codex, guard chỉ nhận đúng danh sách action (mục 3, #7).
- **Câu 5: đúng** với quan sát ở phần 5, nêu cả hai đường dẫn tới bucket orphan.
- **Câu 6: đúng.** Có thêm một suy luận đúng: giữ role vì provider có thể còn cần nó để dọn bucket.

### 6.4 Mức đạt

- Argo CD, kro, Crossplane: **`PRACTICED`** (lab có output 14/11).
- Lần 1: `EXPLAINED` chưa đạt.
- Lần 2: **`EXPLAINED`**. Đủ 6 câu, khớp với output lab, trong giới hạn ở 6.5.

### 6.5 Giới hạn về nguồn gốc câu trả lời

- Câu 1–2 lần 2 do owner gõ trực tiếp (có lỗi gõ).
- Câu 3–6 là một khối dán: không có lỗi gõ, và cách diễn đạt sát phần giải thích Claude viết trong phiên (ví dụ câu 3a, câu 4). Claude không xác minh được khối này do owner tự viết.
- Câu 6 có một suy luận mà Claude không đưa ra (giữ role để provider còn dọn bucket).
- Owner là người chấp nhận đóng P3. Nên hỏi lại miệng câu 3–5 khi diễn tập bảo vệ (P11).
