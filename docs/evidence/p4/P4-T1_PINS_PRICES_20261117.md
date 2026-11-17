# DRF-40 (P4-T1 phần B) — Pin RDS, giá và digest (17/11/2026)

SPEC: `.agent/specs/SPEC-P4_RAG_SANDBOX.md` §5 P4-T1 phần B, D2 và D10 ở §9.1.
Runbook để tự làm lại: `docs/runbooks/P4_PINS_AND_PRICES.md`.

- **Mục 1–5 (AWS):** owner tự gõ AWS CLI v2 chỉ đọc trong phiên MFA profile
  `zdr-bootstrap` (assumed-role `zero-drift-bootstrap`), `us-east-1`, ngày 17/11/2026
  khoảng 10:52 giờ máy owner. Không tạo, sửa hay xóa tài nguyên nào.
- **Mục 6 (image):** Claude đọc manifest trên Docker Hub bằng `docker buildx imagetools
  inspect` và đọc tài liệu AWS. Không cần credential.
- Output đã redaction: account ID chỉ xuất hiện ở dòng nhắc MFA và prompt shell, không
  được chép vào đây.

**Kết quả: PASS.** Mọi giá trị khớp dự đoán, không giá nào lệch COST_PLAN §5.2.
D2 giữ nguyên, không cần fallback lớp to hơn.

## 1. PostgreSQL 17 ở `us-east-1`

`aws rds describe-db-engine-versions --engine postgres`, lọc `17.`:

| Version | Status | Family |
|---|---|---|
| 17.7 | available | postgres17 |
| 17.8 | available | postgres17 |
| 17.9 | available | postgres17 |
| 17.10 | available | postgres17 |
| 17.11 | available | postgres17 |

`--engine-version 17 --default-only` trả về **17.9**. Đây là bản mặc định khi không
pin, khác bản mới nhất. SPEC D2 yêu cầu pin bản mới nhất, nên **pin là 17.11**.
Terraform phải ghi `engine_version = "17.11"` tường minh và không dựa vào mặc định.

## 2. `db.t4g.micro` đặt được với 17.11

`describe-orderable-db-instance-options --engine-version 17.11 --db-instance-class db.t4g.micro`:

| Class | Storage | MultiAZCapable | Số AZ |
|---|---|---|---|
| db.t4g.micro | gp2 | True | 5 |
| db.t4g.micro | **gp3** | True | 5 |
| db.t4g.micro | io1 | True | 5 |
| db.t4g.micro | io2 | True | 5 |

Có gp3, và lớp này có ở 5 AZ. Subnet group của P4 phải nằm trong các AZ đó; DRF-46 kiểm
lại khi chọn subnet.

## 3. TLS mặc định

| Mục | Giá trị | Ý nghĩa cho P4 |
|---|---|---|
| `rds.force_ssl` (family `postgres17`, mặc định) | `1`, modifiable `True` | Kết nối không TLS bị từ chối ngay với parameter group mặc định. P4 không được hạ về `0` |
| CA mặc định cho instance mới | `rds-ca-rsa2048-g1` | App tin CA này qua bundle ở mục 4, dùng `sslmode=verify-full` |

## 4. CA bundle của RDS

| File | Nguồn | sha256 |
|---|---|---|
| `us-east-1-bundle.pem` | `https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem` | `b1711d12bae51838581281e23b6cb97b1074016873b4dafc80ed14002462dd77` |

Lần chạy này không lưu số chứng chỉ (`grep -c`), vì lệnh không `tee` ra file. Cái thiếu
này không ảnh hưởng tới pin: image app (DRF-50) sẽ kiểm sha256 trên khi build. AWS có thể
thay bundle khi xoay vòng CA; khi đó checksum đổi, build báo lỗi và phải pin lại có ghi
ngày.

## 5. Giá, AWS Price List API, `us-east-1`, 17/11/2026

