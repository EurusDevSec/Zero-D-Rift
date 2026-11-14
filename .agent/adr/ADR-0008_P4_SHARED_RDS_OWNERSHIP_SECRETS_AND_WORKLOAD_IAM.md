---
id: ADR-0008
title: P4 shared RDS ownership, secret integration and workload IAM boundary
status: PROPOSED
date: 2026-11-14
decision_source: SPEC-P4 §9.1 D1, D4, D5, D6, D7 (owner approved 2026-11-14)
authority: DOCUMENTATION_ONLY_NO_AWS
---

# Context and authority

[ADR-0004](ADR-0004_SHARED_RDS_AND_RECOVERY_DATABASE.md) chốt một RDS
PostgreSQL/pgvector dùng chung, chuẩn bị trước, và để `UNVERIFIED` ba việc:
ai sở hữu instance, workload lấy secret bằng cách nào, và ranh giới IAM của
workload (mục 8). [SYSTEM_DESIGN §8](../../docs/architecture/SYSTEM_DESIGN.md)
và [THREAT_MODEL §11](../../docs/security/THREAT_MODEL.md) cũng giữ các dòng đó
ở trạng thái mở.

[SPEC-P4](../specs/SPEC-P4_RAG_SANDBOX.md) đề xuất D1–D12; Codex review ba vòng,
lần cuối APPROVE tại `358da73` (SPEC §9.4). Owner duyệt cả 12 quyết định ngày
14/11/2026 (SPEC §9.1). ADR này ghi lại phần kiến trúc của các quyết định đó ở
một chỗ. Nó không thêm quyết định mới.

Trạng thái `PROPOSED` là chờ owner chấp nhận văn bản ADR. ADR không cấp quyền
apply, tạo role, publish image hay chạy window AWS.

# Decision

## 1. Ownership của shared RDS (D1)

1. Terraform sở hữu RDS instance, DB subnet group, security group và secret
   master do RDS quản lý, trong module `shared-rds`, sau cờ
   `enable_rag_platform` (mặc định `false`).
2. Instance được tạo và xoá cùng mỗi window đã duyệt; không giữ giữa các window.
3. Crossplane không có CRD, provider hay quyền IAM nào cho RDS.
   `provider-aws-rds` vẫn không được chọn.
4. Không request `RAGSandbox` nào gọi RDS API (ADR-0004 mục 2).

## 2. Ba tầng credential PostgreSQL (D4)

1. **Master**: secret do RDS quản lý. Chỉ Job `db-init` dùng, một lần mỗi
   window, để cài pgvector, tạo database `rag` và role `rag_bootstrap`.
2. **Bootstrap**: `rag_bootstrap` có `CREATEROLE` và `CREATE` trên database
   `rag`, không phải superuser. Job `bootstrap` và `cleanup` dùng nó để tạo hoặc
   xoá schema, login role và secret của từng sandbox.
3. **Sandbox**: một login role cho mỗi sandbox, chỉ có quyền trên schema của
   nó. Đây là credential duy nhất app nhận.
4. Master và bootstrap chỉ tồn tại trong namespace `zdr-platform`. Job
   `db-init`, `bootstrap`, `cleanup` và ServiceAccount của chúng không bao giờ
   chạy trong namespace tenant, kể cả khi làm phương án dự phòng (SPEC §1 giới
   hạn 3, §10).

## 3. Cách lấy secret (D5)

1. Nguồn sự thật là AWS Secrets Manager.
2. Workload đọc secret bằng một lệnh AWS SDK trực tiếp, xác thực qua IRSA. Tên
   secret được truyền vào (ví dụ `DB_SECRET_ID`); giá trị không đi qua Git,
   manifest hay Kubernetes Secret.
3. Không cài External Secrets Operator hay Secrets Store CSI driver.
4. Khi secret chưa có, hoặc gặp lỗi xác thực/kết nối, app đọc lại secret và kết
   nối lại. Bootstrap chạy lại giữ nguyên mật khẩu nếu secret sandbox đã có.
5. Đọc được secret không có nghĩa PostgreSQL cho phép; quyền dữ liệu do role và
   GRANT quyết định (THREAT_MODEL §6.5).

## 4. Ranh giới IAM của workload (D6, D7)

1. Terraform tạo sẵn mọi IAM role của P4 trong module `rag-identity`:
   - `zero-drift-rag-db-admin`: đọc secret master, ghi secret bootstrap; chỉ tin
     ServiceAccount `rag-db-admin` trong `zdr-platform`.
   - `zero-drift-rag-bootstrap`: đọc secret bootstrap, quản lý secret dưới
     `zero-drift/rag/tenant-*/`; chỉ tin ServiceAccount `rag-bootstrap` trong
     `zdr-platform`.
   - `zero-drift-rag-tenant-a` và `zero-drift-rag-tenant-b`: đọc secret, bucket
     và object của đúng tenant đó; trust subject
     `system:serviceaccount:<tenant>:rag-*`.
   - Role S3 của Crossplane cho bucket `zero-drift-rag-*`, có thêm quyền xoá
     object trên các bucket đó để `forceDestroy` hoạt động.
2. Crossplane không có quyền IAM; `provider-aws-iam` không được chọn.
3. Mọi statement dùng allowlist action chính xác, không wildcard action, không
   action IAM (bài học P3: resource `arn:aws:s3:::<prefix>*` khớp cả object).
