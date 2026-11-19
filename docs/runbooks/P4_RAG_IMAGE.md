# P4 — App `serve` và image RAGSandbox (DRF-50, P4-T3.1)

Runbook để tự làm lại. Không có AWS, không có credential thật. Chỉ dùng Docker
local, cộng GitHub Actions ở mục C.
Code: `workloads/rag-sandbox/` (README có bảng endpoint và biến môi trường).

## Bức tranh

Một request `RAGSandbox` sau này (DRF-51) sẽ chạy image này hai lần:
- Job `bootstrap` trong `zdr-platform`, tạo schema, role và secret;
- Deployment `serve` trong namespace của tenant, đọc secret đó và trả lời `/readyz`.

kro chỉ coi instance là Ready khi `/readyz` trả 200. Vì vậy `/readyz` phải kiểm
thật hai thứ: truy vấn được bảng có cột `vector`, và với tới được bucket.

## A. Kiểm local (Git Bash, ~3 phút)

```bash
cd /r/_Projects/Eurus_Workspace/Zero-D-Rift
bash workloads/rag-sandbox/test.sh --integration
bash workloads/rag-sandbox/smoke.sh
```

**Phải thấy:**
- `test.sh`: `117 passed`.
- `smoke.sh`: kết thúc bằng `SMOKE PASS`. Smoke tự dừng với `FAIL: …` (exit khác 0)
  nếu có một mã trả về sai: 200/200/200/400 lúc DB chạy, `/healthz` 200 và `/readyz`
  503 lúc DB tắt, `/readyz` 200 sau khi bật lại. Nó cũng dừng nếu `/readyz` nhắc tên
  host database.

`smoke.sh` tự dọn mọi container, volume và network nó tạo. Image `ragsandbox:smoke`
vẫn còn; xoá bằng `docker image rm ragsandbox:smoke`.

## B. Đọc output của `smoke.sh`, đoán trước khi chạy

| Bước | Dự đoán (ghi trước) | Phải thấy |
|---|---|---|
| user và root filesystem | uid là gì? `touch /probe` có được không? | `10001`; `Read-only file system` |
| CA bundle | sha256 có khớp VERSION_MATRIX §8 không? có mấy cert? | `b1711d12…2462dd77`; `3` |
| `/readyz` | `bucket` là gì khi `BUCKET_CHECK=off`? | `"bucket": "skipped"`, `"ready": true` |
| `/query?v=1,0,0,0&k=2` | hai id nào gần nhất? | `1` (dist 0), `5` (≈0.141) |
| tắt database | `/healthz` và `/readyz` trả gì? lý do lỗi có tên host không? | `/healthz` 200; `/readyz` 503, `"db": "error: OperationalError: host not resolved"`, không có tên host |
| bật lại database | có cần restart app không? | không; `/readyz` tự về 200 |

`/healthz` không kiểm database. Lý do: nếu nó kiểm, một lần database chết sẽ làm
Kubernetes restart mọi Pod app, mà restart không sửa được database.

## C. Publish lên GHCR (D8, owner đã duyệt 14/11)

Workflow `.github/workflows/rag-sandbox-image.yml`:
- trên PR: chạy test và smoke, **không push**, không có token ghi;
- trên `main`: chạy lại test, rồi push `ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox:sha-<commit>`.

Các bước:
1. Merge PR. Đây là lần publish đầu tiên, nên merge chính là bước owner đồng ý push.
2. Vào tab Actions, mở run `rag-sandbox-image` của commit merge. Ở Summary có dòng
   `Image: ghcr.io/…@sha256:…`.
3. Package mới trên GHCR mặc định là **private**. Vào
   `github.com/EurusDevSec?tab=packages` → `zero-d-rift/rag-sandbox` → Package
   settings → Change visibility → Public. Bước này công khai image, nên owner tự làm.
4. Kiểm tra không cần đăng nhập:

   ```bash
   docker logout ghcr.io
   docker pull ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox@sha256:<digest>
   bash workloads/rag-sandbox/smoke.sh ghcr.io/eurusdevsec/zero-d-rift/rag-sandbox@sha256:<digest>
   ```

5. Ghi digest vào `docs/VERSION_MATRIX.md` §8, dòng "RAGSandbox image", bằng một PR
   nhỏ. Từ đó mọi manifest dùng `@sha256:<digest>`, không dùng tag.

**Undo:** Package settings → xoá version (hoặc xoá cả package). Image không có
secret, nên để công khai không lộ gì; xoá chỉ làm DRF-51 mất image để kéo.

## Tự thử (không bắt buộc)

- Đổi một hash trong `requirements.txt` rồi build: `pip` phải dừng với
  `THESE PACKAGES DO NOT MATCH THE HASHES`.
- Đổi một chữ số trong `--checksum` của `Dockerfile`: build phải lỗi ở bước `ADD`.
- Chạy `serve` thiếu `S3_BUCKET` mà không có `BUCKET_CHECK=off`: exit 2,
  `invalid configuration: S3_BUCKET is not set`.

## Giới hạn

- `smoke.sh` chạy không TLS (`DB_SSLMODE=disable`), secret dạng file, không bucket.
  `verify-full`, IRSA, Secrets Manager và `HeadBucket` thật chỉ được chứng minh ở L3.
- Image chỉ build cho `linux/amd64` (node EKS là `AL2023_x86_64_STANDARD`).