| Khoản | usagetype | Đơn giá | COST_PLAN §5.2 | Kết quả |
|---|---|---|---|---|
| RDS PostgreSQL `db.t4g.micro` Single-AZ | `InstanceUsage:db.t4g.micro` | 0.016 USD/giờ | 0.016 | Khớp |
| RDS PostgreSQL gp3 | `RDS:GP3-Storage` | 0.115 USD/GB-tháng | 0.115 | Khớp |
| Secrets Manager, mỗi secret | `USE1-AWSSecretsManager-Secrets` | 0.40 USD/secret-tháng | chưa có dòng | Thêm vào §5.2 |
| Secrets Manager, API | `USE1-AWSSecretsManagerAPIRequest` | 0.05 USD / 10 000 request | chưa có dòng | Thêm vào §5.2 |

Dòng `UnusedBox:db.t4g.micro` là giờ reservation không dùng, P4 không dùng reservation.

Tính thử phần RDS và secret mỗi giờ window (chia đều 730 giờ/tháng, đây là giả định
prorate, không phải hóa đơn):

- Instance 0.016 + gp3 `20 × 0.115 / 730` ≈ 0.0032 → **≈ 0.019 USD/giờ**.
- Secret: ước tối đa 6 (master, `rag_bootstrap`, tối đa 4 secret sandbox) × `0.40 / 730`
  ≈ **0.0033 USD/giờ**; API call ở mức vài trăm lần mỗi window nên ≈ 0.
- Kết luận: số khoảng 0.35 USD/giờ của D10 đã bao gồm RDS và vẫn đúng; trần 5 USD không đổi.

Chưa kiểm ở đây và để lại cho DRF-46: cách Secrets Manager tính tiền secret đang chờ xóa,
và việc teardown phải xóa ngay (`recovery_window_in_days = 0`), để inventory sau window
không còn secret nào.

## 6. Digest image (Claude, 17/11/2026)

| Image | Tag | Index digest | Ghi chú |
|---|---|---|---|
| Python nền của app | `python:3.13-slim` (= `3.13-slim-trixie`) | `sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90` | `PYTHON_VERSION=3.13.18` |
| PostgreSQL + pgvector cho kind | `pgvector/pgvector:0.8.2-pg17` | `sha256:feb68f4f15446397d8cac7f4fe48fe4586de83160d1fc48b46283312d1a33966` | `PG_VERSION=17.10-1.pgdg12+1` (bookworm); amd64 + arm64 |

Pin theo index digest (đa kiến trúc), không theo digest của một platform.

pgvector trên RDS: bảng extension của PostgreSQL 17 trong tài liệu AWS
(`AmazonRDS/latest/PostgreSQLReleaseNotes/postgresql-extensions.html`, đọc 17/11) ghi
17.11 → pgvector **0.8.2**, 17.10 → 0.8.2, 17.8–17.9 → 0.8.1. Trạng thái `DOC_VERIFIED`.
Phải đọc lại bằng `SELECT extversion FROM pg_extension WHERE extname = 'vector'` trên
instance thật ở window L3 (DRF-56).

## 7. Khác biệt kind và RDS

| Mục | kind (DRF-45) | RDS (DRF-46/56) | Đánh giá |
|---|---|---|---|
| PostgreSQL | 17.10 | 17.11 | Cùng major; khác minor không đổi SQL mà P4 dùng. Chấp nhận, ghi lại |
| pgvector | 0.8.2 | 0.8.2 (doc) | Khớp |
| TLS | Image không bật TLS mặc định | `rds.force_ssl=1`, CA RDS | Lab kind phải bật TLS bằng CA tự ký nếu muốn thử `verify-full`; nếu không, TLS chỉ được chứng minh ở L3 |
| Superuser | Có `postgres` | Master không phải superuser (`rds_superuser`) | Giới hạn đã ghi ở SPEC P4-T2.1. Gợi ý cho DRF-45, không bắt buộc: chạy `db-init` bằng một role không superuser có `CREATEROLE` và `CREATEDB` để bắt lệnh cần superuser thật ngay trên kind |

## Giới hạn

- Giá là đơn giá list On-Demand, chưa trừ credit, không chứng minh capacity hay hóa đơn.
- `ACCOUNT_VERIFIED` chỉ áp dụng cho mục 1–3, ngày 17/11/2026. AWS có thể thêm minor hay
  đổi mặc định; kiểm lại trong plan của window L3.
- Không có review của Codex cho file này.