4. Tenant của một request là namespace của nó (D11). Namespace ngoài
   `tenant-a`/`tenant-b` không có role.

# Alternatives considered

| Quyết định | Phương án khác | Vì sao không chọn |
|---|---|---|
| Owner của RDS | `provider-aws-rds` qua Crossplane | Thêm CRD trên node nhỏ; Crossplane cần quyền RDS và IAM; không cần vì RDS không nằm trong đường đi của request |
| Lấy secret | External Secrets Operator | Thêm controller, CRD và một nơi giữ bản sao secret (Kubernetes Secret) |
| Lấy secret | Secrets Store CSI driver | Thêm DaemonSet và driver; secret nằm trên filesystem của Pod |
| IAM workload | `provider-aws-iam` với permissions boundary | Đưa quản lý IAM vào đường đi của request; PoC chỉ có hai tenant |
| Bootstrap | Dùng thẳng master | Bị loại theo ADR-0004 mục 4–5 |
| Bucket | Một bucket chung, mỗi sandbox một prefix | Giữ được quyền provider chỉ ở mức bucket nhưng làm mất đường Crossplane đã chứng minh ở P3; owner đã chọn D7 |

# Consequences

## Positive

- Một owner cho mỗi tài nguyên: Terraform giữ RDS và IAM, Crossplane giữ bucket
  sandbox (ADR-0003).
- Không controller mới; số thành phần phải pin, giám sát và gỡ không tăng.
- Không Kubernetes Secret nào chứa mật khẩu database.
- Credential bootstrap không chạm tới namespace tenant.

## Trade-offs

- Code app phải tự đọc secret và xử lý đọc lại; không có đồng bộ tự động.
- Thêm tenant thứ ba cần sửa Terraform và một window mới.
- Secret do Job tạo nằm ngoài Terraform state; cleanup bỏ sót thì secret còn
  tính tiền, nên inventory phải liệt kê chúng.
- Quyền xoá object của provider S3 rộng hơn P3, giới hạn trong `zero-drift-rag-*`.
- Schema dùng chung instance vẫn là soft isolation (ADR-0004).

## Security consequences

- Lộ credential sandbox: chỉ đọc/ghi được schema của sandbox đó.
- Lộ credential bootstrap: tạo và xoá được role/schema sandbox trong database
  `rag`, không đọc được master, không là superuser.
- Lộ master: toàn quyền instance; vì vậy master chỉ dùng một lần và chỉ trong
  `zdr-platform`.
- Lộ token IRSA của tenant: chỉ tới secret và bucket của tenant đó.

## Cost consequences

- RDS chỉ chạy trong window; trần 5 USD cho toàn bộ P4 (D10).
- Secrets Manager tính theo secret và theo lần gọi; mỗi sandbox thêm một secret.

# Evidence

- [SPEC-P4](../specs/SPEC-P4_RAG_SANDBOX.md) §1, §9.1 (owner approval), §9.4
  (Codex review 1–3), §10.
- ADR-0003, ADR-0004, ADR-0006.
- SYSTEM_DESIGN §6.2–6.3, §7.1; THREAT_MODEL §6.4–6.5.

Đây là design evidence. Chưa có runtime evidence cho IRSA, Secrets Manager hay
RDS; các dòng đó lên `RUNTIME_VERIFIED` chỉ sau P4-T4.1 trên EKS.

# Independent review

**Codex, 14/11/2026.** PR #34, revision
`8036e44022262fa67c3946e10df89b7d1118f4fb`. Verdict: `APPROVE`; no BLOCKER,
MAJOR, MINOR or NIT in scope. Reviewer findings: ADR-0008 records D1 and D4–D7
as approved, adds no new decision and does not contradict ADR-0003/0004/0006;
platform Jobs, ServiceAccounts and credentials stay in `zdr-platform` and the
SPEC §10 L2 stop is kept; the updated rows in SYSTEM_DESIGN, THREAT_MODEL,
VERSION_MATRIX and ADR-0004 keep design decisions apart from runtime
`UNVERIFIED`; no account ID, real ARN, endpoint or credential in the seven
changed files. Checks: `git diff --check 7dcaa44 8036e44` and
`check-context.sh` PASS; file references valid. Limit: document review only, no
runtime proof; no file, commit, AWS call or Linear change.

Owner acceptance of the text: pending.

# Revisit conditions

- Lab kind P4-T3.2 cho thấy kro v0.9.4 không chạy được Job ngoài namespace
  instance hoặc `readyWhen` trên Job (SPEC §10 dừng gate).
- Test âm P4-T4.1 phần D cho thấy tenant đọc được secret, schema hay bucket của
  tenant khác, hoặc dùng được identity bootstrap.
- Số tenant vượt hai, hoặc cần tạo IAM theo từng request.
- Yêu cầu xoay mật khẩu tự động hoặc đồng bộ secret vào Kubernetes.
- R1 least privilege thay đổi quyền của role Terraform với RDS hay IAM.

# Guardrails

- Không ghi account ID, ARN role, endpoint RDS hay giá trị secret vào Git,
  Linear hay evidence.
- Không gọi kết quả là hard isolation.
- Không tuyên bố ADR này đã được kiểm chứng runtime trước khi có evidence L3.
