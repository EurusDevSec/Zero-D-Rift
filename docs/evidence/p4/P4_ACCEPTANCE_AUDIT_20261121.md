# DRF-57 (P4-T4.2): bản audit nghiệm thu P4 (bản nháp 21/11/2026)

- SPEC: `.agent/specs/SPEC-P4_RAG_SANDBOX.md` §4, §7, §8.
- Window: `P4-L3-20261121-01`.
- Revision ứng viên: `main` = `5e5067f` (merge PR #54).
- Đã che: account ID, ARN, IP, endpoint RDS, tên bucket state.
- Codex đã review bản nháp theo mục 4: REQUEST CHANGES (mục 5). Các sửa ở mục 5.1 đã merge (PR #55–#57).
  Codex review lại ngày 22/11: REQUEST CHANGES, 2 MEDIUM, 2 LOW (mục 5.2); xử lý ở mục 5.3.
  Codex kiểm bản sửa ở `70ad8d8`: APPROVE, không finding mới (mục 5.4).
  Mục 6 (inventory trễ, Bills) điền ngày 22/11.

## 1. Quy tắc hoàn thành P4 (SPEC §8)

| Điều kiện | Trạng thái |
|---|---|
| Mọi kịch bản §4 có evidence L3 trên EKS | **Đạt có giới hạn**: 7/7 kịch bản có evidence L3. Dòng `sts` do owner tự gõ (DRF-56 C) đã có ở window xác nhận 22/11 (`P4-T4.2_L3_CONFIRM_20261122.md`, V4). Còn một giới hạn: kịch bản 6 chỉ đạt một phần, vì nguyên nhân lỗi retry được gỡ bằng `kubectl`, không qua Git (C7) |
| Teardown sạch | **Đạt** 21/11 và 22/11: mỗi lần `65 destroyed`, state 0, `inventory.sh` `RESULT: CLEAN` |
| Inventory trễ sạch | **Đạt** 22/11 02:44Z: owner chạy với MFA, `RESULT: CLEAN`. Chỉ mục tag đã hết lệch (mục 6) |
| Đã đọc billing | **Một phần**: owner đọc trang Credits ngày 22/11 (ước tính, dùng 0,55 USD cả tài khoản). Window xác nhận ước tính thêm khoảng 0,37 USD. Bills gross chưa đọc: đọc một lần cho cả hai window, khi số ước tính đã cập nhật (mục 6) |
| Review độc lập ghi findings và giới hạn | **Đạt**: Codex review lần 1 (1 HIGH, 6 MEDIUM, 3 LOW, mục 5); đã sửa cả 10 (mục 5.1). Review lại 22/11: C1, C5, C6 sửa một phần; 2 MEDIUM, 2 LOW mới (mục 5.2), xử lý ở mục 5.3. Codex kiểm bản sửa `70ad8d8`: **APPROVE**, không finding mới; đồng ý giữ `GetBucketLocation` làm giới hạn LOW (mục 5.4). Sau đó `fec7847` siết thêm `cleanup` theo review Copilot, Codex chưa kiểm (mục 5.4) |
| Owner `PRACTICED` + `EXPLAINED`: IRSA workload, luồng secret, tầng credential PostgreSQL | **Đạt có giới hạn**: IRSA đạt đầy đủ; hai mục kia có giới hạn nguồn gốc (`P4-T4.2_TEACHBACK_20261121.md`) |

## 2. Kịch bản §4 → evidence

Viết tắt: **W** = `P4-T4.1_L3_WINDOW_20261121.md` (L3 trên EKS), **K-DB** = `P4-T2.1_L2_KIND_DB_20261119.md`, **K-G** = `P4-T3.2_L2_KIND_GRAPH_20261119.md`, **TF** = `P4-T2.2_TERRAFORM_RAG_20261119.md`.

| Kịch bản | Mệnh đề | Evidence | Tầng |
|---|---|---|---|
| 1. Shared service chuẩn bị một lần, riêng tư | không public; 5432 chỉ từ SG node | W: RDS describe `public false`; `plan_assert` khoá SG một rule (TF, cổng trước apply W) | L3 cấu hình + plan |
| | pgvector cài một lần bởi Job init | W: `db-init` `vector_version 0.8.2`; `probe platform` `pgvector 0.8.2` | L3 |
| | không request nào tạo, sửa hay xoá RDS | RGD không có resource RDS; ClusterRole `kro-zdr-p4-children` chỉ cho configmaps (đọc), SA, Service, Job, Deployment, `s3.aws.m.upbound.io/buckets`, không có API group RDS; chỉ cài provider S3; plan chỉ có 1 `aws_db_instance` do Terraform sở hữu | tĩnh + plan |
| 2. Một request cho một sandbox dùng được | kro tạo bucket, Job, SA, Deployment, Service | W: thứ tự Job 08:48:16 → Bucket, SA, Service 08:48:22 → Deployment 08:48:24 | L3 |
| | Job tạo một schema và một login role | W: log bootstrap `role_created, schema_created` (retry); `probe sandbox` đọc schema | L3 |
| | Ready chỉ sau khi app truy vấn schema và tới bucket | W: `/readyz` `{'bucket': 'ok', 'db': 'ok', 'ready': True}`; readinessProbe `/readyz` | L3 |
| | status có endpoint, schema, bucket, secretName, không có giá trị secret | W: JSON status của cả hai instance | L3 |
| | kiểm độc lập ngoài Pod app PASS readiness và truy vấn vector | W: `probe sandbox` ×2 (và `retry`), 6/6 mỗi lần | L3 |
| 3. Readiness không giả | request sai bị chặn trước merge | W: G3 (`docs--qa`) và G2 lớp 1, CI `static-gates` đỏ | CI |
| | các request khác không bao giờ Ready trong khi Argo Synced | W: G2 lớp 2 (`IN_PROGRESS Failed`, Argo `Synced/Healthy`); H lần 0 (`IN_PROGRESS Failed`) | L3 |
| | tầng hỏng hiện ở instance, Job, Pod hoặc managed-resource status | W: conditions `ResourcesReady`; log Job (`invalid input…`, `NoCredentialsError`) | L3 |
| 4. Credential bị giới hạn | Pod app chỉ đọc secret tenant mình, chỉ dùng role sandbox | Secret: W `probe sandbox` đọc được secret của mình; G1 secret tenant kia và secret bootstrap `AccessDeniedException`. Bucket: micro-lab `OWN_OK` / `OTHER_DENIED` | L3 |
| | role sandbox không `CREATE ROLE`, không đọc schema khác, không làm bootstrap | W: G1 `42501` ×3 mỗi chiều | L3 |
| | bootstrap không phải superuser, không đọc được master | W: `probe platform` `super=False`, master `AccessDeniedException`; `rag_iam_check --principal` PASS | L3 |
| | Pod tenant không lấy được credential node từ IMDS | W: G1 `IMDS timed out` ×2; H lần 0 `NoCredentialsError` | L3 |
| 5. Tenant tách nhau trên data plane | tenant-a không đọc được schema, secret, bucket của tenant-b, và ngược lại | W: G1 cả hai chiều 7/7 | L3 |
| | mỗi đường được phép vẫn chạy | W: `probe sandbox` cả hai tenant PASS trước G1 (08:49); sau cleanup chỉ ghi `tenant-b/docs-qa` PASS (09:22) | L3 |
| 6. Xoá, retry, cleanup dự đoán được | Job mới chạy, thành công, request Ready sau khi sửa trong Git và tăng `bootstrapAttempt` | W: H (PR #50, #51); `boot-1` Complete; `ACTIVE`; probe PASS. Phần qua Git là tăng attempt. Nguyên nhân (identity bootstrap) được gỡ bằng `kubectl` ở phía nền tảng, nên chưa chứng minh "sửa nguyên nhân trong Git" | L3, một phần |
| | không đổi mật khẩu đang có | K-DB dòng 51: chạy lại khi secret còn thì `password_changed false`. Trên EKS ca này **không xảy ra**: lần 0 chưa tạo gì, nên lần 1 tạo role mới (`password_changed true` là đúng) | L2 kind |
| | không sửa hay xoá tay object nào trong cluster | W: không object nào của request bị sửa tay. Có một thay đổi tay: `bootstrap-identity on` sửa annotation của ServiceAccount `rag-bootstrap` bằng `kubectl` | L3, một phần |
| | xoá request + cleanup: object, bucket, schema, role, secret đều hết | W: I (`HeadBucket` 404, `role_dropped, schema_dropped, secret_deleted`, `ResourceNotFoundException`) | L3 |
| | sandbox còn lại vẫn chạy | W: `probe sandbox tenant-b docs-qa` PASS sau cleanup | L3 |
| 7. Teardown đủ | xoá theo thứ tự sandbox → controller → RDS + EKS | W: phần Teardown, 09:22:51–09:39:49 | L3 |
| | inventory không còn gì ngoài allowlist; không còn RDS, snapshot, secret, bucket, role P4 | W: inventory 2 lần `CLEAN`, mọi bộ đếm P4/RDS = 0. Chỉ mục tag cập nhật chậm, kiểm lại ở mục 6 | L3 |

## 3. Phát hiện và giới hạn

Từ window (chi tiết ở W, mục "Phát hiện"):
- **F1:** `NoRegionError`. Lần sửa duy nhất được phép là PR #46 (`AWS_DEFAULT_REGION`). Lab kind không bắt được lỗi này vì dùng file backend.
- **F3:** G2 bị CI chặn trước, và `main` không có branch protection. Merge vẫn được dù CI đỏ, nên lớp CI chỉ là cảnh báo.
- **F4:** IRSA khi `automountServiceAccountToken: false` chạy được.
- **F5:** lệnh micro-lab trong runbook làm lộ account ID ở câu lỗi, và `-i` làm mất các dòng đầu.

Giới hạn:
- **L1.** Window 21/11 không giữ được dòng `sts get-caller-identity` do owner tự gõ. Owner chọn window ngắn: dòng đó đã có ở `P4-T4.2_L3_CONFIRM_20261122.md` V4 (`assumed-role/zero-drift-rag-tenant-a/…`). **Đã đóng.**
- **L2.** H1 chỉ là **smoke** (một lần, ranh giới âm 12); trial chính thức ở P9.
- **L3.** "Không tới được từ ngoài" chỉ kiểm bằng cấu hình (ranh giới âm 6).
- **L4.** Ca "retry không đổi mật khẩu đang có" chỉ có ở L2 kind.
- **L5.** Câu duyệt window là nút "Duyệt window" trả lời câu hỏi có RunId, không phải nguyên văn câu mẫu.
- **L6.** Teach-back: câu 3, 4, 6 có giới hạn nguồn gốc. Câu 6c và `boot-0` lần đầu là khối dán. Nguyên nhân `propagationPolicy` chưa xác minh.
- **L7.** Runbook `P4_RAG_SANDBOX.md` chưa ghi F3 (lớp CI ở G2) và F5 (lệnh micro-lab). Sửa cùng các finding của review.

Phiên bản dùng trong window:
- EKS 1.35 (node `v1.35.9-eks`);
- RDS PostgreSQL 17.11, `db.t4g.micro`; pgvector 0.8.2;
- kro 0.9.4; Argo CD v3.5.7; Crossplane và provider pin như VERSION_MATRIX §7;
- image `rag-sandbox@sha256:512e982a…` (VERSION_MATRIX §8);
- aws-cli `2.42.1` (`public.ecr.aws/aws-cli/aws-cli@sha256:b0102d22…`).

## 4. Yêu cầu review độc lập (cho Codex)

- **Ứng viên:** base `7dcaa44` (merge PR #33, SPEC-P4 đã được Codex review ở `358da73`), head `5e5067f`. Gồm 101 file, PR #34–#54 (PR #48 đóng không merge).
- **Đọc trước:**
  - SPEC-P4 §1 (ranh giới âm), §4, §5 P4-T4, §8;
  - ADR-0008;
  - `docs/runbooks/P4_RAG_SANDBOX.md`;
  - evidence W, K-DB, K-G, TF, `P4-T3.1_APP_IMAGE_20261119.md`, `P4-T4.2_TEACHBACK_20261121.md`, và file này.
- **Câu hỏi cần trả lời:**
  1. **IAM** (`infra/terraform/modules/rag-identity/`): policy của role tenant có đường tới secret, bucket hay prefix của tenant khác, tới secret bootstrap hoặc master không? Trust có chỉ đúng SA và audience không? `rag_iam_check.sh` có đủ chặt không?
  2. **PostgreSQL** (`workloads/rag-sandbox/src/ragsandbox/`): `db-init`, `bootstrap`, `cleanup` có cấp thừa quyền không (`CREATEROLE` của bootstrap, `GRANT` cho role sandbox, `search_path`, `PUBLIC`)? `cleanup` có xoá nhầm sandbox khác được không?
  3. **RGD và GitOps** (`gitops/platform/rgd/rag-sandbox.yaml`, `gitops/requests/`, `gitops/check.sh`): readiness có thể báo Ready giả không? Cổng `platformConfig` có bị vượt được không? Rule của CI có chặn đủ tên sai và namespace không có role không?
  4. **Script window** (`infra/p4-window/window.sh`, `probe.py`): có in hoặc ghi secret, endpoint, ARN ra output không? Probe có thể PASS khi đường lẽ ra bị chặn lại đi được không (ví dụ lỗi mạng bị đếm là "denied")?
  5. **Evidence:** W và file này có kết luận vượt quá dữ liệu không, nhất là bảng mục 2?
  6. **Lộ thông tin:** có account ID, ARN, IP, endpoint hay tên bucket state trong Git không?
- **Giới hạn đã biết** (không cần báo lại): L1–L7 ở mục 3; R1 least-privilege của role Terraform vẫn hoãn từ P3; `main` không có branch protection.
- **Ghi kết quả:** reviewer, revision, verdict, findings kèm mức độ, lệnh đã chạy, giới hạn. Owner dán vào chat; Claude ghi nguyên văn vào mục 5 qua PR.

## 5. Kết quả review độc lập

Owner chạy Codex ("codex gpt 6.2 astra") theo mục 4, rồi dán kết quả vào chat ngày 21/11/2026.
- Claude ghi nguyên văn bên dưới. Chỉ đổi các link tuyệt đối trên máy thành đường dẫn trong repo `path:dòng`.
- Bản audit được review có blob `19e9fdda`; `VERSION_MATRIX.md` có blob `4b1e0996`. Cả hai khớp working tree lúc dán.

> Verdict — REQUEST CHANGES. Reviewer: Codex. Tôi đã review `7dcaa44dbaf8078d5fd98a86e377d6e7bc404a0b..5e5067f2ba255a94b9d65df385e663cae6978bf9` cùng hai bản chưa commit của audit (`19e9fdda`) và `VERSION_MATRIX.md` (`4b1e0996`).
>
> 1. IAM. Trong policy Terraform, hai role tenant chỉ đọc secret, bucket và object theo prefix của chính tenant. Tôi không thấy đường tới tenant kia, bootstrap hoặc master. Trust khóa đúng OIDC, audience `sts.amazonaws.com` và subject theo D6.
>
> * MEDIUM — Role Crossplane dùng `s3:GetBucket*` trong khi ADR-0008 yêu cầu liệt kê action cụ thể. Test hiện cũng chấp nhận wildcard này. Thay bằng các action provider cần và cập nhật kỳ vọng của test. Finding này thuộc role Crossplane, không phải bằng chứng tenant đọc chéo. `infra/terraform/modules/rag-identity/main.tf:121` · `.agent/adr/ADR-0008_P4_SHARED_RDS_OWNERSHIP_SECRETS_AND_WORKLOAD_IAM.md:81`
> * LOW — Ma trận của `rag_iam_check.sh` kiểm tenant-a bị từ chối đọc bootstrap và master nhưng thiếu hai dòng tương ứng cho tenant-b. Thêm hai dòng `implicitDeny` là đủ để script cũng kiểm được trường hợp quyền thực tế của riêng tenant-b bị nới. `infra/terraform/tests/rag_iam_matrix.json:35`
>
> 2. PostgreSQL. `CREATEROLE` của bootstrap đúng D4. Role sandbox chỉ được `CONNECT` vào `rag`, `USAGE, CREATE` trên schema riêng. Tên schema, role và secret dẫn xuất từ cặp tenant/name đã kiểm tra. Tôi không thấy va chạm tên khiến `cleanup` của sandbox này nhắm sang sandbox khác.
>
> * LOW — Bootstrap được `CREATE ... WITH GRANT OPTION` trên database, trong khi chỉ cần `CREATE` để tạo schema. Quyền cần cấp tiếp cho sandbox là `CONNECT`. Tách hai quyền và chỉ giữ `WITH GRANT OPTION` cho `CONNECT`. `workloads/rag-sandbox/src/ragsandbox/statements.py:105`
>
> 3. RGD và GitOps. RGD hiện tại đợi `platformConfig`, Job của đúng attempt `Complete=True`, bucket `Ready=True` và replica qua `/readyz`. Có hai chỗ ảnh hưởng trực tiếp đến nghiệm thu.
>
> * MEDIUM — Nếu secret của request chứa credential hợp lệ nhưng của sandbox khác, app seed và kiểm `current_schema()` của kết nối đó. Khi bucket đúng vẫn truy cập được, `/readyz` có thể trả 200 dù app đang phục vụ sai schema. So `current_user` và `current_schema()` với định danh dự kiến của request trước khi seed. `workloads/rag-sandbox/src/ragsandbox/serve.py:251` · `workloads/rag-sandbox/src/ragsandbox/serve.py:303`
> * MEDIUM — CI chỉ đọc `*.yaml`, còn Argo cũng đồng bộ `.yml` và `.json`. Request sai tên hoặc namespace ở hai dạng đó sẽ lọt qua kiểm tra trước merge. Ngoài ra, trong thư mục request, rule kiểm `RAGSandbox` bỏ qua kind khác, kể cả `platform-config` vốn chỉ được tạo trong window sau `db-init`. Đồng bộ tập file CI kiểm với Argo và chặn ConfigMap dành riêng cho window trong nguồn GitOps. `gitops/check.sh:15` · `gitops/check.sh:140` · [Argo CD 3.5 Directory](https://argo-cd.readthedocs.io/en/release-3.5/user-guide/directory/)
>
> 4. Script window và probe. Các ca âm Secrets Manager/S3 yêu cầu mã từ chối, còn SQL yêu cầu `42501`. Lỗi kết nối thông thường không được tính là PASS ở các ca này.
>
> * HIGH — `cleanup` coi mọi lỗi của `kubectl get ragsandbox` như request đã biến mất. Nếu lần đọc bị `Forbidden` hoặc timeout nhưng bước tạo Job vẫn chạy được, cleanup có thể xóa schema, role và secret của sandbox còn hoạt động. Chỉ tiếp tục khi lệnh đọc thành công và xác nhận `NotFound`; mọi lỗi đọc khác phải dừng. `infra/p4-window/window.sh:242`
> * MEDIUM — Với secret `{}`, cả `probe platform` và `probe sandbox` ghi nhận đã đọc được credential rồi thoát trước các kiểm tra còn lại. Tôi đã kiểm cục bộ bằng store giả: cả hai trả exit 0, `RESULT: PASS (0 failed)`. Yêu cầu đủ `username` và `password` trước khi ghi PASS. Nhánh IMDS cũng nên chỉ chấp nhận timeout dự kiến, vì hiện mọi exception ngoài `HTTPError` đều được tính PASS. `infra/p4-window/probe.py:110` · `infra/p4-window/probe.py:147` · `infra/p4-window/probe.py:209`
> * MEDIUM — `window.sh db-init` truyền ARN thật làm `MASTER_SECRET_ID`. Khi secret thiếu hoặc thiếu trường, `require()` đưa nguyên ID vào `RuntimeError`, rồi CLI và `wait_job` in ra log. Kiểm bằng ID giả xác nhận ID còn nguyên sau `safe_reason`. Dùng nhãn `master secret` trong thông báo lỗi này. `workloads/rag-sandbox/src/ragsandbox/secretstore.py:55` · `infra/p4-window/window.sh:181`
>
> 5. Evidence. Giá trị pgvector `0.8.2` trong `VERSION_MATRIX` có kết quả truy vấn L3 ở W hỗ trợ. Hai kết luận trong bảng nghiệm thu cần thu hẹp theo dữ liệu đã ghi.
>
> * MEDIUM — Scenario 6 được ghi là không sửa tay object nào trong cluster. W ghi rõ trước attempt 1, `bootstrap-identity on` đã sửa annotation của ServiceAccount bằng `kubectl`. Đủ bằng chứng rằng tăng attempt qua Git tạo Job mới và request về `ACTIVE` sau khi khôi phục identity. Chưa đủ để ghi rằng cả nguyên nhân lỗi được sửa qua Git theo SPEC. Sửa cách ghi ở W và bảng §2. `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md:45` · `docs/evidence/p4/P4-T4.1_L3_WINDOW_20261121.md:157` · `infra/p4-window/window.sh:212`
> * LOW — Audit ghi cả hai tenant PASS trước và sau G1. W ghi cả hai trước G1, nhưng sau cleanup chỉ ghi `tenant-b/docs-qa` PASS. Sửa câu theo hai mốc đã giữ. Ở dòng 37, `OWN_OK/OTHER_DENIED` kiểm bucket; bằng chứng cho secret là `probe sandbox` và G1. `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md:42` · `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md:37` · `docs/evidence/p4/P4-T4.1_L3_WINDOW_20261121.md:78`
>
> 6. Lộ thông tin trong Git. Không phát hiện account ID, ARN, IP hạ tầng, endpoint RDS, tên bucket state hoặc credential thật trong 102 đường dẫn thuộc phạm vi. Các kết quả khớp đã đối chiếu là fixture, placeholder hoặc địa chỉ công khai/hệ thống. Finding về ARN ở mục 4 là đường in lỗi khi chạy.
>
> Lệnh đã chạy. `git status --short`, `git rev-parse`, `git diff --stat`, `git diff --check` cho range và `VERSION_MATRIX.md`, `git hash-object --no-filters`, `rg -n`, `Get-Content`, `bash gitops/check.sh` (PASS), cùng Python cục bộ để quét định danh và kiểm hai trường hợp lỗi bằng dữ liệu giả.
>
> Giới hạn review. Đây là review chỉ đọc trên mã, manifest và evidence đã lưu. Tôi không chạy lệnh AWS, không chạy lại EKS/RDS, không sửa file và không commit.

### 5.1. Xử lý từng finding

| # | Mức | Finding | Sửa | Test âm |
|---|---|---|---|---|
| C1 | HIGH | `cleanup` coi mọi lỗi đọc là `NotFound` | `window.sh cleanup` chỉ đi tiếp khi lệnh đọc báo `(NotFound)`. Còn object, hoặc mọi lỗi đọc khác (Forbidden, timeout, thiếu CRD), đều dừng. Review PR #55: lệnh đọc và Job không nguyên tử, và Job không có token Kubernetes để tự kiểm. Nên sau Job, script đọc lại: nếu request đã xuất hiện lại thì báo lỗi, kèm cách khôi phục (tăng `bootstrapAttempt`). Đây là phát hiện, không phải chặn | `infra/p4-window/tests/cleanup_guard.sh`: kubectl giả, 6 ca; chỉ `notfound` và `reappear` được tới `apply`; `reappear` phải thoát khác 0. Code cũ FAIL 3 ca; bản trước review PR #55 FAIL ca `reappear` |
| C2 | MEDIUM | probe PASS với secret `{}`; IMDS nhận mọi exception | `probe.py`: credential phải có `username` và `password` không rỗng mới tính PASS. IMDS chỉ nhận timeout (`TimeoutError`, `socket.timeout`, `URLError` vì timeout) | `infra/p4-window/tests/run_probe_tests.sh`: 16 PASS. Code cũ FAIL 15, gồm secret `{}` và IMDS `ConnectionRefused` |
| C3 | MEDIUM | ID master secret lọt vào thông báo lỗi | `require(..., label="master secret")`: thông báo lỗi chỉ in nhãn, không in ID | `test_require_label_hides_the_name`, `test_db_init_error_does_not_print_master_secret_id` |
| C4 | MEDIUM | `/readyz` không kiểm `current_user`/`current_schema()` so với request | App so `current_user`, `current_schema()` với `sandbox_<tenant>_<name>` trước khi seed. Định danh dự kiến lấy từ `SECRET_ID` và phải khớp `SANDBOX_TENANT`/`SANDBOX_NAME` mà RGD truyền vào | Test đơn vị trong `test_serve.py`; `test_4c_serve_refuses_another_sandboxs_credential` trên pgvector thật. Code cũ: 12 test FAIL |
| C5 | MEDIUM | CI chỉ đọc `*.yaml`; không chặn kind khác trong requests | `gitops/check.sh` đọc `.yaml`, `.yml`, `.json`. Rule 8b: `requests/` (trừ `disabled/`) chỉ chứa `RAGSandbox`; không có ConfigMap `platform-config` ở đâu trong Git | `gitops/tests/check_guards.sh`: 4 ca mới (tên sai `.yml`, thiếu tenant `.json`, ConfigMap trong requests, `platform-config` trong Git). `check.sh` cũ cho qua cả 4 |
| C6 | MEDIUM | role Crossplane dùng `s3:GetBucket*` | Bỏ `s3:GetBucket*`, thay bằng 10 action `GetBucket…` mà hàm `Read` của `aws_s3_bucket` gọi (fork upbound `d7cd6f2fe022`, dùng trong provider-aws-s3 v2.8.1). `plan_assert` check 16 giờ chặn mọi action có `*`. **Chưa chạy trên AWS**: window sau phải xem bucket `Ready`/`Synced` và xoá được | Guard `crossplane-GetBucket-star` FAIL (code cũ PASS); `terraform test` có assert "không wildcard"; ma trận: `GetBucketPublicAccessBlock` `implicitDeny`, `GetBucketObjectLockConfiguration` `allowed` |
| C7 | MEDIUM | kịch bản 6 ghi quá: "không sửa tay" | W phần H, runbook mục H và §2 kịch bản 6: phần qua Git là tăng attempt; nguyên nhân được gỡ bằng `kubectl` (`bootstrap-identity on`). Kịch bản 6 ghi "một phần" | — |
| C8 | LOW | ma trận IAM thiếu 2 dòng tenant-b | Thêm 2 dòng `implicitDeny` cho tenant-b: secret bootstrap và master | Ma trận chạy trong `terraform test` (offline) và `rag_iam_check.sh` (sau apply) |
| C9 | LOW | `CREATE … WITH GRANT OPTION` thừa | Bootstrap có `CONNECT … WITH GRANT OPTION` và `CREATE` không kèm grant option. Có thêm `REVOKE GRANT OPTION FOR CREATE` cho DB đã cấp theo cách cũ | `test_6b_bootstrap_cannot_pass_on_create_database` trên pgvector thật; `test_statements.py` |
| C10 | LOW | audit ghi PASS sau G1 cho cả hai tenant; dòng 37 trộn bucket với secret | §2 kịch bản 5 ghi đúng hai mốc: cả hai tenant trước G1; sau cleanup chỉ `tenant-b/docs-qa`. Kịch bản 4 tách bằng chứng secret (probe sandbox, G1) với bucket (micro-lab) | — |

Ngoài phạm vi C6: role P3 `zero-drift-p3-crossplane-s3` vẫn dùng `s3:GetBucket*` (`modules/p3-provider-irsa`). P3 đã nghiệm thu và flag P3 đang tắt. Nếu bật lại P3, sửa theo cùng cách.

Đã kiểm trên AWS ở window xác nhận `P4-L3-20261122-01` (`P4-T4.2_L3_CONFIRM_20261122.md`):
- C9: V1 `create_grant_option=False` PASS;
- C6: V2 bucket `SYNCED/READY`, không `AccessDenied` sau 16 phút; V5 xoá được;
- C4: V3 app image mới Ready, probe 6/6 ×2, đường đúng. Ca từ chối chỉ có ở L2;
- C1: V5 cleanup không báo `reappeared`. Lần đọc sau Job của bản chạy hôm đó bỏ stderr, nên `rc=0` không chứng minh nó thấy `NotFound` (mục 5.3, R1);
- C3: chỉ ở L2.

Ghi chú lịch sử, trước window xác nhận: C3, C4 và C9 nằm trong code app: chúng chỉ có hiệu lực khi RGD pin image build từ commit có bản sửa. Image `512e982a…` của window 21/11 bỏ qua `SANDBOX_TENANT`/`SANDBOX_NAME`. Image `850c77c2…` (build từ `e0c8319`, đã pin ngày 22/11) có đủ ba bản sửa và `smoke.sh` PASS. Window xác nhận `P4-L3-20261122-01` sẽ kiểm chúng trên EKS. C1, C2, C5, C8 chỉ đổi script, test hoặc tài liệu.

### 5.2. Review lại (22/11)

Owner chạy Codex theo câu hỏi Claude soạn (phạm vi `5e5067f..50ddefd`, PR #55–#57), rồi dán kết quả vào chat ngày 22/11/2026.
- Claude ghi nguyên văn bên dưới. Chỉ đổi các link tuyệt đối trên máy thành đường dẫn trong repo `path:dòng`.
- Số dòng theo revision `50ddefd`; các sửa ở mục 5.3 làm lệch số dòng.

> **Verdict — REQUEST CHANGES.** Lỗi HIGH cũ đã được chặn **trước khi tạo cleanup Job**. Còn hai điểm MEDIUM ảnh hưởng trực tiếp đến nghiệm thu: lần đọc **sau Job** có thể báo thành công giả, và CI vẫn bỏ sót một số manifest mà Argo CD sẽ đồng bộ.
>
> **Reviewer:** Codex, độc lập.\
> **Revision:** `5e5067f2ba255a94b9d65df385e663cae6978bf9..50ddefd2c4463a759ac38df6760bfa4ab57fa048` · 34 file · PR #55–#57.
>
> ### Findings
>
> | Mức | Vị trí | Phát hiện và cách sửa |
> |---|---|---|
> | **MEDIUM** | `infra/p4-window/window.sh:258` · `docs/evidence/p4/P4-T4.2_L3_CONFIRM_20261122.md:108` | Sau Job, `kubectl get` bỏ stderr và coi mọi lần đọc lỗi như request đã mất. Mình tái hiện bằng stub: trước Job `NotFound`, sau Job `Forbidden`, **cleanup vẫn trả 0**. Vì vậy V5 chứng minh hai Job hoàn tất, nhưng `rc=0` chưa chứng minh lần đọc cuối thấy `NotFound`. Dùng lại quy tắc trước Job cho lần đọc cuối và thêm đúng ca test này. |
> | **MEDIUM** | `gitops/check.sh:16` · `gitops/check.sh:162` | C5 đã chặn bốn ca được báo lần trước. Tuy nhiên Argo CD v3.5.7 còn đọc `.jsonnet` và bung từng object trong Kubernetes `List`. CI bỏ qua `.jsonnet` và chỉ xét `kind` ngoài cùng, nên vẫn có thể bỏ sót `platform-config` trong nguồn platform. Cách sửa nhỏ nhất là từ chối hai dạng này trong các thư mục đang sync nếu P4 không dùng chúng. [Mã đọc manifest của Argo CD v3.5.7](https://github.com/argoproj/argo-cd/blob/v3.5.7/reposerver/repository/repository.go#L1825) · [Xử lý List](https://github.com/argoproj/argo-cd/blob/v3.5.7/reposerver/repository/repository.go#L1660) |
> | **LOW** | `infra/terraform/modules/rag-identity/main.tf:128` | Allowlist đủ cho đường tạo, observe và xoá đã chạy ở V2/V5. Còn một quyền đọc thừa trên đường này: provider lấy region qua `GetBucketRegion`, SDK gọi `HeadBucket`, và role đã có `s3:ListBucket`. Bỏ `s3:GetBucketLocation` khỏi policy và danh sách kỳ vọng tương ứng. [Provider đã pin](https://github.com/upbound/terraform-provider-aws/blob/d7cd6f2fe022/internal/service/s3/bucket.go#L1695) · [SDK gọi HeadBucket](https://github.com/aws/aws-sdk-go-v2/blob/feature/s3/manager/v1.23.6/feature/s3/manager/bucket_region.go#L78) · [Quyền của HeadBucket](https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadBucket.html) |
> | **LOW** | `docs/evidence/p4/P4-T4.2_L3_CONFIRM_20261122.md:23` | Dòng “P4 đã tiêu trước window ≤ 0,55 USD” biến số Credits ước tính thành cận trên. Phần chi phí cuối file và audit §6 đã ghi đúng. Chỉ cần sửa dòng 23 thành “Credits ước tính 0,55 USD cho cả tài khoản; gross P4 chưa xác minh”. |
>
> ### Đối chiếu C1–C10
>
> | Mục | Kết quả | Test âm và kết quả trên code cũ `5e5067f` |
> |---|---|---|
> | C1 | **Sửa một phần** | Sáu ca hiện có đều qua ở head. Trên base, `Forbidden`, timeout và thiếu CRD vẫn cho tạo Job; request xuất hiện lại cũng không làm script trả lỗi. Ca còn thiếu là lỗi đọc sau Job như finding trên. `infra/p4-window/tests/cleanup_guard.sh:50` |
> | C2 | **Đã sửa** | Probe từ chối credential rỗng hoặc thiếu trường; nhánh IMDS chỉ nhận timeout. Trên base, 8 ca credential và 7 ca IMDS đều đỏ. Riêng 7 ca IMDS gọi trực tiếp hàm phân loại mới, nên trên base chúng đỏ vì thiếu hàm. `infra/p4-window/tests/test_probe.py:34` · `infra/p4-window/probe.py:244` |
> | C3 | **Đã sửa** | `db-init` truyền nhãn `master secret`; lỗi thiếu secret hoặc thiếu trường dùng nhãn này. Hai test đỏ trên base, xanh trên head. EKS ngày 22/11 chỉ chạy đường thành công. `workloads/rag-sandbox/src/ragsandbox/commands.py:44` · `workloads/rag-sandbox/tests/test_commands.py:167` |
> | C4 | **Đã sửa** | App đối chiếu role **và** schema của request trước khi seed. Test đơn vị kiểm sai danh tính trả 503 và chưa chạy `CREATE`/`INSERT`; test cấu hình và danh tính đỏ trên base. Ca credential chéo chạy qua trên pgvector thật ở head. EKS V3 xác nhận đường đúng của hai tenant. `workloads/rag-sandbox/src/ragsandbox/serve.py:256` · `workloads/rag-sandbox/tests/test_serve.py:169` · `workloads/rag-sandbox/tests/test_integration_pg.py:195` |
> | C5 | **Sửa một phần** | Đã chạy lại cả bốn ca mới: `check.sh` cũ cho qua cả bốn, head chặn đúng cả bốn. Phần còn thiếu là `.jsonnet` và `List` nêu trên. `gitops/tests/check_guards.sh:80` |
> | C6 | **Sửa một phần** | Wildcard đã sửa đúng. Check 16 bắt `*` ở mọi vị trí trong action của policy đã biết lúc plan. Cùng ca `s3:GetBucket*`, base báo PASS sai, head báo FAIL đúng. Chỉ còn quyền đọc thừa nêu trên. `infra/terraform/scripts/plan_assert.sh:275` · `infra/terraform/tests/plan_assert_guards.sh:90` |
> | C7 | **Đã sửa phần ghi evidence** | Audit ghi đúng: khôi phục identity bằng `kubectl`, tăng attempt qua Git. Scenario 6 vẫn **một phần**. Đây là sửa kết luận tài liệu, không áp dụng test âm. `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md:44` · `docs/evidence/p4/P4-T4.1_L3_WINDOW_20261121.md:157` |
> | C8 | **Đã sửa** | Đã thêm hai ca `implicitDeny` cho tenant-b đọc secret bootstrap và master. Hai ca này **cũng sẽ qua với policy cũ** vì quyền cũ đã từ chối đúng; lỗi ban đầu là thiếu ca kiểm. `infra/terraform/tests/rag_iam_matrix.json:46` |
> | C9 | **Đã sửa** | Chỉ `CONNECT` còn grant option. `REVOKE GRANT OPTION FOR CREATE` xử lý cả DB từng nhận grant cũ. Test SQL đỏ trên base; integration ở head và V1 đều xác nhận bootstrap có `CREATE` nhưng không cấp tiếp được. `workloads/rag-sandbox/src/ragsandbox/statements.py:105` · `workloads/rag-sandbox/tests/test_integration_pg.py:203` |
> | C10 | **Đã sửa** | Audit đã tách evidence secret và bucket, ghi đúng hai tenant PASS trước G1 và chỉ `tenant-b/docs-qa` có kết quả sau cleanup. Sửa tài liệu, không áp dụng test âm. `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md:38` · `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md:43` |
>
> **Evidence và image.** V1, V2, V3 và V4 có kết quả đúng loại kiểm tra đã mô tả. V5 có hai bucket trả 404 và hai cleanup Job hoàn tất, với giới hạn lần đọc cuối nêu trên. V6 ghi `65 destroyed`, state 0 và inventory sạch ngay sau teardown. Inventory trễ lúc 02:44Z ngày 22/11 thuộc **window 21/11**. Digest `850c77c2…` khớp giữa RGD, manifest lab, registry probe và version matrix. C3 và ca từ chối của C4 chỉ có bằng chứng cục bộ/L2. `docs/evidence/p4/P4-T4.2_L3_CONFIRM_20261122.md:66` · `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md:165` · `docs/VERSION_MATRIX.md:182`
>
> **Lộ thông tin.** Trong 34 file, mình không phát hiện account ID thật, ARN role đầy đủ, endpoint/IP hạ tầng thật, tên bucket state thật hay credential. Có **một ARN S3 nguyên văn của bucket sandbox** trong output V4. ARN đó chứa tên bucket workload đã dùng trong bài thử; không chứa account ID. Vì vậy câu “đã che ARN” ở đầu evidence rộng hơn dữ liệu thực tế. `docs/evidence/p4/P4-T4.2_L3_CONFIRM_20261122.md:101`
>
> **Lệnh đã chạy**
>
> | Lệnh trên head | Kết quả |
> |---|---|
> | `bash gitops/check.sh` · `bash gitops/tests/check_guards.sh` | PASS · 33/33 ca guard |
> | `bash infra/terraform/tests/plan_assert_guards.sh` | PASS trên plan giả lập |
> | `bash infra/p4-window/tests/cleanup_guard.sh` | PASS 6/6 ca có sẵn |
> | `bash infra/p4-window/tests/run_probe_tests.sh` | 20 passed |
> | `bash workloads/rag-sandbox/test.sh --integration` | 138 passed, có PostgreSQL/pgvector thật trong Docker |
> | `git rev-parse`, `git status --short`, `git diff --stat`, `git diff --check`, `git show`, `git log`, `rg`, Python | Xác nhận revision và phạm vi, quét định danh, chạy đối chứng trên base trong thư mục tạm và tái hiện ca sau Job trả `Forbidden` |
>
> **Giới hạn.** Mình kiểm độc lập bằng mã nguồn, test cục bộ và evidence đã lưu. Kết quả EKS và chi phí dựa trên hồ sơ của window; Bills gross vẫn chưa được xác minh. Mình không chạy lệnh AWS, sửa file trong repo hay commit.

### 5.3. Xử lý review lại

| # | Mức | Finding | Xử lý | Test âm |
|---|---|---|---|---|
| R1 | MEDIUM | `cleanup` coi lần đọc lỗi **sau Job** là request đã mất | `window.sh`: hàm `request_state` trả `exists`, `gone` (server báo `NotFound`) hoặc `unknown`. Trước và sau Job dùng cùng quy tắc. Sau Job, `unknown` dừng với "cleanup ran, but cannot confirm … still gone". Evidence V5 thu hẹp: `rc=0` hôm đó không chứng minh lần đọc cuối thấy `NotFound` | `cleanup_guard.sh` thêm `after-forbidden`, `after-timeout` (8 ca). `window.sh` cũ: 2 ca mới FAIL (`exit 0`) |
| R2 | MEDIUM | CI bỏ sót `.jsonnet` và object trong Kubernetes `List` | `gitops/check.sh`: rule 1a từ chối `.jsonnet`/`.libsonnet` trong `bootstrap/ platform/ requests/`; rule 0 từ chối mọi document có `items` dạng list hoặc `kind` kết thúc bằng `List`. P4 không dùng cả hai | `check_guards.sh` thêm 2 ca (35 ca): `platform-config` trong `.jsonnet` và trong `List`. `check.sh` cũ cho qua cả 2 |
| R3 | LOW | `s3:GetBucketLocation` thừa | **Giữ, không sửa trong P4.** Danh sách hiện tại là danh sách đã chạy trên EKS ở V2/V5. Bỏ thêm một action sẽ lại làm bản nghiệm thu khác bản đã chạy, và cần thêm một window để kiểm. Quyền này chỉ đọc region, giới hạn trong prefix bucket sandbox. Ghi là giới hạn đã chấp nhận; bỏ khi có window tiếp theo đụng tới role Crossplane | — |
| R4 | LOW | Evidence dòng 23 coi Credits là cận trên | Sửa thành "Credits ước tính 0,55 USD cho cả tài khoản; gross P4 chưa xác minh" | — |
| R5 | (lộ thông tin) | Câu "đã che ARN" rộng hơn dữ liệu: V4 giữ ARN S3 của bucket sandbox | Evidence ghi rõ: che ARN role đầy đủ; giữ ARN S3 `zero-drift-rag-tenant-b-docs-qa` vì tên dẫn xuất từ tenant/name theo RGD và không có account ID | — |

R1 và R2 chỉ đổi script và CI, không đổi gì đã chạy trên AWS; bản sửa R1 chỉ được kiểm bằng stub.

### 5.4. Codex kiểm bản sửa R1–R5 (22/11)

Owner chạy Codex trên `50ddefd..70ad8d8` (PR #58), rồi dán kết quả vào chat ngày 22/11/2026.
Claude ghi nguyên văn; chỉ đổi link tuyệt đối trên máy thành đường dẫn trong repo `path:dòng`.

> **APPROVE** cho bản sửa DRF-57. Hai finding MEDIUM **R1 và R2 đã được sửa đúng**. Mình đã chạy đối chứng: cả bốn ca test mới đều đỏ trên `50ddefd` và xanh trên `70ad8d8`. Không có finding mới trong phạm vi review.
>
> **Reviewer:** Codex · **Revision:** `50ddefd..70ad8d86e2dc11cd1a3a897149b75f6c8a991ce6` · 7 file. Bản sửa đã được commit trên nhánh `hoang/drf-57-rereview`.
>
> | Mục | Kết quả |
> |---|---|
> | **R1 — cleanup sau Job** | Trước và sau Job dùng cùng quy tắc: chỉ `NotFound` xác nhận request đã mất. Khi lần đọc sau Job gặp `Forbidden` hoặc timeout, bản cũ trả `0`, bản mới trả `1`. Evidence V5 cũng đã ghi đúng rằng bản sửa mới chỉ được kiểm bằng stub. `infra/p4-window/window.sh:271` · `docs/evidence/p4/P4-T4.2_L3_CONFIRM_20261122.md:110` |
> | **R2 — GitOps** | Bản cũ cho qua cả `.jsonnet` và `platform-config` nằm trong Kubernetes `List`. Bản mới chặn cả hai, đúng lý do mà từng test yêu cầu. `gitops/check.sh:20` · `gitops/check.sh:55` |
> | **R3 — IAM** | Mình đồng ý **giữ `s3:GetBucketLocation` trong P4** như một giới hạn LOW. Đây là quyền đọc region trên prefix bucket sandbox; policy hiện tại đúng bản đã chạy V2/V5. R3 không chặn bản sửa này. `docs/evidence/p4/P4_ACCEPTANCE_AUDIT_20261121.md:218` |
> | **R4–R5 — evidence** | Đã ghi đúng `0,55 USD` là Credits ước tính cả tài khoản, gross P4 chưa xác minh. Phần che thông tin cũng ghi rõ ARN role đã được che và ARN S3 của bucket sandbox được giữ lại. `docs/evidence/p4/P4-T4.2_L3_CONFIRM_20261122.md:25` · `docs/evidence/p4/P4-T4.2_L3_CONFIRM_20261122.md:8` |
>
> **Kiểm tra độc lập:** `bash infra/p4-window/tests/cleanup_guard.sh` **8/8**, `bash gitops/tests/check_guards.sh` **35/35**, `bash gitops/check.sh` **PASS**, `git diff --check 50ddefd..70ad8d8` **PASS**.
>
> Review chỉ đọc, dựa trên diff, test cục bộ và evidence đã lưu. Mình không chạy AWS, sửa file hay commit.

Sau APPROVE, Copilot review PR #58 báo: `NotFound` không nêu đúng object (ví dụ discovery cũ trả "the server could not find the requested resource") vẫn bị coi là request đã mất. Commit `fec7847` sửa: `request_state` chỉ trả `gone` khi lỗi nêu `ragsandbox…kro.run` và đúng tên request. `cleanup_guard.sh` thêm 2 ca `apinotfound`, `othername` (13 dòng kiểm); cả hai FAIL trên `70ad8d8`. **Codex chưa kiểm `fec7847`.**

## 6. Inventory trễ và billing (22/11)

Owner chạy trên máy mình, với MFA, profile `zdr-tf`, rồi dán output vào chat. Claude ghi lại, đã che account ID.

**Danh tính:** `arn:aws:sts::<ACCOUNT>:assumed-role/zero-drift-bootstrap/hoang-bootstrap`.

**Inventory** `2026-11-22T02:44:03Z`, `us-east-1`: `RESULT: CLEAN (only the retain allowlist remains)`.
- Mọi bộ đếm đều 0, gồm `eks_clusters`, `rds_instances`, `rds_snapshots_*`, `rds_automated_backups`, `p4_secrets_incl_pending`, `rds_managed_secrets_incl_pending`, `p4_buckets`, `p4_iam_roles`, `vpc_endpoints_live`, `sg_non_default`, `enis`.
- Chỉ còn `s3_buckets=1`, là bucket state (allowlist).
- Chỉ mục tag `Project=Zero-D-Rift` giờ chỉ còn `1 s3:bucket`. Lúc 09:39Z ngày 21/11, nó còn liệt kê SG, rule SG, subnet và endpoint, dù API trực tiếp đếm 0. Độ lệch đó đã hết, đúng như giả thuyết chỉ mục cập nhật chậm.

**Chi phí** (trang Credits, owner đọc 22/11; số ước tính, cập nhật khoảng 24 giờ một lần):

| Mốc | Credit đã dùng (ước tính) | Còn lại |
|---|---|---|
| 21/11, trước window | 0,29 USD | 199,71 USD |
| 22/11, sau window | 0,55 USD | 199,45 USD |

- Chênh lệch **≈ 0,26 USD**. Đó là ước tính cho window 21/11, thấp hơn ước tính D10 là 0,50 USD. Lúc đọc, window mới kết thúc khoảng 17 giờ, nên số này có thể chưa đủ.
- Đây là credit ước tính, không phải Bills gross, nên không chặn trên được chi phí gross. Số còn lại dưới trần 5 USD (D10, gross) **chưa xác minh** cho tới khi đọc Bills. Theo ước tính, coi cả 0,55 USD là của P4, P4 còn khoảng 4,45 USD.
- Bills gross: owner đọc một lần sau window xác nhận `P4-L3-20261122-01`, cho cả hai window.
